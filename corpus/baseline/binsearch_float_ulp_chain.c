// @category: baseline
// #152: 二分迭代浮点全链(mid/f(x)/b-a)——双臂与 clang -O0 逐位一致
//(立案时 b-a 列 1 ULP 差,2026-10-26 重测仍活;2026-11-13 复测已绿,疑 B4 #427
// printf 高精度段 bigint 化或 B10 #434 strtod 族修复;入库锁行为防回归)
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

/* 
 * ISO C23 Teaching Subset Compliance:
 * - No VLAs, no restrict, no _Static_assert, no complex numbers.
 * - Only allowed library functions used.
 * - No pointer printing (%p).
 */

// --- Part 1: Binary Search and Lower Bound ---

/**
 * Standard binary search on a sorted array.
 * Returns the index of the target if found, otherwise -1.
 */
int binary_search(const int *arr, int size, int target) {
    int left = 0;
    int right = size - 1;

    while (left <= right) {
        int mid = left + (right - left) / 2; // Avoid overflow

        if (arr[mid] == target) {
            return mid;
        } else if (arr[mid] < target) {
            left = mid + 1;
        } else {
            right = mid - 1;
        }
    }

    return -1;
}

/**
 * Lower bound binary search.
 * Returns the index of the first element >= target.
 * If all elements are smaller than target, returns size.
 * If all elements are larger than target, returns 0.
 */
int lower_bound(const int *arr, int size, int target) {
    int left = 0;
    int right = size; // Note: range is [left, right)

    while (left < right) {
        int mid = left + (right - left) / 2;

        if (arr[mid] < target) {
            left = mid + 1;
        } else {
            right = mid;
        }
    }

    return left;
}

// --- Part 2: Bisection Method for sqrt(2) ---

/**
 * Solves f(x) = x*x - 2 = 0 using the bisection method.
 * Interval [a, b] must contain the root (f(a)*f(b) < 0).
 */
void bisection_method(void) {
    double a = 1.0;
    double b = 2.0;
    double tolerance = 1e-12;
    int max_iterations = 50;
    int iter = 0;

    printf("=== Bisection Method for x^2 - 2 = 0 ===\n");
    printf("Initial interval: [%.10f, %.10f]\n", a, b);
    printf("Tolerance: %.2e\n", tolerance);
    printf("Max Iterations: %d\n\n", max_iterations);
    
    printf("%-5s %-20s %-20s %-20s\n", "Iter", "Midpoint", "f(Midpoint)", "Interval Width");
    printf("------------------------------------------------------------\n");

    while (iter < max_iterations) {
        double mid = (a + b) / 2.0;
        double f_mid = mid * mid - 2.0;
        double f_a = a * a - 2.0;
        
        // Check for convergence
        if (fabs(f_mid) < tolerance || (b - a) / 2.0 < tolerance) {
            printf("%-5d %-20.15f %-20.15e %-20.15e\n", iter, mid, f_mid, b - a);
            printf("\nConverged at iteration %d.\n", iter);
            break;
        }

        printf("%-5d %-20.15f %-20.15e %-20.15e\n", iter, mid, f_mid, b - a);

        // Determine which half contains the root
        if (f_a * f_mid < 0) {
            b = mid;
        } else {
            a = mid;
        }
        
        iter++;
    }

    double result = (a + b) / 2.0;
    printf("\nApproximate root: %.15f\n", result);
    printf("Actual sqrt(2):   %.15f\n", 1.414213562373095);
    printf("Difference:       %.15e\n\n", fabs(result - 1.414213562373095));
}

// --- Part 3: Newton-Raphson Method for sqrt(2) ---

/**
 * Solves f(x) = x*x - 2 = 0 using Newton's method.
 * f'(x) = 2*x
 * x_new = x - f(x)/f'(x) = x - (x^2 - 2)/(2x) = (x + 2/x)/2
 */
void newton_raphson_method(void) {
    double x = 1.0; // Initial guess
    int iterations = 10;

    printf("=== Newton-Raphson Method for x^2 - 2 = 0 ===\n");
    printf("Initial guess: %.15f\n\n", x);
    
    printf("%-5s %-20s %-20s\n", "Iter", "x", "f(x)");
    printf("--------------------------------------------\n");

    for (int i = 0; i < iterations; i++) {
        double f_x = x * x - 2.0;
        double df_x = 2.0 * x;

        printf("%-5d %-20.15f %-20.15e\n", i, x, f_x);

        // Avoid division by zero, though unlikely with x=1.0 for this function
        if (fabs(df_x) < 1e-15) {
            printf("Derivative near zero. Stopping.\n");
            break;
        }

        x = x - f_x / df_x;
    }
    
    // Print the final state after the last update
    double f_final = x * x - 2.0;
    printf("%-5d %-20.15f %-20.15e\n", iterations, x, f_final);

    printf("\nApproximate root: %.15f\n", x);
    printf("Actual sqrt(2):   %.15f\n", 1.414213562373095);
    printf("Difference:       %.15e\n\n", fabs(x - 1.414213562373095));
}

// --- Main Function ---

int main(void) {
    // Part 1: Demonstrate Binary Search and Lower Bound
    printf("=== Part 1: Binary Search & Lower Bound ===\n");
    
    int arr[] = {1, 3, 5, 7, 9, 11, 13, 15};
    int size = sizeof(arr) / sizeof(arr[0]);

    printf("Array: ");
    for (int i = 0; i < size; i++) {
        printf("%d ", arr[i]);
    }
    printf("\n\n");

    // Test binary_search
    int target1 = 7;
    int idx1 = binary_search(arr, size, target1);
    printf("Binary Search for %d: Index %d\n", target1, idx1);

    int target2 = 6;
    int idx2 = binary_search(arr, size, target2);
    printf("Binary Search for %d: Index %d (Not Found)\n", target2, idx2);

    // Test lower_bound
    int lb1 = lower_bound(arr, size, 7);
    printf("Lower Bound for %d: Index %d (Value: %d)\n", 7, lb1, arr[lb1]);

    int lb2 = lower_bound(arr, size, 6);
    printf("Lower Bound for %d: Index %d (Value: %d)\n", 6, lb2, arr[lb2]);

    int lb3 = lower_bound(arr, size, 20);
    if (lb3 < size) {
        printf("Lower Bound for %d: Index %d (Value: %d)\n", 20, lb3, arr[lb3]);
    } else {
        printf("Lower Bound for %d: Index %d (Out of bounds, all elements smaller)\n", 20, lb3);
    }

    int lb4 = lower_bound(arr, size, 0);
    printf("Lower Bound for %d: Index %d (Value: %d)\n", 0, lb4, arr[lb4]);

    printf("\n");

    // Part 2: Bisection Method
    bisection_method();

    // Part 3: Newton-Raphson Method
    newton_raphson_method();

    return 0;
}
