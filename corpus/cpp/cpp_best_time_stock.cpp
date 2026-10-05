#include <stdio.h>
int maxProfit(int* prices, int pricesSize) {
    int minp = prices[0], profit = 0;
    for (int i = 1; i < pricesSize; i++) {
        if (prices[i] - minp > profit) profit = prices[i] - minp;
        if (prices[i] < minp) minp = prices[i];
    }
    return profit;
}
int main() {
    int p[] = {7, 1, 5, 3, 6, 4};
    printf("%d\n", maxProfit(p, 6));
    return 0;
}
