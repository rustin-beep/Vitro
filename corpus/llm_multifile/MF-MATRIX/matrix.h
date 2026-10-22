#ifndef MATRIX_H
#define MATRIX_H

#include <stddef.h>

#define MATRIX_MAX 8

#define MATRIX_OK 0
#define MATRIX_ERR_SIZE (-1)
#define MATRIX_ERR_SINGULAR (-2)

typedef struct {
    int rows;
    int cols;
    double data[MATRIX_MAX][MATRIX_MAX];
} Matrix;

void matrix_zero(Matrix *matrix);
void matrix_identity(Matrix *matrix, int size);
void matrix_set(Matrix *matrix, int rows, int cols, const double *values);

int matrix_add(const Matrix *a, const Matrix *b, Matrix *out);
int matrix_sub(const Matrix *a, const Matrix *b, Matrix *out);
int matrix_mul(const Matrix *a, const Matrix *b, Matrix *out);
int matrix_transpose(const Matrix *a, Matrix *out);

/* determinant with an upper triangularisation, 0 when the matrix is singular */
double matrix_determinant(const Matrix *a);

/* inverse with a Gauss Jordan elimination, MATRIX_ERR_SINGULAR when not invertible */
int matrix_inverse(const Matrix *a, Matrix *out);

double matrix_trace(const Matrix *a);

/* largest absolute difference between two matrices of the same size */
double matrix_max_abs_diff(const Matrix *a, const Matrix *b);

void matrix_print(const Matrix *matrix, const char *label);

extern int matrix_ops;

#endif /* MATRIX_H */
