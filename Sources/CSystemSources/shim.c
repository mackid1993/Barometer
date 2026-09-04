#include "CSystemSources.h"

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
