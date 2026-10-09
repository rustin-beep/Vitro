#define _USE_MATH_DEFINES   // 必须在 include <math.h> 之前定义，MSVC 才能用 M_PI
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <time.h>

// ============================================================
// 算法参数
// ============================================================
#define DIM 2                // 搜索维度
#define POP_SIZE 30          // 种群大小（草莓植株数量）
#define MAX_GEN 100          // 最大迭代次数
#define MAX_RUNNERS 10       // 每株最多产生的匍匐茎数量
#define LOWER_BOUND -10.0    // 搜索下界
#define UPPER_BOUND 10.0     // 搜索上界

// ============================================================
// 数据结构
// ============================================================
typedef struct {
    double position[DIM];    // 位置（解向量）
    double fitness;          // 适应度（目标函数值，求最小值）
} Plant;

// ============================================================
// 辅助函数
// ============================================================
double rand_double() {
    return (double)rand() / RAND_MAX;
}

double rand_range(double min, double max) {
    return min + (max - min) * rand_double();
}

// ============================================================
// 目标函数：Rastrigin 函数，全局最小值在 (0,0) 处为 0
// ============================================================
double objective_function(double x[]) {
    double sum = 0.0;
    for (int i = 0; i < DIM; i++) {
        sum += x[i] * x[i] - 10.0 * cos(2.0 * M_PI * x[i]);
    }
    return 10.0 * DIM + sum;
}

// ============================================================
// 初始化种群
// ============================================================
void initialize_population(Plant pop[]) {
    for (int i = 0; i < POP_SIZE; i++) {
        for (int j = 0; j < DIM; j++) {
            pop[i].position[j] = rand_range(LOWER_BOUND, UPPER_BOUND);
        }
        pop[i].fitness = objective_function(pop[i].position);
    }
}

// ============================================================
// 评估整个种群
// ============================================================
void evaluate_population(Plant pop[]) {
    for (int i = 0; i < POP_SIZE; i++) {
        pop[i].fitness = objective_function(pop[i].position);
    }
}

// ============================================================
// 找当前最优个体索引
// ============================================================
int find_best_index(Plant pop[]) {
    int best_idx = 0;
    for (int i = 1; i < POP_SIZE; i++) {
        if (pop[i].fitness < pop[best_idx].fitness) {
            best_idx = i;
        }
    }
    return best_idx;
}

// ============================================================
// 核心：植物传播（产生子代）
// ============================================================
void propagate(Plant pop[], Plant new_pop[]) {
    // 先复制一份当前种群
    for (int i = 0; i < POP_SIZE; i++) {
        new_pop[i] = pop[i];
    }

    // 计算当前种群适应度的最大值和最小值
    double max_fit = -1e30, min_fit = 1e30;
    for (int k = 0; k < POP_SIZE; k++) {
        if (pop[k].fitness > max_fit) max_fit = pop[k].fitness;
        if (pop[k].fitness < min_fit) min_fit = pop[k].fitness;
    }
    double range = max_fit - min_fit;
    if (range < 1e-12) range = 1.0;  // 防止除以零

    for (int i = 0; i < POP_SIZE; i++) {
        // 归一化适应度 N_i：越优的个体 N_i 越大（0~1）
        double N_i = (max_fit - pop[i].fitness) / range;

        // 产生匍匐茎的数量：好植株产生更多子代
        double alpha = rand_double();
        int n_runners = (int)ceil(MAX_RUNNERS * N_i * alpha);
        if (n_runners < 1) n_runners = 1;

        // 为每个匍匐茎生成一个新位置
        for (int r = 0; r < n_runners; r++) {
            double dx[DIM];
            for (int j = 0; j < DIM; j++) {
                // 好植株移动距离小（局部开发），差植株移动距离大（全局探索）
                dx[j] = 2.0 * (1.0 - N_i) * (rand_double() - 0.5);
            }

            Plant child;
            for (int j = 0; j < DIM; j++) {
                child.position[j] = pop[i].position[j] + dx[j];
                // 边界处理
                if (child.position[j] < LOWER_BOUND) child.position[j] = LOWER_BOUND;
                if (child.position[j] > UPPER_BOUND) child.position[j] = UPPER_BOUND;
            }
            child.fitness = objective_function(child.position);

            // 随机替换一个个体，仅当子代更优时才替换
            int replace_idx = rand() % POP_SIZE;
            if (child.fitness < new_pop[replace_idx].fitness) {
                new_pop[replace_idx] = child;
            }
        }
    }
}

// ============================================================
// 主函数
// ============================================================
int main() {
    srand((unsigned int)time(NULL));  // 随机种子

    Plant population[POP_SIZE];
    Plant new_population[POP_SIZE];

    // 初始化
    initialize_population(population);
    int best_idx = find_best_index(population);

    printf("Initial best fitness: %f\n", population[best_idx].fitness);

    // 迭代
    for (int gen = 0; gen < MAX_GEN; gen++) {
        propagate(population, new_population);

        // 新一代覆盖旧一代
        for (int i = 0; i < POP_SIZE; i++) {
            population[i] = new_population[i];
        }
        evaluate_population(population);
        best_idx = find_best_index(population);

        if ((gen + 1) % 10 == 0) {
            printf("Generation %d: best fitness = %f\n", gen + 1, population[best_idx].fitness);
        }
    }

    // 输出最终结果
    printf("\n===== Final Result =====\n");
    printf("Best fitness: %f\n", population[best_idx].fitness);
    printf("Best position: (");
    for (int j = 0; j < DIM; j++) {
        printf("%.6f", population[best_idx].position[j]);
        if (j < DIM - 1) printf(", ");
    }
    printf(")\n");

    return 0;
}
