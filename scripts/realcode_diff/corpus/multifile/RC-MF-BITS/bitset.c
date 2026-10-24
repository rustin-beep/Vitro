#include "bitset.h"

int bitset_ops = 0;

void bitset_init(BitSet *set)
{
    int i;

    if (set == NULL) {
        return;
    }
    for (i = 0; i < BITSET_WORDS; i++) {
        set->words[i] = 0u;
    }
}

void bitset_set(BitSet *set, int index)
{
    if (set == NULL || index < 0 || index >= BITSET_BITS) {
        return;
    }
    set->words[index / BITSET_WORD_BITS] |= 1u << (index % BITSET_WORD_BITS);
    bitset_ops++;
}

void bitset_clear(BitSet *set, int index)
{
    if (set == NULL || index < 0 || index >= BITSET_BITS) {
        return;
    }
    set->words[index / BITSET_WORD_BITS] &= ~(1u << (index % BITSET_WORD_BITS));
}

int bitset_test(const BitSet *set, int index)
{
    if (set == NULL || index < 0 || index >= BITSET_BITS) {
        return 0;
    }
    return ((set->words[index / BITSET_WORD_BITS] >> (index % BITSET_WORD_BITS)) & 1u) != 0u ? 1 : 0;
}

void bitset_flip(BitSet *set, int index)
{
    if (set == NULL || index < 0 || index >= BITSET_BITS) {
        return;
    }
    set->words[index / BITSET_WORD_BITS] ^= 1u << (index % BITSET_WORD_BITS);
}

int bitset_count(const BitSet *set)
{
    int total = 0;
    int w;

    if (set == NULL) {
        return 0;
    }
    for (w = 0; w < BITSET_WORDS; w++) {
        unsigned int value = set->words[w];
        while (value != 0u) {
            total += (int)(value & 1u);
            value >>= 1;
        }
    }
    return total;
}

int bitset_count_bitwise(const BitSet *set)
{
    int total = 0;
    int i;

    if (set == NULL) {
        return 0;
    }
    for (i = 0; i < BITSET_BITS; i++) {
        if (bitset_test(set, i) != 0) {
            total++;
        }
    }
    return total;
}

void bitset_and(BitSet *dst, const BitSet *a, const BitSet *b)
{
    int w;

    if (dst == NULL || a == NULL || b == NULL) {
        return;
    }
    for (w = 0; w < BITSET_WORDS; w++) {
        dst->words[w] = a->words[w] & b->words[w];
    }
}

void bitset_or(BitSet *dst, const BitSet *a, const BitSet *b)
{
    int w;

    if (dst == NULL || a == NULL || b == NULL) {
        return;
    }
    for (w = 0; w < BITSET_WORDS; w++) {
        dst->words[w] = a->words[w] | b->words[w];
    }
}

void bitset_xor(BitSet *dst, const BitSet *a, const BitSet *b)
{
    int w;

    if (dst == NULL || a == NULL || b == NULL) {
        return;
    }
    for (w = 0; w < BITSET_WORDS; w++) {
        dst->words[w] = a->words[w] ^ b->words[w];
    }
}

void bitset_not(BitSet *dst, const BitSet *a)
{
    int w;

    if (dst == NULL || a == NULL) {
        return;
    }
    for (w = 0; w < BITSET_WORDS; w++) {
        dst->words[w] = ~a->words[w];
    }
}

int bitset_shift_left(BitSet *set, int amount)
{
    unsigned int tmp[BITSET_WORDS];
    int dropped = 0;
    int i;

    if (set == NULL || amount < 0) {
        return 0;
    }
    for (i = 0; i < BITSET_WORDS; i++) {
        tmp[i] = 0u;
    }
    for (i = 0; i < BITSET_BITS; i++) {
        int target;
        if (bitset_test(set, i) == 0) {
            continue;
        }
        target = i + amount;
        if (target >= BITSET_BITS) {
            dropped++;
            continue;
        }
        tmp[target / BITSET_WORD_BITS] |= 1u << (target % BITSET_WORD_BITS);
    }
    for (i = 0; i < BITSET_WORDS; i++) {
        set->words[i] = tmp[i];
    }
    return dropped;
}

int bitset_shift_right(BitSet *set, int amount)
{
    unsigned int tmp[BITSET_WORDS];
    int dropped = 0;
    int i;

    if (set == NULL || amount < 0) {
        return 0;
    }
    for (i = 0; i < BITSET_WORDS; i++) {
        tmp[i] = 0u;
    }
    for (i = 0; i < BITSET_BITS; i++) {
        int target;
        if (bitset_test(set, i) == 0) {
            continue;
        }
        target = i - amount;
        if (target < 0) {
            dropped++;
            continue;
        }
        tmp[target / BITSET_WORD_BITS] |= 1u << (target % BITSET_WORD_BITS);
    }
    for (i = 0; i < BITSET_WORDS; i++) {
        set->words[i] = tmp[i];
    }
    return dropped;
}

int bitset_to_hex_string(const BitSet *set, char *out, size_t cap)
{
    static const char DIGITS[] = "0123456789abcdef";
    int position;

    if (set == NULL || out == NULL || cap < (size_t)BITSET_HEX_LEN + 1) {
        return 0;
    }
    for (position = 0; position < BITSET_HEX_LEN; position++) {
        int nibble = BITSET_HEX_LEN - 1 - position;
        unsigned int word = set->words[nibble / 8];
        int shift = (nibble % 8) * 4;
        out[position] = DIGITS[(word >> shift) & 0xfu];
    }
    out[BITSET_HEX_LEN] = '\0';
    return BITSET_HEX_LEN;
}

int bitset_to_binary_string(const BitSet *set, char *out, size_t cap)
{
    int i;

    if (set == NULL || out == NULL || cap < (size_t)BITSET_BITS + 1) {
        return 0;
    }
    for (i = 0; i < BITSET_BITS; i++) {
        int index = BITSET_BITS - 1 - i;
        out[i] = (bitset_test(set, index) != 0) ? '1' : '0';
    }
    out[BITSET_BITS] = '\0';
    return BITSET_BITS;
}

unsigned long long bitset_to_u64(const BitSet *set)
{
    unsigned long long low;

    if (set == NULL) {
        return 0ULL;
    }
    low = (unsigned long long)set->words[0];
    low |= ((unsigned long long)set->words[1]) << 32;
    return low;
}

double bitset_jaccard(const BitSet *a, const BitSet *b)
{
    BitSet intersection;
    BitSet union_set;
    int both;
    int either;

    if (a == NULL || b == NULL) {
        return 0.0;
    }
    bitset_and(&intersection, a, b);
    bitset_or(&union_set, a, b);
    both = bitset_count(&intersection);
    either = bitset_count(&union_set);
    if (either == 0) {
        return 0.0;
    }
    return (double)both / (double)either;
}
