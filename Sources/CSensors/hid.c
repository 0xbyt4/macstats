#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/hidsystem/IOHIDEventSystemClient.h>
#include <IOKit/hidsystem/IOHIDServiceClient.h>
#include <string.h>

#include "CSensors.h"

// Private IOKit HID functions. They are exported by IOKit but have no public header.
typedef struct __IOHIDEvent *IOHIDEventRef;
extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
extern int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef match);
extern IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service, int64_t type,
                                                 int32_t options, int64_t timestamp);
extern double IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);

#define CS_HID_EVENT_TYPE_TEMPERATURE 15
#define CS_HID_FIELD_BASE(type) ((type) << 16)
#define CS_HID_PAGE_APPLE_VENDOR 0xff00
#define CS_HID_USAGE_TEMPERATURE 5

static IOHIDEventSystemClientRef g_client = NULL;

static IOHIDEventSystemClientRef hid_client(void) {
    if (g_client != NULL) {
        return g_client;
    }
    IOHIDEventSystemClientRef client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (client == NULL) {
        return NULL;
    }

    int page = CS_HID_PAGE_APPLE_VENDOR;
    int usage = CS_HID_USAGE_TEMPERATURE;
    CFNumberRef page_num = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &page);
    CFNumberRef usage_num = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &usage);
    const void *keys[] = {CFSTR("PrimaryUsagePage"), CFSTR("PrimaryUsage")};
    const void *values[] = {page_num, usage_num};
    CFDictionaryRef match = CFDictionaryCreate(kCFAllocatorDefault, keys, values, 2,
                                               &kCFTypeDictionaryKeyCallBacks,
                                               &kCFTypeDictionaryValueCallBacks);
    IOHIDEventSystemClientSetMatching(client, match);
    CFRelease(match);
    CFRelease(page_num);
    CFRelease(usage_num);

    g_client = client;
    return g_client;
}

#define CS_HID_MAX_PREFIXES 16

/// Returns the index of the first prefix that `name` starts with, or -1.
static int match_prefix(const char *name, const char *const *prefixes, int prefix_count) {
    for (int p = 0; p < prefix_count; p++) {
        if (strncmp(name, prefixes[p], strlen(prefixes[p])) == 0) {
            return p;
        }
    }
    return -1;
}

int cs_hid_temperatures(const char *const *prefixes, int prefix_count, int first_only,
                        cs_temp_reading *out, int max) {
    if (prefix_count < 0 || prefix_count > CS_HID_MAX_PREFIXES) {
        return -1;
    }
    IOHIDEventSystemClientRef client = hid_client();
    if (client == NULL) {
        return -1;
    }
    CFArrayRef services = IOHIDEventSystemClientCopyServices(client);
    if (services == NULL) {
        return -1;
    }

    int found[CS_HID_MAX_PREFIXES] = {0};
    int written = 0;
    CFIndex count = CFArrayGetCount(services);
    for (CFIndex i = 0; i < count && written < max; i++) {
        IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, i);
        if (service == NULL) {
            continue;
        }

        char name[64] = {0};
        CFTypeRef product = IOHIDServiceClientCopyProperty(service, CFSTR("Product"));
        if (product != NULL && CFGetTypeID(product) == CFStringGetTypeID()) {
            CFStringGetCString((CFStringRef)product, name, sizeof(name), kCFStringEncodingUTF8);
        } else {
            strncpy(name, "unknown", sizeof(name) - 1);
        }
        if (product != NULL) {
            CFRelease(product);
        }

        if (prefix_count > 0) {
            int p = match_prefix(name, prefixes, prefix_count);
            if (p < 0 || (first_only && found[p])) {
                continue;
            }
            found[p] = 1;
        }

        IOHIDEventRef event = IOHIDServiceClientCopyEvent(service, CS_HID_EVENT_TYPE_TEMPERATURE, 0, 0);
        if (event == NULL) {
            continue;
        }
        double value = IOHIDEventGetFloatValue(event, CS_HID_FIELD_BASE(CS_HID_EVENT_TYPE_TEMPERATURE));
        CFRelease(event);

        memcpy(out[written].name, name, sizeof(name));
        out[written].celsius = value;
        written++;
    }
    CFRelease(services);
    return written;
}
