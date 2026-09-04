#include "CSystemSources.h"
#include <dlfcn.h>
#include <pthread.h>

static void *mbs_ioreport_handle;
static pthread_once_t mbs_ioreport_once = PTHREAD_ONCE_INIT;

static void mbs_open_ioreport(void) {
    mbs_ioreport_handle = dlopen("/usr/lib/libIOReport.dylib", RTLD_LAZY | RTLD_LOCAL);
}

static void *mbs_ioreport_symbol(const char *name) {
    pthread_once(&mbs_ioreport_once, mbs_open_ioreport);
    if (mbs_ioreport_handle == NULL) {
        return NULL;
    }
    return dlsym(mbs_ioreport_handle, name);
}

int mbs_system_sources_available(void) {
    return 1;
}

int32_t mbs_iohid_event_field_base(int64_t type) {
    return MBS_IOHID_EVENT_FIELD_BASE(type);
}

void mbs_iohid_event_release(MBSIOHIDEventRef event) {
    if (event != NULL) {
        CFRelease(event);
    }
}

void mbs_ioreport_subscription_release(MBSIOReportSubscriptionRef subscription) {
    if (subscription != NULL) {
        CFRelease(subscription);
    }
}

CFDictionaryRef mbs_ioreport_copy_channels_in_group(CFStringRef group, CFStringRef subgroup) {
    typedef CFDictionaryRef (*Function)(CFStringRef, CFStringRef, uint64_t, uint64_t, uint64_t);
    Function function = (Function)mbs_ioreport_symbol("IOReportCopyChannelsInGroup");
    return function == NULL ? NULL : function(group, subgroup, 0, 0, 0);
}

void mbs_ioreport_merge_channels(CFDictionaryRef destination, CFDictionaryRef source) {
    typedef void (*Function)(CFDictionaryRef, CFDictionaryRef, CFTypeRef);
    Function function = (Function)mbs_ioreport_symbol("IOReportMergeChannels");
    if (function != NULL) {
        function(destination, source, NULL);
    }
}

MBSIOReportSubscriptionRef mbs_ioreport_create_subscription(
    CFMutableDictionaryRef channels,
    CFMutableDictionaryRef *subscribedChannels
) {
    typedef MBSIOReportSubscriptionRef (*Function)(
        void *,
        CFMutableDictionaryRef,
        CFMutableDictionaryRef *,
        uint64_t,
        CFTypeRef
    );
    Function function = (Function)mbs_ioreport_symbol("IOReportCreateSubscription");
    return function == NULL ? NULL : function(NULL, channels, subscribedChannels, 0, NULL);
}

CFDictionaryRef mbs_ioreport_create_samples(
    MBSIOReportSubscriptionRef subscription,
    CFMutableDictionaryRef channels
) {
    typedef CFDictionaryRef (*Function)(MBSIOReportSubscriptionRef, CFMutableDictionaryRef, CFTypeRef);
    Function function = (Function)mbs_ioreport_symbol("IOReportCreateSamples");
    return function == NULL ? NULL : function(subscription, channels, NULL);
}

CFDictionaryRef mbs_ioreport_create_samples_delta(CFDictionaryRef previous, CFDictionaryRef current) {
    typedef CFDictionaryRef (*Function)(CFDictionaryRef, CFDictionaryRef, CFTypeRef);
    Function function = (Function)mbs_ioreport_symbol("IOReportCreateSamplesDelta");
    return function == NULL ? NULL : function(previous, current, NULL);
}

CFStringRef mbs_ioreport_channel_get_group(CFDictionaryRef channel) {
    typedef CFStringRef (*Function)(CFDictionaryRef);
    Function function = (Function)mbs_ioreport_symbol("IOReportChannelGetGroup");
    return function == NULL ? NULL : function(channel);
}

CFStringRef mbs_ioreport_channel_get_subgroup(CFDictionaryRef channel) {
    typedef CFStringRef (*Function)(CFDictionaryRef);
    Function function = (Function)mbs_ioreport_symbol("IOReportChannelGetSubGroup");
    return function == NULL ? NULL : function(channel);
}

CFStringRef mbs_ioreport_channel_get_name(CFDictionaryRef channel) {
    typedef CFStringRef (*Function)(CFDictionaryRef);
    Function function = (Function)mbs_ioreport_symbol("IOReportChannelGetChannelName");
    return function == NULL ? NULL : function(channel);
}

CFStringRef mbs_ioreport_channel_get_unit_label(CFDictionaryRef channel) {
    typedef CFStringRef (*Function)(CFDictionaryRef);
    Function function = (Function)mbs_ioreport_symbol("IOReportChannelGetUnitLabel");
    return function == NULL ? NULL : function(channel);
}

int64_t mbs_ioreport_simple_get_integer_value(CFDictionaryRef channel, int32_t index) {
    typedef int64_t (*Function)(CFDictionaryRef, int32_t);
    Function function = (Function)mbs_ioreport_symbol("IOReportSimpleGetIntegerValue");
    return function == NULL ? 0 : function(channel, index);
}

int32_t mbs_ioreport_state_get_count(CFDictionaryRef channel) {
    typedef int32_t (*Function)(CFDictionaryRef);
    Function function = (Function)mbs_ioreport_symbol("IOReportStateGetCount");
    return function == NULL ? 0 : function(channel);
}

CFStringRef mbs_ioreport_state_get_name(CFDictionaryRef channel, int32_t index) {
    typedef CFStringRef (*Function)(CFDictionaryRef, int32_t);
    Function function = (Function)mbs_ioreport_symbol("IOReportStateGetNameForIndex");
    return function == NULL ? NULL : function(channel, index);
}

int64_t mbs_ioreport_state_get_residency(CFDictionaryRef channel, int32_t index) {
    typedef int64_t (*Function)(CFDictionaryRef, int32_t);
    Function function = (Function)mbs_ioreport_symbol("IOReportStateGetResidency");
    return function == NULL ? 0 : function(channel, index);
}
