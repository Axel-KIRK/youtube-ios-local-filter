#include <stddef.h>
#include <stdint.h>

// The caller owns a bounded output buffer. Nonzero means invalid/oversized input.
int lf_gzip(const uint8_t *input, size_t count, uint8_t *output, size_t *capacity);
int lf_gunzip(const uint8_t *input, size_t count, uint8_t *output, size_t *capacity);
