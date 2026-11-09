#ifndef CSENSORS_H
#define CSENSORS_H

#include <stdint.h>

/// One temperature reading from a HID temperature sensor.
typedef struct {
    char name[64];
    double celsius;
} cs_temp_reading;

/// Reads HID temperature sensors (Apple Silicon). Each sensor read costs about 1 ms,
/// so read only the sensors you need.
/// - `prefixes`: read only sensors whose product name starts with one of these strings.
///   Pass `prefix_count` 0 to read all sensors.
/// - `first_only`: when non-zero, read only the first sensor for each prefix.
/// Writes at most `max` readings to `out`.
/// Returns the number of readings, or -1 when the HID client is not available.
int cs_hid_temperatures(const char *const *prefixes, int prefix_count, int first_only,
                        cs_temp_reading *out, int max);

/// Opens the connection to the AppleSMC service. Returns 0 on success.
int cs_smc_open(void);

/// Closes the AppleSMC connection.
void cs_smc_close(void);

/// Reads one SMC key (4 characters, for example "F0Ac") as a number.
/// Supported data types: flt, ui8, ui16, ui32, sp78, fpe2.
/// Returns 0 on success.
int cs_smc_read_double(const char *key, double *out);

/// Returns the number of SMC keys, or -1 on failure.
int cs_smc_key_count(void);

/// Writes the key name at `index` to `key` and its data type to `type`
/// (both buffers must hold 5 bytes). Returns 0 on success.
int cs_smc_key_at(int index, char *key, char *type);

#endif
