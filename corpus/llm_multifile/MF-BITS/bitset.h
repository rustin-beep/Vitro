#ifndef BITSET_H
#define BITSET_H

#include <stddef.h>

#define BITSET_BITS 128
#define BITSET_WORD_BITS 32
#define BITSET_WORDS (BITSET_BITS / BITSET_WORD_BITS)
#define BITSET_HEX_LEN (BITSET_BITS / 4)

typedef struct {
    unsigned int words[BITSET_WORDS];
} BitSet;

void bitset_init(BitSet *set);
void bitset_set(BitSet *set, int index);
void bitset_clear(BitSet *set, int index);
int bitset_test(const BitSet *set, int index);
void bitset_flip(BitSet *set, int index);

/* population count, word wise and bit wise */
int bitset_count(const BitSet *set);
int bitset_count_bitwise(const BitSet *set);

void bitset_and(BitSet *dst, const BitSet *a, const BitSet *b);
void bitset_or(BitSet *dst, const BitSet *a, const BitSet *b);
void bitset_xor(BitSet *dst, const BitSet *a, const BitSet *b);
void bitset_not(BitSet *dst, const BitSet *a);

/* shifts move the bit index up or down; the number of dropped bits is returned */
int bitset_shift_left(BitSet *set, int amount);
int bitset_shift_right(BitSet *set, int amount);

int bitset_to_hex_string(const BitSet *set, char *out, size_t cap);
int bitset_to_binary_string(const BitSet *set, char *out, size_t cap);

/* low 64 bits as a decimal value */
unsigned long long bitset_to_u64(const BitSet *set);

double bitset_jaccard(const BitSet *a, const BitSet *b);

extern int bitset_ops;

#endif /* BITSET_H */
