#include <stdio.h>
#include <string.h>
#include "bitset.h"

static void show(const char *label, const BitSet *set)
{
    char binary[BITSET_BITS + 1];
    char hex[BITSET_HEX_LEN + 1];

    bitset_to_binary_string(set, binary, sizeof binary);
    bitset_to_hex_string(set, hex, sizeof hex);
    printf("  %-18s hex=%s\n", label, hex);
    printf("  %-18s bin=%s\n", label, binary);
    printf("  %-18s popcount=%d low64=%llu\n", label, bitset_count(set), bitset_to_u64(set));
}

int main(void)
{
    BitSet a;
    BitSet b;
    BitSet tmp;
    char binary[BITSET_BITS + 1];
    int i;
    int dropped;
    int wordwise;
    int bitwise;

    bitset_init(&a);
    bitset_init(&b);

    printf("=== set and test ===\n");
    for (i = 0; i < 16; i++) {
        bitset_set(&a, i * 3);
    }
    show("A after set", &a);
    printf("  test(0)=%d test(3)=%d test(127)=%d test(200)=%d\n",
           bitset_test(&a, 0), bitset_test(&a, 3), bitset_test(&a, 127), bitset_test(&a, 200));

    printf("=== clear and flip ===\n");
    bitset_clear(&a, 0);
    bitset_flip(&a, 100);
    show("A after clear+flip", &a);

    printf("=== second set ===\n");
    for (i = 0; i < 8; i++) {
        bitset_set(&b, i * 7 + 1);
    }
    show("B", &b);

    printf("=== logic operations ===\n");
    bitset_and(&tmp, &a, &b);
    show("A and B", &tmp);
    bitset_or(&tmp, &a, &b);
    show("A or B", &tmp);
    bitset_xor(&tmp, &a, &b);
    show("A xor B", &tmp);
    bitset_not(&tmp, &a);
    show("not A", &tmp);

    printf("=== shifts ===\n");
    bitset_init(&tmp);
    for (i = 0; i < 4; i++) {
        bitset_set(&tmp, i * 10);
    }
    show("shift source", &tmp);
    dropped = bitset_shift_left(&tmp, 5);
    printf("  shift_left(5) dropped=%d\n", dropped);
    show("after shift left", &tmp);
    dropped = bitset_shift_right(&tmp, 2);
    printf("  shift_right(2) dropped=%d\n", dropped);
    show("after shift right", &tmp);
    dropped = bitset_shift_left(&tmp, 200);
    printf("  shift_left(200) dropped=%d (beyond capacity)\n", dropped);
    show("after huge shift", &tmp);
    dropped = bitset_shift_right(&tmp, 200);
    printf("  shift_right(200) dropped=%d (beyond capacity)\n", dropped);
    show("after huge shift", &tmp);

    printf("=== popcount cross check ===\n");
    wordwise = bitset_count(&b);
    bitwise = bitset_count_bitwise(&b);
    printf("  word_wise=%d bit_wise=%d same=%s\n",
           wordwise, bitwise, (wordwise == bitwise) ? "yes" : "no");

    printf("=== jaccard similarity ===\n");
    printf("  jaccard(A,B)=%.4f\n", bitset_jaccard(&a, &b));
    bitset_init(&tmp);
    printf("  jaccard(A,empty)=%.4f\n", bitset_jaccard(&a, &tmp));
    printf("  jaccard(A,A)=%.4f\n", bitset_jaccard(&a, &a));

    bitset_to_binary_string(&a, binary, sizeof binary);
    printf("  bitset_ops=%d\n", bitset_ops);
    printf("=== final ===\n");
    printf("  A length=%d first_bits=%.16s\n", (int)strlen(binary), binary);
    return 0;
}
