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
    if (![data isKindOfClass:NSData.class] || data.length > 256 * 1024) return nil;
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!source) return nil;
    NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
    CFRelease(source);
    NSNumber *width = properties[(NSString *)kCGImagePropertyPixelWidth];
    NSNumber *height = properties[(NSString *)kCGImagePropertyPixelHeight];
    if (width.integerValue <= 0 || height.integerValue <= 0 || width.integerValue > 512 || height.integerValue > 512) {
        return nil;
    }
    return data;
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
