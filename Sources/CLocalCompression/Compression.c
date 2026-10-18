#include "CLocalCompression.h"
#include <limits.h>
#include <zlib.h>

static int codec(const uint8_t *input, size_t count, uint8_t *output,
                 size_t *capacity, int compress) {
    if (count > UINT_MAX || *capacity > UINT_MAX) return -1;
    z_stream stream = {0};
    int status = compress
        ? deflateInit2(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, 31, 8, Z_DEFAULT_STRATEGY)
        : inflateInit2(&stream, 31);
    if (status != Z_OK) return -1;
    stream.next_in = (Bytef *)input;
    stream.avail_in = (uInt)count;
    stream.next_out = output;
    stream.avail_out = (uInt)*capacity;
    status = compress ? deflate(&stream, Z_FINISH) : inflate(&stream, Z_FINISH);
    int valid = status == Z_STREAM_END && stream.avail_in == 0;
    *capacity = stream.total_out;
    if (compress) deflateEnd(&stream); else inflateEnd(&stream);
    return valid ? 0 : -1;
}

int lf_gzip(const uint8_t *input, size_t count, uint8_t *output, size_t *capacity) {
    return codec(input, count, output, capacity, 1);
}
int lf_gunzip(const uint8_t *input, size_t count, uint8_t *output, size_t *capacity) {
    return codec(input, count, output, capacity, 0);
}
