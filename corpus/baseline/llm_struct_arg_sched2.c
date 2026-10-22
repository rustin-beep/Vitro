// @category: llm_regression
// #162 红锚：struct 按值传参（另一模型的独立写法）
// 来源：LLM 探针批 8 q36_27b/SCHED_s1（307 行，2026-10-21 入库；clang golden 由 clang_direct 现场生成）
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

/* 
 * ISO C23 Teaching Subset Simulation
 * Process Scheduling Simulator
 * 
 * Constraints:
 * - No stdint.h types (use unsigned long long for large integers if needed, though int/long suffice here)
 * - No scanf/fscanf (use fgets + manual parsing if input were needed, but here we use hardcoded data)
 * - No %p for pointers
 * - ASCII only output
 * - Fixed seed LCG if randomness were needed (not needed for deterministic scheduling)
 */

/* --- Type Definitions --- */

typedef struct {
    int pid;
    int arrival_time;
    int burst_time;
    int completion_time;
    int turnaround_time;
    int waiting_time;
    int remaining_time; // For RR simulation
    int start_time;     // For RR simulation tracking
} Process;

typedef enum {
    SCHED_FCFS,
    SCHED_SJF,
    SCHED_RR
} ScheduleType;

/* --- Global Constants --- */

#define NUM_PROCESSES 5
#define TIME_QUANTUM 3

/* --- Helper Functions --- */

/* Swap two processes */
void swap(Process *a, Process *b) {
    Process temp = *a;
    *a = *b;
    *b = temp;
}

/* Print header for a scheduling strategy */
void print_header(const char *name) {
    printf("\n--- %s ---\n", name);
    printf("PID\tArrival\tBurst\tCompletion\tTurnaround\tWaiting\n");
}

/* Print a single process result */
void print_process(Process p) {
    printf("%d\t%d\t%d\t%d\t\t%d\t\t%d\n", 
           p.pid, 
           p.arrival_time, 
           p.burst_time, 
           p.completion_time, 
           p.turnaround_time, 
           p.waiting_time);
}

/* Calculate and print averages */
void print_averages(Process procs[], int n) {
    double total_wt = 0;
    double total_tat = 0;
    
    for (int i = 0; i < n; i++) {
        total_wt += procs[i].waiting_time;
        total_tat += procs[i].turnaround_time;
    }
    
    printf("\nAverage Waiting Time: %.2f\n", total_wt / n);
    printf("Average Turnaround Time: %.2f\n", total_tat / n);
}

/* --- Scheduling Algorithms --- */

/* 1. First Come First Serve (FCFS) */
void fcfs(Process procs[], int n) {
    /* Sort by arrival time to ensure FCFS order based on arrival */
    /* Note: If arrival times are same, stable sort or PID order doesn't strictly matter for basic FCFS, 
       but we'll sort by arrival time. */
    for (int i = 0; i < n - 1; i++) {
        for (int j = 0; j < n - i - 1; j++) {
            if (procs[j].arrival_time > procs[j+1].arrival_time) {
                swap(&procs[j], &procs[j+1]);
            }
        }
    }

    int current_time = 0;
    
    for (int i = 0; i < n; i++) {
        /* If CPU is idle, advance time to arrival of next process */
        if (current_time < procs[i].arrival_time) {
            current_time = procs[i].arrival_time;
        }
        
        /* Execute process */
        procs[i].completion_time = current_time + procs[i].burst_time;
        current_time = procs[i].completion_time;
        
        /* Calculate Turnaround Time = Completion - Arrival */
        procs[i].turnaround_time = procs[i].completion_time - procs[i].arrival_time;
        
        /* Calculate Waiting Time = Turnaround - Burst */
        procs[i].waiting_time = procs[i].turnaround_time - procs[i].burst_time;
    }
}

/* 2. Shortest Job First (SJF) - Non-Preemptive */
void sjf(Process procs[], int n) {
    /* We need to simulate time step by step or event by event */
    int completed_count = 0;
    int current_time = 0;
    int visited[NUM_PROCESSES];
    
    /* Initialize visited array */
    for (int i = 0; i < n; i++) {
        visited[i] = 0;
        procs[i].remaining_time = procs[i].burst_time;
    }

    while (completed_count < n) {
        /* Find the process with minimum burst time among arrived and unvisited processes */
        int min_index = -1;
        int min_burst = 2147483647; /* INT_MAX equivalent */

        for (int i = 0; i < n; i++) {
            if (visited[i] == 0 && procs[i].arrival_time <= current_time) {
                if (procs[i].burst_time < min_burst) {
                    min_burst = procs[i].burst_time;
                    min_index = i;
                } else if (procs[i].burst_time == min_burst) {
                    /* Tie-breaker: smaller PID first */
                    if (procs[i].pid < procs[min_index].pid) {
                        min_index = i;
                    }
                }
            }
        }

        /* If no process is available, increment time (idle CPU) */
        if (min_index == -1) {
            current_time++;
            continue;
        }

        /* Execute the selected process */
        visited[min_index] = 1;
        completed_count++;
        
        int start_time = current_time;
        current_time += procs[min_index].burst_time;
        
        procs[min_index].completion_time = current_time;
        procs[min_index].turnaround_time = current_time - procs[min_index].arrival_time;
        procs[min_index].waiting_time = procs[min_index].turnaround_time - procs[min_index].burst_time;
    }
}

/* 3. Round Robin (RR) */
void round_robin(Process procs[], int n) {
    int current_time = 0;
    int completed_count = 0;
    int remaining_time[NUM_PROCESSES];
    int visited[NUM_PROCESSES];
    
    /* Initialize */
    for (int i = 0; i < n; i++) {
        remaining_time[i] = procs[i].burst_time;
        visited[i] = 0;
        procs[i].remaining_time = procs[i].burst_time;
    }

    while (completed_count < n) {
        int found_ready = 0;
        
        for (int i = 0; i < n; i++) {
            /* Check if process has arrived and still has work to do */
            if (procs[i].arrival_time <= current_time && remaining_time[i] > 0) {
                found_ready = 1;
                
                /* Determine execution time: min of remaining burst or time quantum */
                int exec_time = remaining_time[i];
                if (exec_time > TIME_QUANTUM) {
                    exec_time = TIME_QUANTUM;
                }

                /* Execute */
                remaining_time[i] -= exec_time;
                current_time += exec_time;

                /* If process is completed */
                if (remaining_time[i] == 0) {
                    completed_count++;
                    procs[i].completion_time = current_time;
                    procs[i].turnaround_time = current_time - procs[i].arrival_time;
                    procs[i].waiting_time = procs[i].turnaround_time - procs[i].burst_time;
                    visited[i] = 1;
                }
            }
        }
        
        /* Safety break if no processes are ready but some are not completed (should not happen in valid input) */
        if (!found_ready) {
             /* Advance time to next arrival if any remain */
             int next_arrival = 2147483647;
             for(int i=0; i<n; i++) {
                 if(!visited[i] && procs[i].arrival_time < next_arrival) {
                     next_arrival = procs[i].arrival_time;
                 }
             }
             if(next_arrival != 2147483647) {
                 current_time = next_arrival;
             }
        }
    }
}

/* --- Main Function --- */

int main(void) {
    /* Define 5 processes: PID, Arrival Time, Burst Time */
    Process original_procs[NUM_PROCESSES] = {
        {1, 0, 5},
        {2, 1, 3},
        {3, 2, 8},
        {4, 3, 6},
        {5, 4, 4}
    };

    /* Arrays to hold copies for each simulation */
    Process fcfs_procs[NUM_PROCESSES];
    Process sjf_procs[NUM_PROCESSES];
    Process rr_procs[NUM_PROCESSES];

    /* Copy data to avoid modifying originals */
    memcpy(fcfs_procs, original_procs, sizeof(original_procs));
    memcpy(sjf_procs, original_procs, sizeof(original_procs));
    memcpy(rr_procs, original_procs, sizeof(original_procs));

    /* 1. FCFS */
    print_header("First Come First Serve (FCFS)");
    fcfs(fcfs_procs, NUM_PROCESSES);
    for (int i = 0; i < NUM_PROCESSES; i++) {
        print_process(fcfs_procs[i]);
    }
    double avg_wt_fcfs = 0;
    double avg_tat_fcfs = 0;
    for (int i = 0; i < NUM_PROCESSES; i++) {
        avg_wt_fcfs += fcfs_procs[i].waiting_time;
        avg_tat_fcfs += fcfs_procs[i].turnaround_time;
    }
    avg_wt_fcfs /= NUM_PROCESSES;
    avg_tat_fcfs /= NUM_PROCESSES;
    printf("\nAverage Waiting Time: %.2f\n", avg_wt_fcfs);
    printf("Average Turnaround Time: %.2f\n", avg_tat_fcfs);

    /* 2. SJF */
    print_header("Shortest Job First (SJF) Non-Preemptive");
    sjf(sjf_procs, NUM_PROCESSES);
    for (int i = 0; i < NUM_PROCESSES; i++) {
        print_process(sjf_procs[i]);
    }
    double avg_wt_sjf = 0;
    double avg_tat_sjf = 0;
    for (int i = 0; i < NUM_PROCESSES; i++) {
        avg_wt_sjf += sjf_procs[i].waiting_time;
        avg_tat_sjf += sjf_procs[i].turnaround_time;
    }
    avg_wt_sjf /= NUM_PROCESSES;
    avg_tat_sjf /= NUM_PROCESSES;
    printf("\nAverage Waiting Time: %.2f\n", avg_wt_sjf);
    printf("Average Turnaround Time: %.2f\n", avg_tat_sjf);

    /* 3. Round Robin */
    print_header("Round Robin (Time Quantum = 3)");
    round_robin(rr_procs, NUM_PROCESSES);
    for (int i = 0; i < NUM_PROCESSES; i++) {
        print_process(rr_procs[i]);
    }
    double avg_wt_rr = 0;
    double avg_tat_rr = 0;
    for (int i = 0; i < NUM_PROCESSES; i++) {
        avg_wt_rr += rr_procs[i].waiting_time;
        avg_tat_rr += rr_procs[i].turnaround_time;
    }
    avg_wt_rr /= NUM_PROCESSES;
    avg_tat_rr /= NUM_PROCESSES;
    printf("\nAverage Waiting Time: %.2f\n", avg_wt_rr);
    printf("Average Turnaround Time: %.2f\n", avg_tat_rr);

    /* Comparison */
    printf("\n--- Comparison of Average Waiting Times ---\n");
    printf("FCFS: %.2f\n", avg_wt_fcfs);
    printf("SJF:  %.2f\n", avg_wt_sjf);
    printf("RR:   %.2f\n", avg_wt_rr);

    return 0;
}
