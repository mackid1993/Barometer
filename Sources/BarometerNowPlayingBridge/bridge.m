#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <dlfcn.h>

typedef void (^DictionaryCallback)(NSDictionary *);
typedef void (^BooleanCallback)(BOOL);
typedef void (^StringCallback)(NSString *);
typedef void (*GetDictionary)(dispatch_queue_t, DictionaryCallback);
typedef void (*GetBoolean)(dispatch_queue_t, BooleanCallback);
typedef void (*GetString)(dispatch_queue_t, StringCallback);

static NSData *boundedArtwork(NSData *data) {
    if (![data isKindOfClass:NSData.class] || data.length > 16 * 1024 * 1024) return nil;
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!source) return nil;
    NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
    NSNumber *width = properties[(NSString *)kCGImagePropertyPixelWidth];
    NSNumber *height = properties[(NSString *)kCGImagePropertyPixelHeight];
    NSInteger pixelWidth = width.integerValue;
    NSInteger pixelHeight = height.integerValue;
    if (pixelWidth <= 0 || pixelHeight <= 0 || pixelWidth > 16384 || pixelHeight > 16384
        || pixelWidth * pixelHeight > 64 * 1024 * 1024) {
        CFRelease(source);
        return nil;
    }
    if (data.length <= 256 * 1024 && pixelWidth <= 512 && pixelHeight <= 512) {
        CFRelease(source);
        return data;
    }
    NSDictionary *thumbnailOptions = @{
        (NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES,
        (NSString *)kCGImageSourceThumbnailMaxPixelSize: @512,
    };
    CGImageRef thumbnail = CGImageSourceCreateThumbnailAtIndex(
        source, 0, (__bridge CFDictionaryRef)thumbnailOptions);
    CFRelease(source);
    if (!thumbnail) return nil;
    for (NSNumber *quality in @[@0.85, @0.70, @0.55, @0.40]) {
        NSMutableData *output = [NSMutableData data];
        CGImageDestinationRef destination = CGImageDestinationCreateWithData(
            (__bridge CFMutableDataRef)output, CFSTR("public.jpeg"), 1, NULL);
        if (!destination) break;
        CGImageDestinationAddImage(destination, thumbnail,
            (__bridge CFDictionaryRef)@{(NSString *)kCGImageDestinationLossyCompressionQuality: quality});
        BOOL finalized = CGImageDestinationFinalize(destination);
        CFRelease(destination);
        if (finalized && output.length <= 256 * 1024) {
            CGImageRelease(thumbnail);
            return output;
        }
    }
    CGImageRelease(thumbnail);
    return nil;
}

__attribute__((visibility("default"))) void barometer_now_playing_get(void) {
    @autoreleasepool {
        void *handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW | RTLD_LOCAL);
        if (!handle) { puts("{\"available\":false}"); return; }
        GetDictionary getInfo = (GetDictionary)dlsym(handle, "MRMediaRemoteGetNowPlayingInfo");
        GetBoolean getPlaying = (GetBoolean)dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
        GetString getBundle = (GetString)dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationDisplayID");
        if (!getInfo || !getPlaying || !getBundle) { puts("{\"available\":false}"); return; }

        dispatch_group_t group = dispatch_group_create();
        dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
        __block NSDictionary *information = nil;
        __block NSNumber *playing = nil;
        __block NSString *bundleIdentifier = nil;
        dispatch_group_enter(group); getInfo(queue, ^(NSDictionary *value) { information = value; dispatch_group_leave(group); });
        dispatch_group_enter(group); getPlaying(queue, ^(BOOL value) { playing = @(value); dispatch_group_leave(group); });
        dispatch_group_enter(group); getBundle(queue, ^(NSString *value) { bundleIdentifier = value; dispatch_group_leave(group); });
        if (dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)) != 0) {
            puts("{\"available\":false}"); return;
        }
        if (information.count == 0) { puts("{\"available\":true,\"idle\":true}"); return; }

        NSMutableDictionary *output = [@{ @"available": @YES, @"idle": @NO } mutableCopy];
        NSDictionary *mapping = @{
            @"title": @"kMRMediaRemoteNowPlayingInfoTitle", @"artist": @"kMRMediaRemoteNowPlayingInfoArtist",
            @"album": @"kMRMediaRemoteNowPlayingInfoAlbum", @"duration": @"kMRMediaRemoteNowPlayingInfoDuration",
            @"elapsedTime": @"kMRMediaRemoteNowPlayingInfoElapsedTime"
        };
        [mapping enumerateKeysAndObjectsUsingBlock:^(NSString *destination, NSString *source, BOOL *stop) {
            id value = information[source]; if (value) output[destination] = value;
        }];
        output[@"playing"] = playing ?: @NO;
        if (bundleIdentifier.length) output[@"bundleIdentifier"] = bundleIdentifier;
        NSData *artwork = boundedArtwork(information[@"kMRMediaRemoteNowPlayingInfoArtworkData"]);
        if (artwork) output[@"artworkData"] = [artwork base64EncodedStringWithOptions:0];
        NSData *json = [NSJSONSerialization dataWithJSONObject:output options:0 error:nil];
        if (!json || json.length > 512 * 1024) { puts("{\"available\":false}"); return; }
        fwrite(json.bytes, 1, json.length, stdout); fputc('\n', stdout); fflush(stdout);
    }
}
