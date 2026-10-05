#include <stdio.h>

int maximalSquare(char* matrix, int rows, int cols) {
    int dp[100];
    int max_side = 0;
    int prev_diag = 0;

    for (int c = 0; c < cols; c++) {
        dp[c] = matrix[c] - '0';
        if (dp[c] > max_side) {
            max_side = dp[c];
        }
    }

    for (int r = 1; r < rows; r++) {
        prev_diag = dp[0];
        dp[0] = matrix[r * cols] - '0';
        if (dp[0] > max_side) {
            max_side = dp[0];
        }
        for (int c = 1; c < cols; c++) {
            int temp = dp[c];
            if (matrix[r * cols + c] == '1') {
                int min = dp[c];
                if (dp[c - 1] < min) {
                    min = dp[c - 1];
                }
                if (prev_diag < min) {
                    min = prev_diag;
                }
                dp[c] = min + 1;
                if (dp[c] > max_side) {
                    max_side = dp[c];
                }
            } else {
                dp[c] = 0;
            }
            prev_diag = temp;
        }
    }

    return max_side * max_side;
}

int main() {
    char m1[20] = {
        '1', '0', '1', '0', '0',
        '1', '0', '1', '1', '1',
        '1', '1', '1', '1', '1',
        '1', '0', '0', '1', '0'
    };
    printf("%d\n", maximalSquare(m1, 4, 5));

    char m2[1] = {'0'};
    printf("%d\n", maximalSquare(m2, 1, 1));

    char m3[1] = {'1'};
    printf("%d\n", maximalSquare(m3, 1, 1));

    char m4[8] = {
        '1', '1',
        '1', '1',
        '0', '0',
        '1', '1'
    };
    printf("%d\n", maximalSquare(m4, 4, 2));

    return 0;
}
