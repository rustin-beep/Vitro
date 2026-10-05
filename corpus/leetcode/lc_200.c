#include <stdio.h>
#include <string.h>

void dfs(char* grid, int rows, int cols, int r, int c) {
    if (r < 0 || r >= rows || c < 0 || c >= cols) {
        return;
    }
    if (grid[r * cols + c] != '1') {
        return;
    }
    grid[r * cols + c] = '0';
    dfs(grid, rows, cols, r - 1, c);
    dfs(grid, rows, cols, r + 1, c);
    dfs(grid, rows, cols, r, c - 1);
    dfs(grid, rows, cols, r, c + 1);
}

int numIslands(char* grid, int rows, int cols) {
    int count = 0;
    for (int r = 0; r < rows; r++) {
        for (int c = 0; c < cols; c++) {
            if (grid[r * cols + c] == '1') {
                count++;
                dfs(grid, rows, cols, r, c);
            }
        }
    }
    return count;
}

int main() {
    char g1[20] = {
        '1', '1', '1', '1', '0',
        '1', '1', '0', '1', '0',
        '1', '1', '0', '0', '0',
        '0', '0', '0', '0', '0'
    };
    printf("%d\n", numIslands(g1, 4, 5));

    char g2[30] = {
        '1', '1', '0', '0', '0',
        '1', '1', '0', '0', '0',
        '0', '0', '1', '0', '0',
        '0', '0', '0', '1', '1'
    };
    printf("%d\n", numIslands(g2, 4, 5));

    char g3[1] = {'0'};
    printf("%d\n", numIslands(g3, 1, 1));

    return 0;
}
