#include <IOKit/IOKitLib.h>
#include <string.h>

#include "CSensors.h"

// AppleSMC user client protocol. The layout matches the kernel structure.
#define SMC_KERNEL_INDEX 2
#define SMC_CMD_READ_BYTES 5
#define SMC_CMD_READ_INDEX 8
#define SMC_CMD_READ_KEYINFO 9

typedef struct {
    char major;
    char minor;
    char build;
    char reserved[1];
    uint16_t release;
} smc_vers_t;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpu_p_limit;
    uint32_t gpu_p_limit;
    uint32_t mem_p_limit;
} smc_plimit_t;

typedef struct {
    uint32_t data_size;
    uint32_t data_type;
    char data_attributes;
} smc_keyinfo_t;

typedef struct {
    uint32_t key;
    smc_vers_t vers;
    smc_plimit_t plimit;
    smc_keyinfo_t key_info;
    char result;
    char status;
    char data8;
    uint32_t data32;
    unsigned char bytes[32];
} smc_param_t;

static io_connect_t g_conn = 0;

static uint32_t fourcc(const char *s) {
    return ((uint32_t)(unsigned char)s[0] << 24) | ((uint32_t)(unsigned char)s[1] << 16) |
           ((uint32_t)(unsigned char)s[2] << 8) | (uint32_t)(unsigned char)s[3];
}

static void fourcc_str(uint32_t v, char *out) {
    out[0] = (char)(v >> 24);
    out[1] = (char)(v >> 16);
    out[2] = (char)(v >> 8);
    out[3] = (char)v;
    out[4] = '\0';
}

static kern_return_t smc_call(smc_param_t *in, smc_param_t *out) {
    size_t out_size = sizeof(smc_param_t);
    return IOConnectCallStructMethod(g_conn, SMC_KERNEL_INDEX, in, sizeof(smc_param_t), out, &out_size);
}

int cs_smc_open(void) {
    if (g_conn != 0) {
        return 0;
    }
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (service == 0) {
        return -1;
    }
    kern_return_t kr = IOServiceOpen(service, mach_task_self(), 0, &g_conn);
    IOObjectRelease(service);
    if (kr != KERN_SUCCESS) {
        g_conn = 0;
        return -1;
    }
    return 0;
}

void cs_smc_close(void) {
    if (g_conn != 0) {
        IOServiceClose(g_conn);
        g_conn = 0;
    }
}

// Key info does not change, so cache it. This halves the calls for each read.
#define SMC_INFO_CACHE_SIZE 256
static struct {
    uint32_t key;
    smc_keyinfo_t info;
} g_info_cache[SMC_INFO_CACHE_SIZE];
static int g_info_cache_count = 0;

static int smc_key_info(uint32_t key, smc_keyinfo_t *info) {
    for (int i = 0; i < g_info_cache_count; i++) {
        if (g_info_cache[i].key == key) {
            *info = g_info_cache[i].info;
            return 0;
        }
    }
    smc_param_t in;
    smc_param_t out;
    memset(&in, 0, sizeof(in));
    memset(&out, 0, sizeof(out));
    in.key = key;
    in.data8 = SMC_CMD_READ_KEYINFO;
    if (smc_call(&in, &out) != KERN_SUCCESS || out.result != 0) {
        return -1;
    }
    *info = out.key_info;
    if (g_info_cache_count < SMC_INFO_CACHE_SIZE) {
        g_info_cache[g_info_cache_count].key = key;
        g_info_cache[g_info_cache_count].info = out.key_info;
        g_info_cache_count++;
    }
    return 0;
}

static int smc_read(const char *key, smc_keyinfo_t *info, unsigned char *bytes) {
    if (g_conn == 0 && cs_smc_open() != 0) {
        return -1;
    }
    smc_param_t in;
    smc_param_t out;
    memset(&in, 0, sizeof(in));
    memset(&out, 0, sizeof(out));
    in.key = fourcc(key);
    if (smc_key_info(in.key, info) != 0) {
        return -1;
    }
    in.key_info.data_size = info->data_size;
    in.data8 = SMC_CMD_READ_BYTES;
    if (smc_call(&in, &out) != KERN_SUCCESS || out.result != 0) {
        return -1;
    }
    memcpy(bytes, out.bytes, sizeof(out.bytes));
    return 0;
}

int cs_smc_read_double(const char *key, double *out) {
    smc_keyinfo_t info;
    unsigned char b[32];
    if (strlen(key) != 4 || smc_read(key, &info, b) != 0) {
        return -1;
    }
    char type[5];
    fourcc_str(info.data_type, type);

    if (strcmp(type, "flt ") == 0 && info.data_size == 4) {
        float f;
        memcpy(&f, b, sizeof(f));
        *out = f;
    } else if (strcmp(type, "ui8 ") == 0) {
        *out = b[0];
    } else if (strcmp(type, "ui16") == 0) {
        *out = (double)((b[0] << 8) | b[1]);
    } else if (strcmp(type, "ui32") == 0) {
        *out = (double)(((uint32_t)b[0] << 24) | ((uint32_t)b[1] << 16) | ((uint32_t)b[2] << 8) | b[3]);
    } else if (strcmp(type, "sp78") == 0) {
        *out = (double)(int16_t)((b[0] << 8) | b[1]) / 256.0;
    } else if (strcmp(type, "fpe2") == 0) {
        *out = (double)((b[0] << 8) | b[1]) / 4.0;
    } else {
        return -1;
    }
    return 0;
}

int cs_smc_key_count(void) {
    double count = 0;
    if (cs_smc_read_double("#KEY", &count) != 0) {
        return -1;
    }
    return (int)count;
}

int cs_smc_key_at(int index, char *key, char *type) {
    if (g_conn == 0 && cs_smc_open() != 0) {
        return -1;
    }
    smc_param_t in;
    smc_param_t out;
    memset(&in, 0, sizeof(in));
    memset(&out, 0, sizeof(out));
    in.data8 = SMC_CMD_READ_INDEX;
    in.data32 = (uint32_t)index;
    if (smc_call(&in, &out) != KERN_SUCCESS || out.result != 0) {
        return -1;
    }
    fourcc_str(out.key, key);

    smc_param_t info_in;
    smc_param_t info_out;
    memset(&info_in, 0, sizeof(info_in));
    memset(&info_out, 0, sizeof(info_out));
    info_in.key = out.key;
    info_in.data8 = SMC_CMD_READ_KEYINFO;
    if (smc_call(&info_in, &info_out) != KERN_SUCCESS || info_out.result != 0) {
        return -1;
    }
    fourcc_str(info_out.key_info.data_type, type);
    return 0;
}
