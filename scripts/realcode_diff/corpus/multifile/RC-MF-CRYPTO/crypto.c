#include "crypto.h"
#include <string.h>

unsigned int crypto_crc32(const unsigned char *data, size_t length)
{
    unsigned int crc = 0xffffffffu;
    size_t i;
    int bit;

    if (data == NULL) {
        return 0;
    }
    for (i = 0; i < length; i++) {
        crc ^= (unsigned int)data[i];
        for (bit = 0; bit < 8; bit++) {
            if ((crc & 1u) != 0u) {
                crc = (crc >> 1) ^ 0xedb88320u;
            } else {
                crc = crc >> 1;
            }
        }
    }
    return crc ^ 0xffffffffu;
}

unsigned long crypto_djb2(const unsigned char *data, size_t length)
{
    unsigned long hash = 5381ul;
    size_t i;

    if (data == NULL) {
        return 5381ul;
    }
    for (i = 0; i < length; i++) {
        hash = hash * 33ul + (unsigned long)data[i];
    }
    return hash;
}

unsigned long crypto_fnv1a(const unsigned char *data, size_t length)
{
    unsigned long hash = 2166136261ul;
    size_t i;

    if (data == NULL) {
        return 2166136261ul;
    }
    for (i = 0; i < length; i++) {
        hash ^= (unsigned long)data[i];
        hash = hash * 16777619ul;
    }
    return hash;
}

unsigned int crypto_adler32(const unsigned char *data, size_t length)
{
    unsigned int a = 1;
    unsigned int b = 0;
    size_t i;

    if (data == NULL) {
        return 1;
    }
    for (i = 0; i < length; i++) {
        a = (a + (unsigned int)data[i]) % 65521u;
        b = (b + a) % 65521u;
    }
    return (b << 16) | a;
}

void crypto_to_hex(unsigned long value, char *out, size_t cap)
{
    static const char DIGITS[] = "0123456789abcdef";
    int i;

    if (out == NULL || cap == 0) {
        return;
    }
    if (cap < CRYPTO_HEX_LEN + 1) {
        out[0] = '\0';
        return;
    }
    for (i = 0; i < CRYPTO_HEX_LEN; i++) {
        int shift = (CRYPTO_HEX_LEN - 1 - i) * 4;
        out[i] = DIGITS[(value >> shift) & 0xfUL];
    }
    out[CRYPTO_HEX_LEN] = '\0';
}

unsigned int crypto_flip_bit(const unsigned int value, int bit)
{
    if (bit < 0 || bit > 31) {
        return value;
    }
    return value ^ (1u << bit);
}
