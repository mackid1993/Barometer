#ifndef CSYSTEMSOURCES_H
#define CSYSTEMSOURCES_H

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/hidsystem/IOHIDEventSystemClient.h>
#include <IOKit/hidsystem/IOHIDServiceClient.h>
#include <stdint.h>

int mbs_system_sources_available(void);

// MARK: - IOHID event sensors

typedef struct __IOHIDEvent *MBSIOHIDEventRef;

#define MBS_IOHID_EVENT_TYPE_TEMPERATURE 15
#define MBS_IOHID_EVENT_TYPE_POWER 25
#define MBS_IOHID_EVENT_FIELD_BASE(type) ((int32_t)(type) << 16)

IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef matching);
MBSIOHIDEventRef IOHIDServiceClientCopyEvent(
    IOHIDServiceClientRef service,
    int64_t type,
    int32_t options,
    int64_t timestamp
);
double IOHIDEventGetFloatValue(MBSIOHIDEventRef event, int32_t field);

// MARK: - IOReport

typedef struct IOReportSubscriptionRef *MBSIOReportSubscriptionRef;

CFDictionaryRef IOReportCopyChannelsInGroup(
    CFStringRef group,
    CFStringRef subgroup,
    uint64_t channelID,
    uint64_t options,
    uint64_t reserved
);
void IOReportMergeChannels(CFDictionaryRef destination, CFDictionaryRef source, CFTypeRef options);
MBSIOReportSubscriptionRef IOReportCreateSubscription(
    void *allocator,
    CFMutableDictionaryRef channels,
    CFMutableDictionaryRef *subscribedChannels,
    uint64_t options,
    CFTypeRef reserved
);
CFDictionaryRef IOReportCreateSamples(
    MBSIOReportSubscriptionRef subscription,
    CFMutableDictionaryRef channels,
    CFTypeRef options
);
CFDictionaryRef IOReportCreateSamplesDelta(
    CFDictionaryRef previous,
    CFDictionaryRef current,
    CFTypeRef options
);
CFStringRef IOReportChannelGetGroup(CFDictionaryRef channel);
CFStringRef IOReportChannelGetSubGroup(CFDictionaryRef channel);
CFStringRef IOReportChannelGetChannelName(CFDictionaryRef channel);
CFStringRef IOReportChannelGetUnitLabel(CFDictionaryRef channel);
int64_t IOReportSimpleGetIntegerValue(CFDictionaryRef channel, int32_t index);
int32_t IOReportStateGetCount(CFDictionaryRef channel);
CFStringRef IOReportStateGetNameForIndex(CFDictionaryRef channel, int32_t index);
int64_t IOReportStateGetResidency(CFDictionaryRef channel, int32_t index);

// MARK: - AppleSMC external-method ABI

#define MBS_SMC_SELECTOR 2
#define MBS_SMC_COMMAND_READ_BYTES 5
#define MBS_SMC_COMMAND_READ_INDEX 8
#define MBS_SMC_COMMAND_READ_KEY_INFO 9

typedef struct {
    uint8_t major;
    uint8_t minor;
    uint8_t build;
    uint8_t reserved;
    uint16_t release;
} MBSSMCVersion;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memoryPLimit;
} MBSSMCPowerLimitData;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t dataAttributes;
} MBSSMCKeyInfo;

typedef struct {
    uint32_t key;
    MBSSMCVersion version;
    MBSSMCPowerLimitData powerLimitData;
    MBSSMCKeyInfo keyInfo;
    uint8_t result;
    uint8_t status;
    uint8_t data8;
    uint32_t data32;
    uint8_t bytes[32];
} MBSSMCKeyData;

#endif
