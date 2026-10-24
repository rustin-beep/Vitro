#include "matrix.h"

int matrix_ops = 0;
#include <stdio.h>
#include <string.h>
#include <math.h>

void matrix_zero(Matrix *matrix)
{
    int r;
    int c;

    if (matrix == NULL) {
        return;
    }
    for (r = 0; r < MATRIX_MAX; r++) {
        for (c = 0; c < MATRIX_MAX; c++) {
            matrix->data[r][c] = 0.0;
        }
    }
    matrix->rows = 0;
    matrix->cols = 0;
}

void matrix_identity(Matrix *matrix, int size)
{
    int r;
    int c;

    if (matrix == NULL || size <= 0 || size > MATRIX_MAX) {
        return;
    }
    matrix_zero(matrix);
    matrix->rows = size;
    matrix->cols = size;
    for (r = 0; r < size; r++) {
        for (c = 0; c < size; c++) {
            matrix->data[r][c] = (r == c) ? 1.0 : 0.0;
        }
    }
}

void matrix_set(Matrix *matrix, int rows, int cols, const double *values)
{
    int r;
    int c;

    if (matrix == NULL || values == NULL || rows <= 0 || cols <= 0) {
        return;
    }
    if (rows > MATRIX_MAX || cols > MATRIX_MAX) {
        return;
    }
    matrix_zero(matrix);
    matrix->rows = rows;
    matrix->cols = cols;
    for (r = 0; r < rows; r++) {
        for (c = 0; c < cols; c++) {
            matrix->data[r][c] = values[r * cols + c];
        }
    }
}

int matrix_add(const Matrix *a, const Matrix *b, Matrix *out)
{
    int r;
    int c;

    if (a == NULL || b == NULL || out == NULL) {
        return MATRIX_ERR_SIZE;
    }
    if (a->rows != b->rows || a->cols != b->cols) {
        return MATRIX_ERR_SIZE;
    }
    matrix_zero(out);
    out->rows = a->rows;
    out->cols = a->cols;
    for (r = 0; r < a->rows; r++) {
        for (c = 0; c < a->cols; c++) {
            out->data[r][c] = a->data[r][c] + b->data[r][c];
        }
    }
    return MATRIX_OK;
}

int matrix_sub(const Matrix *a, const Matrix *b, Matrix *out)
{
    int r;
    int c;

    if (a == NULL || b == NULL || out == NULL) {
        return MATRIX_ERR_SIZE;
    }
    if (a->rows != b->rows || a->cols != b->cols) {
        return MATRIX_ERR_SIZE;
    }
    matrix_zero(out);
    out->rows = a->rows;
    out->cols = a->cols;
    for (r = 0; r < a->rows; r++) {
        for (c = 0; c < a->cols; c++) {
            out->data[r][c] = a->data[r][c] - b->data[r][c];
        }
    }
    return MATRIX_OK;
}

int matrix_mul(const Matrix *a, const Matrix *b, Matrix *out)
{
    int r;
    int c;
    int k;

    if (a == NULL || b == NULL || out == NULL) {
        return MATRIX_ERR_SIZE;
    }
    if (a->cols != b->rows) {
        return MATRIX_ERR_SIZE;
    }
    matrix_zero(out);
    out->rows = a->rows;
    out->cols = b->cols;
    for (r = 0; r < a->rows; r++) {
        for (c = 0; c < b->cols; c++) {
            double sum = 0.0;
            for (k = 0; k < a->cols; k++) {
                sum += a->data[r][k] * b->data[k][c];
            }
            out->data[r][c] = sum;
            matrix_ops++;
        }
    }
    return MATRIX_OK;
}

int matrix_transpose(const Matrix *a, Matrix *out)
{
    int r;
    int c;

    if (a == NULL || out == NULL) {
        return MATRIX_ERR_SIZE;
    }
    matrix_zero(out);
    out->rows = a->cols;
    out->cols = a->rows;
    for (r = 0; r < a->rows; r++) {
        for (c = 0; c < a->cols; c++) {
            out->data[c][r] = a->data[r][c];
        }
    }
    return MATRIX_OK;
}

double matrix_determinant(const Matrix *a)
{
    double work[MATRIX_MAX][MATRIX_MAX];
    double determinant = 1.0;
    int n;
    int r;
    int c;
    int k;

    if (a == NULL || a->rows != a->cols) {
        return 0.0;
    }
    n = a->rows;
    for (r = 0; r < n; r++) {
        for (c = 0; c < n; c++) {
            work[r][c] = a->data[r][c];
        }
    }
    for (k = 0; k < n; k++) {
        int pivot = k;
        double best = fabs(work[k][k]);
        for (r = k + 1; r < n; r++) {
            if (fabs(work[r][k]) > best) {
                best = fabs(work[r][k]);
                pivot = r;
            }
        }
        if (best < 1e-12) {
            return 0.0;
        }
        if (pivot != k) {
            for (c = 0; c < n; c++) {
                double tmp = work[k][c];
                work[k][c] = work[pivot][c];
                work[pivot][c] = tmp;
            }
            determinant = -determinant;
        }
        determinant *= work[k][k];
        for (r = k + 1; r < n; r++) {
            double factor = work[r][k] / work[k][k];
            for (c = k; c < n; c++) {
                work[r][c] -= factor * work[k][c];
            }
        }
    }
    return determinant;
}

int matrix_inverse(const Matrix *a, Matrix *out)
{
    double work[MATRIX_MAX][MATRIX_MAX];
    double right[MATRIX_MAX][MATRIX_MAX];
    int n;
    int r;
    int c;
    int k;

    if (a == NULL || out == NULL || a->rows != a->cols) {
        return MATRIX_ERR_SIZE;
    }
    n = a->rows;
    for (r = 0; r < n; r++) {
        for (c = 0; c < n; c++) {
            work[r][c] = a->data[r][c];
            right[r][c] = (r == c) ? 1.0 : 0.0;
        }
    }
    for (k = 0; k < n; k++) {
        int pivot = k;
        double best = fabs(work[k][k]);
        for (r = k + 1; r < n; r++) {
            if (fabs(work[r][k]) > best) {
                best = fabs(work[r][k]);
                pivot = r;
            }
        }
        if (best < 1e-12) {
            return MATRIX_ERR_SINGULAR;
        }
        if (pivot != k) {
            for (c = 0; c < n; c++) {
                double tmp = work[k][c];
                work[k][c] = work[pivot][c];
                work[pivot][c] = tmp;
                tmp = right[k][c];
                right[k][c] = right[pivot][c];
                right[pivot][c] = tmp;
            }
        }
        {
            double divisor = work[k][k];
            for (c = 0; c < n; c++) {
                work[k][c] /= divisor;
                right[k][c] /= divisor;
            }
        }
        for (r = 0; r < n; r++) {
            double factor;
            if (r == k) {
                continue;
            }
            factor = work[r][k];
            for (c = 0; c < n; c++) {
                work[r][c] -= factor * work[k][c];
                right[r][c] -= factor * right[k][c];
            }
        }
    }
    matrix_zero(out);
    out->rows = n;
    out->cols = n;
    for (r = 0; r < n; r++) {
        for (c = 0; c < n; c++) {
            out->data[r][c] = right[r][c];
        }
    }
    return MATRIX_OK;
}

double matrix_trace(const Matrix *a)
{
    double sum = 0.0;
    int i;

    if (a == NULL) {
        return 0.0;
    }
    for (i = 0; i < a->rows && i < a->cols; i++) {
        sum += a->data[i][i];
    }
    return sum;
}

double matrix_max_abs_diff(const Matrix *a, const Matrix *b)
{
    double worst = 0.0;
    int r;
    int c;

    if (a == NULL || b == NULL) {
        return 0.0;
    }
    for (r = 0; r < a->rows; r++) {
        for (c = 0; c < a->cols; c++) {
            double diff = fabs(a->data[r][c] - b->data[r][c]);
            if (diff > worst) {
                worst = diff;
            }
        }
    }
    return worst;
}

void matrix_print(const Matrix *matrix, const char *label)
{
    int r;
    int c;

    if (matrix == NULL) {
        return;
    }
    printf("  %s (%dx%d)\n", (label != NULL) ? label : "matrix", matrix->rows, matrix->cols);
    for (r = 0; r < matrix->rows; r++) {
        printf("   ");
        for (c = 0; c < matrix->cols; c++) {
            printf("%9.4f ", matrix->data[r][c]);
        }
        printf("\n");
    }
}
