#include <stdio.h>
#include <string.h>
#include "strutil.h"

static void show_trim(const char *label, const char *input)
{
    char buf[256];
    int rc;

    str_copy_bounded(buf, sizeof buf, input);
    rc = str_trim(buf);
    printf("%-18s rc=%3d len=%3d value=[%s]\n", label, rc, rc < 0 ? 0 : rc, buf);
}

int main(void)
{
    char buf[512];
    int rc;

    printf("=== trim ===\n");
    show_trim("plain", "hello world");
    show_trim("leading/trailing", "   padded   ");
    show_trim("all spaces", "     ");
    show_trim("empty", "");

    printf("=== split_count ===\n");
    printf("%-18s rc=%3d (a,b,c)\n", "split_count", str_split_count("a,b,c", ','));
    printf("%-18s rc=%3d (a,,b)\n", "split_count empty", str_split_count("a,,b", ','));
    printf("%-18s rc=%3d (empty)\n", "split_count empty str", str_split_count("", ','));

    printf("=== replace_all ===\n");
    str_copy_bounded(buf, sizeof buf, "the cat sat on the mat");
    rc = str_replace_all(buf, "at", "og");
    printf("%-18s rc=%3d value=[%s]\n", "replace_all", rc, buf);

    str_copy_bounded(buf, sizeof buf, "abc");
    rc = str_replace_all(buf, "xyz", "q");
    printf("%-18s rc=%3d value=[%s]\n", "replace no match", rc, buf);

    str_copy_bounded(buf, sizeof buf, "aaaa");
    rc = str_replace_all(buf, "a", "bb");
    printf("%-18s rc=%3d value=[%s]\n", "replace grow", rc, buf);

    printf("=== prefix / suffix ===\n");
    printf("%-18s rc=%3d\n", "starts_with yes", str_starts_with("vitro/engine", "vitro"));
    printf("%-18s rc=%3d\n", "starts_with no", str_starts_with("vitro/engine", "engine"));
    printf("%-18s rc=%3d\n", "ends_with yes", str_ends_with("vec.h", ".h"));
    printf("%-18s rc=%3d\n", "ends_with no", str_ends_with("vec.h", ".c"));

    printf("=== reverse / case ===\n");
    str_copy_bounded(buf, sizeof buf, "abcdef");
    str_reverse(buf);
    printf("%-18s value=[%s]\n", "reverse", buf);

    str_copy_bounded(buf, sizeof buf, "Mixed Case 42");
    rc = str_to_upper(buf);
    printf("%-18s rc=%3d value=[%s]\n", "to_upper", rc, buf);

    str_copy_bounded(buf, sizeof buf, "Mixed Case 42");
    rc = str_to_lower(buf);
    printf("%-18s rc=%3d value=[%s]\n", "to_lower", rc, buf);

    printf("=== count / index ===\n");
    printf("%-18s rc=%3d\n", "count_char l", str_count_char("hello world", 'l'));
    printf("%-18s rc=%3d\n", "count_char z", str_count_char("hello world", 'z'));
    printf("%-18s rc=%3d\n", "index_of o", str_index_of("hello world", 'o'));
    printf("%-18s rc=%3d\n", "index_of missing", str_index_of("hello world", 'z'));

    printf("=== bounded copy ===\n");
    {
        char small[4];
        rc = str_copy_bounded(small, sizeof small, "0123456789");
        printf("%-18s rc=%3d value=[%s]\n", "copy truncated", rc, small);
        rc = str_copy_bounded(small, sizeof small, "abc");
        printf("%-18s rc=%3d value=[%s]\n", "copy fits", rc, small);
    }

    printf("=== summary ===\n");
    printf("functions_checked = 12\n");
    printf("error_codes: null=%d not_found=%d toobig=%d empty=%d\n",
           STR_ERR_NULL, STR_ERR_NOT_FOUND, STR_ERR_TOOBIG, STR_ERR_EMPTY);
    return 0;
}
