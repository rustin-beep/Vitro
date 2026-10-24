#ifndef CRYPTO_H
#define CRYPTO_H

#include <stddef.h>

#define CRYPTO_HEX_LEN 16

unsigned int crypto_crc32(const unsigned char *data, size_t length);
unsigned long crypto_djb2(const unsigned char *data, size_t length);
unsigned long crypto_fnv1a(const unsigned char *data, size_t length);
unsigned int crypto_adler32(const unsigned char *data, size_t length);
void crypto_to_hex(unsigned long value, char *out, size_t cap);
unsigned int crypto_flip_bit(const unsigned int value, int bit);

#endif /* CRYPTO_H */
