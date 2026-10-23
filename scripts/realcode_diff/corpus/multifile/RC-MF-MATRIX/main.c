#include <stdio.h>
#include <math.h>
#include "matrix.h"

int main(void)
{
    static const double A_VALUES[9] = {
        4.0, 7.0, 2.0,
        3.0, 6.0, 1.0,
        2.0, 4.0, 3.0
    };
    static const double SINGULAR_VALUES[9] = {
        1.0, 2.0, 3.0,
        2.0, 4.0, 6.0,
        1.0, 1.0, 1.0
    };
    static const double B_VALUES[9] = {
        1.0, 0.0, 2.0,
        0.0, 1.0, 1.0,
        3.0, 2.0, 1.0
    };
    Matrix a;
    Matrix b;
    Matrix identity;
    Matrix result;
    Matrix inverse;
    Matrix product;
    Matrix singular;
    int rc;

    matrix_set(&a, 3, 3, A_VALUES);
    matrix_set(&b, 3, 3, B_VALUES);
    matrix_set(&singular, 3, 3, SINGULAR_VALUES);
    matrix_identity(&identity, 3);

    printf("=== input matrices ===\n");
    matrix_print(&a, "A");
    matrix_print(&b, "B");
    matrix_print(&identity, "I");

    printf("=== addition ===\n");
    rc = matrix_add(&a, &b, &result);
    printf("  rc=%d\n", rc);
    matrix_print(&result, "A + B");

    printf("=== subtraction ===\n");
    rc = matrix_sub(&a, &b, &result);
    printf("  rc=%d\n", rc);
    matrix_print(&result, "A - B");

    printf("=== multiplication ===\n");
    rc = matrix_mul(&a, &b, &result);
    printf("  rc=%d\n", rc);
    matrix_print(&result, "A * B");

    printf("=== manual cross check ===\n");
    {
        double expected[9];
        expected[0] = 4.0 * 1.0 + 7.0 * 0.0 + 2.0 * 3.0;
        expected[1] = 4.0 * 0.0 + 7.0 * 1.0 + 2.0 * 2.0;
        expected[2] = 4.0 * 2.0 + 7.0 * 1.0 + 2.0 * 1.0;
        expected[3] = 3.0 * 1.0 + 6.0 * 0.0 + 1.0 * 3.0;
        expected[4] = 3.0 * 0.0 + 6.0 * 1.0 + 1.0 * 2.0;
        expected[5] = 3.0 * 2.0 + 6.0 * 1.0 + 1.0 * 1.0;
        expected[6] = 2.0 * 1.0 + 4.0 * 0.0 + 3.0 * 3.0;
        expected[7] = 2.0 * 0.0 + 4.0 * 1.0 + 3.0 * 2.0;
        expected[8] = 2.0 * 2.0 + 4.0 * 1.0 + 3.0 * 1.0;
        printf("  manual[0][0]=%.4f computed=%.4f\n", expected[0], result.data[0][0]);
        printf("  manual[2][2]=%.4f computed=%.4f\n", expected[8], result.data[2][2]);
    }

    printf("=== transpose ===\n");
    rc = matrix_transpose(&a, &result);
    printf("  rc=%d\n", rc);
    matrix_print(&result, "A transposed");

    printf("=== determinant and trace ===\n");
    printf("  det(A)=%.6f\n", matrix_determinant(&a));
    printf("  det(I)=%.6f\n", matrix_determinant(&identity));
    printf("  trace(A)=%.6f\n", matrix_trace(&a));
    printf("  trace(I)=%.6f\n", matrix_trace(&identity));

    printf("=== inverse ===\n");
    rc = matrix_inverse(&a, &inverse);
    printf("  rc=%d\n", rc);
    matrix_print(&inverse, "A inverse");

    printf("=== verification A * A^-1 == I ===\n");
    rc = matrix_mul(&a, &inverse, &product);
    printf("  rc=%d\n", rc);
    matrix_print(&product, "A * A inverse");
    printf("  max_abs_error=%.6f\n", matrix_max_abs_diff(&product, &identity));

    printf("=== singular matrix ===\n");
    matrix_print(&singular, "singular");
    printf("  det=%.6f\n", matrix_determinant(&singular));
    rc = matrix_inverse(&singular, &inverse);
    printf("  inverse rc=%d (negative means the matrix is not invertible)\n", rc);

    printf("=== dimension mismatch ===\n");
    {
        Matrix small;
        matrix_identity(&small, 2);
        rc = matrix_add(&a, &small, &result);
        printf("  add with a 2x2 rc=%d\n", rc);
        rc = matrix_mul(&a, &small, &result);
        printf("  multiply with a 2x2 rc=%d\n", rc);
    printf("  matrix_ops=%d\n", matrix_ops);
    }
    return 0;
}
