// @category: llm_regression
// #197 红锚：snprintf 取 struct 成员作实参被读成 0/垃圾
// 来源：LLM 探针批 10 q36a3b/BANK_s1（356 行，2026-10-21 入库；clang golden 由 clang_direct 现场生成）
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <ctype.h>

/* Constants */
#define MAX_ACCOUNTS 5
#define MAX_TRANSACTIONS 32
#define NAME_LEN 16
#define ACCOUNT_ID_LEN 5

/* Enums */
typedef enum {
    STATUS_ACTIVE,
    STATUS_CLOSED
} AccountStatus;

typedef enum {
    TYPE_DEPOSIT,
    TYPE_WITHDRAW,
    TYPE_TRANSFER
} TransactionType;

/* Structures */
typedef struct {
    char id[ACCOUNT_ID_LEN];
    char name[NAME_LEN];
    double balance;
    AccountStatus status;
} Account;

typedef struct {
    int sequence;
    TransactionType type;
    char source_id[ACCOUNT_ID_LEN];
    char target_id[ACCOUNT_ID_LEN];
    double amount;
    double balance_after;
    int success;
    char reason[64];
} TransactionRecord;

/* Global Variables */
static Account accounts[MAX_ACCOUNTS];
static TransactionRecord transactions[MAX_TRANSACTIONS];
static int transaction_count = 0;

/* Helper: Find account by ID */
static Account* find_account(const char* id) {
    for (int i = 0; i < MAX_ACCOUNTS; i++) {
        if (strcmp(accounts[i].id, id) == 0) {
            return &accounts[i];
        }
    }
    return NULL;
}

/* Helper: Format amount to string with 2 decimal places manually to avoid locale issues if any, 
   though printf %.2f is standard. We stick to printf %.2f as allowed. */

/* Function: Execute Deposit */
static void execute_deposit(const char* acc_id, double amount) {
    Account* acc = find_account(acc_id);
    if (acc == NULL) {
        /* Should not happen based on problem description but good for robustness */
        return;
    }
    
    acc->balance += amount;
    
    /* Record Transaction */
    if (transaction_count < MAX_TRANSACTIONS) {
        TransactionRecord* rec = &transactions[transaction_count];
        rec->sequence = transaction_count + 1;
        rec->type = TYPE_DEPOSIT;
        strcpy(rec->source_id, acc_id);
        strcpy(rec->target_id, "N/A");
        rec->amount = amount;
        rec->balance_after = acc->balance;
        rec->success = 1;
        strcpy(rec->reason, "Success");
        transaction_count++;
    }
}

/* Function: Execute Withdraw */
static void execute_withdraw(const char* acc_id, double amount) {
    Account* acc = find_account(acc_id);
    if (acc == NULL) {
        return;
    }
    
    if (acc->balance < amount) {
        /* Record Failed Transaction */
        if (transaction_count < MAX_TRANSACTIONS) {
            TransactionRecord* rec = &transactions[transaction_count];
            rec->sequence = transaction_count + 1;
            rec->type = TYPE_WITHDRAW;
            strcpy(rec->source_id, acc_id);
            strcpy(rec->target_id, "N/A");
            rec->amount = amount;
            rec->balance_after = acc->balance;
            rec->success = 0;
            snprintf(rec->reason, sizeof(rec->reason), "Insufficient funds: Balance %.2f < %.2f", acc->balance, amount);
            transaction_count++;
        }
        return;
    }
    
    acc->balance -= amount;
    
    /* Record Successful Transaction */
    if (transaction_count < MAX_TRANSACTIONS) {
        TransactionRecord* rec = &transactions[transaction_count];
        rec->sequence = transaction_count + 1;
        rec->type = TYPE_WITHDRAW;
        strcpy(rec->source_id, acc_id);
        strcpy(rec->target_id, "N/A");
        rec->amount = amount;
        rec->balance_after = acc->balance;
        rec->success = 1;
        strcpy(rec->reason, "Success");
        transaction_count++;
    }
}

/* Function: Execute Transfer */
static void execute_transfer(const char* src_id, const char* dst_id, double amount) {
    Account* src = find_account(src_id);
    Account* dst = find_account(dst_id);
    
    if (src == NULL || dst == NULL) {
        return;
    }
    
    if (src->balance < amount) {
        /* Record Failed Transaction */
        if (transaction_count < MAX_TRANSACTIONS) {
            TransactionRecord* rec = &transactions[transaction_count];
            rec->sequence = transaction_count + 1;
            rec->type = TYPE_TRANSFER;
            strcpy(rec->source_id, src_id);
            strcpy(rec->target_id, dst_id);
            rec->amount = amount;
            rec->balance_after = src->balance;
            rec->success = 0;
            snprintf(rec->reason, sizeof(rec->reason), "Insufficient funds: Balance %.2f < %.2f", src->balance, amount);
            transaction_count++;
        }
        return;
    }
    
    /* Perform Transfer */
    src->balance -= amount;
    dst->balance += amount;
    
    /* Record Successful Transaction */
    if (transaction_count < MAX_TRANSACTIONS) {
        TransactionRecord* rec = &transactions[transaction_count];
        rec->sequence = transaction_count + 1;
        rec->type = TYPE_TRANSFER;
        strcpy(rec->source_id, src_id);
        strcpy(rec->target_id, dst_id);
        rec->amount = amount;
        rec->balance_after = src->balance;
        rec->success = 1;
        strcpy(rec->reason, "Success");
        transaction_count++;
    }
}

/* Helper: Get Transaction Type String */
static const char* get_type_string(TransactionType type) {
    switch (type) {
        case TYPE_DEPOSIT: return "DEPOSIT";
        case TYPE_WITHDRAW: return "WITHDRAW";
        case TYPE_TRANSFER: return "TRANSFER";
        default: return "UNKNOWN";
    }
}

/* Helper: Get Account Name by ID */
static const char* get_account_name(const char* id) {
    Account* acc = find_account(id);
    if (acc) return acc->name;
    return "Unknown";
}

int main(void) {
    /* Initialize Accounts */
    /* Using a static array of initializers */
    static const char initial_ids[MAX_ACCOUNTS][ACCOUNT_ID_LEN] = {"A1", "A2", "A3", "A4", "A5"};
    static const char initial_names[MAX_ACCOUNTS][NAME_LEN] = {"Alice", "Bob", "Charlie", "David", "Eve"};
    static const double initial_balances[MAX_ACCOUNTS] = {1000.0, 2000.0, 3000.0, 4000.0, 5000.0};

    for (int i = 0; i < MAX_ACCOUNTS; i++) {
        strcpy(accounts[i].id, initial_ids[i]);
        strcpy(accounts[i].name, initial_names[i]);
        accounts[i].balance = initial_balances[i];
        accounts[i].status = STATUS_ACTIVE;
    }

    /* Execute 10 Transactions */
    
    /* 1. A1 Deposit 500 */
    execute_deposit("A1", 500.0);
    printf("Tx %d: Type=DEPOSIT, Amount=%.2f, Status=%s\n", 
           transactions[0].sequence, transactions[0].amount, 
           transactions[0].success ? "Success" : transactions[0].reason);

    /* 2. A2 Withdraw 200 */
    execute_withdraw("A2", 200.0);
    printf("Tx %d: Type=WITHDRAW, Amount=%.2f, Status=%s\n", 
           transactions[1].sequence, transactions[1].amount, 
           transactions[1].success ? "Success" : transactions[1].reason);

    /* 3. A1 Transfer to A3 300 */
    execute_transfer("A1", "A3", 300.0);
    printf("Tx %d: Type=TRANSFER, Amount=%.2f, Status=%s\n", 
           transactions[2].sequence, transactions[2].amount, 
           transactions[2].success ? "Success" : transactions[2].reason);

    /* 4. A2 Withdraw 99999 (Fail) */
    execute_withdraw("A2", 99999.0);
    printf("Tx %d: Type=WITHDRAW, Amount=%.2f, Status=%s\n", 
           transactions[3].sequence, transactions[3].amount, 
           transactions[3].success ? "Success" : transactions[3].reason);

    /* 5. A4 Deposit 1200 */
    execute_deposit("A4", 1200.0);
    printf("Tx %d: Type=DEPOSIT, Amount=%.2f, Status=%s\n", 
           transactions[4].sequence, transactions[4].amount, 
           transactions[4].success ? "Success" : transactions[4].reason);

    /* 6. A3 Transfer to A5 150 */
    execute_transfer("A3", "A5", 150.0);
    printf("Tx %d: Type=TRANSFER, Amount=%.2f, Status=%s\n", 
           transactions[5].sequence, transactions[5].amount, 
           transactions[5].success ? "Success" : transactions[5].reason);

    /* 7. A5 Withdraw 5000 (Fail) */
    execute_withdraw("A5", 5000.0);
    printf("Tx %d: Type=WITHDRAW, Amount=%.2f, Status=%s\n", 
           transactions[6].sequence, transactions[6].amount, 
           transactions[6].success ? "Success" : transactions[6].reason);

    /* 8. A2 Deposit 80 */
    execute_deposit("A2", 80.0);
    printf("Tx %d: Type=DEPOSIT, Amount=%.2f, Status=%s\n", 
           transactions[7].sequence, transactions[7].amount, 
           transactions[7].success ? "Success" : transactions[7].reason);

    /* 9. A4 Transfer to A1 400 */
    execute_transfer("A4", "A1", 400.0);
    printf("Tx %d: Type=TRANSFER, Amount=%.2f, Status=%s\n", 
           transactions[8].sequence, transactions[8].amount, 
           transactions[8].success ? "Success" : transactions[8].reason);

    /* 10. A1 Withdraw 100 */
    execute_withdraw("A1", 100.0);
    printf("Tx %d: Type=WITHDRAW, Amount=%.2f, Status=%s\n", 
           transactions[9].sequence, transactions[9].amount, 
           transactions[9].success ? "Success" : transactions[9].reason);

    printf("\n--- Transaction Ledger ---\n");
    printf("%-5s %-10s %-5s %-5s %-12s %-15s\n", "Seq", "Type", "From", "To", "Amount", "Balance After");
    printf("%-5s %-10s %-5s %-5s %-12s %-15s\n", "-----", "----------", "-----", "-----", "------------", "---------------");
    
    for (int i = 0; i < transaction_count; i++) {
        printf("%-5d %-10s %-5s %-5s %-12.2f %-15.2f",
               transactions[i].sequence,
               get_type_string(transactions[i].type),
               transactions[i].source_id,
               transactions[i].target_id,
               transactions[i].amount,
               transactions[i].balance_after);
        if (!transactions[i].success) {
            printf(" (%s)", transactions[i].reason);
        }
        printf("\n");
    }

    printf("\n--- End of Day Reconciliation ---\n");
    printf("%-5s %-10s %-12s %-12s %-12s %-12s %-8s\n", 
           "ID", "Name", "Start Bal", "Income", "Expense", "End Bal", "Check");
    printf("%-5s %-10s %-12s %-12s %-12s %-12s %-8s\n", 
           "-----", "----------", "------------", "------------", "------------", "------------", "--------");

    double total_assets = 0.0;
    int success_count = 0;
    int fail_count = 0;

    for (int i = 0; i < MAX_ACCOUNTS; i++) {
        double start_bal = initial_balances[i];
        double income = 0.0;
        double expense = 0.0;
        
        /* Calculate Income and Expense from transactions */
        for (int j = 0; j < transaction_count; j++) {
            if (transactions[j].success) {
                if (strcmp(transactions[j].target_id, accounts[i].id) == 0 && 
                    transactions[j].type != TYPE_DEPOSIT) {
                    /* Received money via transfer */
                    income += transactions[j].amount;
                }
                if (strcmp(transactions[j].source_id, accounts[i].id) == 0) {
                    /* Sent money via withdraw or transfer */
                    expense += transactions[j].amount;
                }
                /* Note: Deposit adds to balance but is not "Income" from another account, 
                   but for reconciliation, Income usually means total inflows. 
                   Let's define Income as total credits to the account and Expense as total debits. */
                if (transactions[j].type == TYPE_DEPOSIT && strcmp(transactions[j].source_id, accounts[i].id) == 0) {
                     income += transactions[j].amount;
                }
            }
        }
        
        /* Recalculate End Balance directly from account struct to ensure accuracy */
        double end_bal = accounts[i].balance;
        
        /* Verify Check: Start + Income - Expense == End */
        /* Note: In a real system, Income/Expense are derived from transactions. 
           Here, we derived them above. Let's verify consistency. */
        
        double check_val = start_bal + income - expense;
        /* Use a small epsilon for double comparison */
        int is_balanced = (fabs(check_val - end_bal) < 0.001);
        
        total_assets += end_bal;
        
        printf("%-5s %-10s %-12.2f %-12.2f %-12.2f %-12.2f %-8s\n",
               accounts[i].id,
               accounts[i].name,
               start_bal,
               income,
               expense,
               end_bal,
               is_balanced ? "OK" : "ERROR");
    }

    printf("\n--- Summary ---\n");
    printf("Total Assets: %.2f\n", total_assets);
    
    /* Count Success/Fail */
    for (int i = 0; i < transaction_count; i++) {
        if (transactions[i].success) success_count++;
        else fail_count++;
    }
    
    printf("Successful Transactions: %d\n", success_count);
    printf("Failed Transactions: %d\n", fail_count);

    return 0;
}
