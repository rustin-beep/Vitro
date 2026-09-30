/* tiny_vm.c —— 迷你编译器 + 栈式虚拟机
 *
 * 编译: gcc -Wall -O2 -o tiny_vm tiny_vm.c
 * 运行: ./tiny_vm
 *
 * 流水线: 源码 → 词法 → 解析 → 字节码 → 栈式 VM
 *
 * 语言特性:
 *   let x = expr;           声明并赋值
 *   x = expr;               赋值
 *   print expr;             打印
 *   if (expr) { ... } else { ... }
 *   while (expr) { ... }
 *   { ... }                 代码块
 *
 * 表达式: 整数、+ - * / %、== != < > <= >=、一元 -、括号
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <stdint.h>

/* ================================================================
 * 1. 词法分析器
 * ================================================================ */
enum {
    T_EOF, T_NUM, T_IDENT,
    T_LET, T_PRINT, T_IF, T_ELSE, T_WHILE,
    T_PLUS, T_MINUS, T_STAR, T_SLASH, T_PERCENT,
    T_EQ, T_NE, T_LT, T_GT, T_LE, T_GE,
    T_ASSIGN, T_SEMI, T_LPAREN, T_RPAREN, T_LBRACE, T_RBRACE
};

typedef struct {
    int  type;
    long num;
    char ident[64];
} Token;

static const char *g_src;
static Token       g_tok;

static void lex_next(void)
{
    while (*g_src && isspace((unsigned char)*g_src)) g_src++;

    if (*g_src == '\0') { g_tok.type = T_EOF; return; }

    char c = *g_src;

    /* 数字 */
    if (isdigit((unsigned char)c)) {
        long v = 0;
        while (isdigit((unsigned char)*g_src))
            v = v * 10 + (*g_src++ - '0');
        g_tok.type = T_NUM;
        g_tok.num  = v;
        return;
    }

    /* 标识符 / 关键字 */
    if (isalpha((unsigned char)c) || c == '_') {
        int n = 0;
        while ((isalnum((unsigned char)*g_src) || *g_src == '_') && n < 63)
            g_tok.ident[n++] = *g_src++;
        g_tok.ident[n] = '\0';

        if      (!strcmp(g_tok.ident, "let"))   g_tok.type = T_LET;
        else if (!strcmp(g_tok.ident, "print")) g_tok.type = T_PRINT;
        else if (!strcmp(g_tok.ident, "if"))    g_tok.type = T_IF;
        else if (!strcmp(g_tok.ident, "else"))  g_tok.type = T_ELSE;
        else if (!strcmp(g_tok.ident, "while")) g_tok.type = T_WHILE;
        else                                    g_tok.type = T_IDENT;
        return;
    }

    /* 运算符 / 标点 */
    g_src++;
    switch (c) {
    case '+': g_tok.type = T_PLUS;    break;
    case '-': g_tok.type = T_MINUS;   break;
    case '*': g_tok.type = T_STAR;    break;
    case '/': g_tok.type = T_SLASH;   break;
    case '%': g_tok.type = T_PERCENT; break;
    case '(': g_tok.type = T_LPAREN;  break;
    case ')': g_tok.type = T_RPAREN;  break;
    case '{': g_tok.type = T_LBRACE;  break;
    case '}': g_tok.type = T_RBRACE;  break;
    case ';': g_tok.type = T_SEMI;    break;
    case '=':
        if (*g_src == '=') { g_src++; g_tok.type = T_EQ; }
        else               {          g_tok.type = T_ASSIGN; }
        break;
    case '!':
        if (*g_src == '=') { g_src++; g_tok.type = T_NE; }
        else { fprintf(stderr, "lex: 意外的 '!'\n"); exit(1); }
        break;
    case '<':
        if (*g_src == '=') { g_src++; g_tok.type = T_LE; }
        else               {          g_tok.type = T_LT; }
        break;
    case '>':
        if (*g_src == '=') { g_src++; g_tok.type = T_GE; }
        else               {          g_tok.type = T_GT; }
        break;
    default:
        fprintf(stderr, "lex: 非法字符 '%c'\n", c);
        exit(1);
    }
}

/* ================================================================
 * 2. 指令集 & 字节码缓冲区
 * ================================================================ */
enum {
    OP_CONST,  /* +4 字节常量                            */
    OP_LOAD,   /* +1 字节槽号：压入局部变量              */
    OP_STORE,  /* +1 字节槽号：弹出并存入局部变量        */
    OP_ADD, OP_SUB, OP_MUL, OP_DIV, OP_MOD,
    OP_NEG,    /* 一元负                                */
    OP_EQ, OP_NE, OP_LT, OP_GT, OP_LE, OP_GE,
    OP_PRINT,  /* 弹出并打印                            */
    OP_POP,    /* 弹出丢弃                              */
    OP_JMP,    /* +4 字节偏移：无条件跳转                */
    OP_JZ,     /* +4 字节偏移：弹出，为 0 则跳转         */
    OP_HALT
};

static unsigned char g_code[8192];
static int           g_code_len;

static void emit_byte(int b)
{
    if (g_code_len >= (int)sizeof(g_code)) {
        fprintf(stderr, "字节码溢出\n"); exit(1);
    }
    g_code[g_code_len++] = (unsigned char)b;
}

static int emit32(long v)
{
    if (g_code_len + 4 > (int)sizeof(g_code)) {
        fprintf(stderr, "字节码溢出\n"); exit(1);
    }
    int pos = g_code_len;
    g_code[g_code_len++] = (unsigned char)( v        & 0xff);
    g_code[g_code_len++] = (unsigned char)((v >>  8) & 0xff);
    g_code[g_code_len++] = (unsigned char)((v >> 16) & 0xff);
    g_code[g_code_len++] = (unsigned char)((v >> 24) & 0xff);
    return pos;
}

static void patch32(int pos, long v)
{
    g_code[pos    ] = (unsigned char)( v        & 0xff);
    g_code[pos + 1] = (unsigned char)((v >>  8) & 0xff);
    g_code[pos + 2] = (unsigned char)((v >> 16) & 0xff);
    g_code[pos + 3] = (unsigned char)((v >> 24) & 0xff);
}

static long read32(int *pc)
{
    uint32_t v = (uint32_t)g_code[*pc]
               | ((uint32_t)g_code[*pc + 1] <<  8)
               | ((uint32_t)g_code[*pc + 2] << 16)
               | ((uint32_t)g_code[*pc + 3] << 24);
    *pc += 4;
    return (long)(int32_t)v;   /* 关键：显式符号扩展 */
}

/* 跳转偏移基准 = 4 字节操作数之后的位置 */
static void patch_jump(int operand_pos, int target)
{
    patch32(operand_pos, (long)(target - (operand_pos + 4)));
}

/* ================================================================
 * 3. 符号表
 * ================================================================ */
typedef struct { char name[64]; int slot; } Sym;
static Sym g_syms[64];
static int g_nsyms;

static int sym_find(const char *name)
{
    for (int i = 0; i < g_nsyms; i++)
        if (!strcmp(g_syms[i].name, name)) return g_syms[i].slot;
    return -1;
}

static int sym_intern(const char *name)
{
    int s = sym_find(name);
    if (s >= 0) return s;
    if (g_nsyms >= 64) { fprintf(stderr, "变量太多\n"); exit(1); }
    strncpy(g_syms[g_nsyms].name, name, 63);
    g_syms[g_nsyms].name[63] = '\0';
    g_syms[g_nsyms].slot = g_nsyms;
    return g_nsyms++;
}

/* ================================================================
 * 4. 解析器（边解析边发射字节码）
 *
 *    表达式优先级，从低到高：
 *      expr   -> cmp
 *      cmp    -> add (('==' | '!=' | '<' | '>' | '<=' | '>=') add)*
 *      add    -> mul (('+' | '-') mul)*
 *      mul    -> unary (('*' | '/' | '%') unary)*
 *      unary  -> '-' unary | primary
 *      primary-> NUM | IDENT | '(' expr ')'
 * ================================================================ */
static void parse_expr(void);
static void parse_stmt(void);
static void parse_block(void);

static void expect(int type, const char *what)
{
    if (g_tok.type != type) {
        fprintf(stderr, "语法错误: 期望 %s (当前 token 类型 %d)\n",
                what, g_tok.type);
        exit(1);
    }
    lex_next();
}

static void parse_primary(void)
{
    if (g_tok.type == T_NUM) {
        emit_byte(OP_CONST);
        emit32(g_tok.num);
        lex_next();
        return;
    }
    if (g_tok.type == T_IDENT) {
        int slot = sym_find(g_tok.ident);
        if (slot < 0) {
            fprintf(stderr, "未定义的变量: %s\n", g_tok.ident);
            exit(1);
        }
        emit_byte(OP_LOAD);
        emit_byte(slot);
        lex_next();
        return;
    }
    if (g_tok.type == T_LPAREN) {
        lex_next();
        parse_expr();
        expect(T_RPAREN, "')'");
        return;
    }
    fprintf(stderr, "语法错误: 期望表达式\n");
    exit(1);
}

static void parse_unary(void)
{
    if (g_tok.type == T_MINUS) {
        lex_next();
        parse_unary();
        emit_byte(OP_NEG);
        return;
    }
    parse_primary();
}

static void parse_mul(void)
{
    parse_unary();
    while (g_tok.type == T_STAR || g_tok.type == T_SLASH ||
           g_tok.type == T_PERCENT) {
        int op = g_tok.type;
        lex_next();
        parse_unary();
        emit_byte(op == T_STAR  ? OP_MUL :
                  op == T_SLASH ? OP_DIV : OP_MOD);
    }
}

static void parse_add(void)
{
    parse_mul();
    while (g_tok.type == T_PLUS || g_tok.type == T_MINUS) {
        int op = g_tok.type;
        lex_next();
        parse_mul();
        emit_byte(op == T_PLUS ? OP_ADD : OP_SUB);
    }
}

static void parse_cmp(void)
{
    parse_add();
    while (g_tok.type == T_EQ || g_tok.type == T_NE ||
           g_tok.type == T_LT || g_tok.type == T_GT ||
           g_tok.type == T_LE || g_tok.type == T_GE) {
        int op = g_tok.type;
        lex_next();
        parse_add();
        switch (op) {
        case T_EQ: emit_byte(OP_EQ); break;
        case T_NE: emit_byte(OP_NE); break;
        case T_LT: emit_byte(OP_LT); break;
        case T_GT: emit_byte(OP_GT); break;
        case T_LE: emit_byte(OP_LE); break;
        case T_GE: emit_byte(OP_GE); break;
        }
    }
}

static void parse_expr(void) { parse_cmp(); }

static void parse_block(void)
{
    expect(T_LBRACE, "'{'");
    while (g_tok.type != T_RBRACE && g_tok.type != T_EOF)
        parse_stmt();
    expect(T_RBRACE, "'}'");
}

static void parse_stmt(void)
{
    /* let x = expr; */
    if (g_tok.type == T_LET) {
        lex_next();
        if (g_tok.type != T_IDENT) {
            fprintf(stderr, "语法错误: let 后需要变量名\n");
            exit(1);
        }
        int slot = sym_intern(g_tok.ident);
        lex_next();
        expect(T_ASSIGN, "'='");
        parse_expr();
        emit_byte(OP_STORE);
        emit_byte(slot);
        expect(T_SEMI, "';'");
        return;
    }

    /* print expr; */
    if (g_tok.type == T_PRINT) {
        lex_next();
        parse_expr();
        emit_byte(OP_PRINT);
        expect(T_SEMI, "';'");
        return;
    }

    /* if (expr) block [else block] */
    if (g_tok.type == T_IF) {
        lex_next();
        expect(T_LPAREN, "'('");
        parse_expr();
        expect(T_RPAREN, "')'");

        emit_byte(OP_JZ);
        int jz_pos = g_code_len;
        emit32(0);                    /* 占位，稍后回填 */

        parse_block();

        if (g_tok.type == T_ELSE) {
            emit_byte(OP_JMP);
            int jmp_pos = g_code_len;
            emit32(0);

            /* 没有 else 时 jz 跳到这里；有 else 时跳到 else 分支 */
            patch_jump(jz_pos, g_code_len);

            lex_next();
            parse_block();

            /* else 分支结束后跳过它 */
            patch_jump(jmp_pos, g_code_len);
        } else {
            patch_jump(jz_pos, g_code_len);
        }
        return;
    }

    /* while (expr) block */
    if (g_tok.type == T_WHILE) {
        lex_next();
        expect(T_LPAREN, "'('");

        int loop_start = g_code_len;   /* 循环体执行完跳回这里 */
        parse_expr();
        expect(T_RPAREN, "')'");

        emit_byte(OP_JZ);
        int jz_pos = g_code_len;
        emit32(0);                    /* 条件为假时跳出循环 */

        parse_block();

        emit_byte(OP_JMP);
        int jmp_pos = g_code_len;
        emit32(0);
        patch_jump(jmp_pos, loop_start);

        /* 循环结束位置 */
        patch_jump(jz_pos, g_code_len);
        return;
    }

    /* x = expr; */
    if (g_tok.type == T_IDENT) {
        int slot = sym_find(g_tok.ident);
        if (slot < 0) {
            fprintf(stderr, "未定义的变量: %s\n", g_tok.ident);
            exit(1);
        }
        lex_next();
        expect(T_ASSIGN, "'='");
        parse_expr();
        emit_byte(OP_STORE);
        emit_byte(slot);
        expect(T_SEMI, "';'");
        return;
    }

    /* 裸代码块 */
    if (g_tok.type == T_LBRACE) {
        parse_block();
        return;
    }

    fprintf(stderr, "语法错误: 意外的 token 类型 %d\n", g_tok.type);
    exit(1);
}

static void compile(const char *src)
{
    g_src      = src;
    g_code_len = 0;
    g_nsyms    = 0;

    lex_next();
    while (g_tok.type != T_EOF)
        parse_stmt();

    emit_byte(OP_HALT);
}

/* ================================================================
 * 5. 反汇编器（调试用）
 * ================================================================ */
static const char *op_name(int op)
{
    static const char *names[] = {
        "CONST", "LOAD", "STORE",
        "ADD", "SUB", "MUL", "DIV", "MOD", "NEG",
        "EQ", "NE", "LT", "GT", "LE", "GE",
        "PRINT", "POP",
        "JMP", "JZ", "HALT"
    };
    return names[op];
}

static void disasm(void)
{
    int pc = 0;
    while (pc < g_code_len) {
        int start = pc;
        int op    = g_code[pc++];
        printf("  %04d  %-6s", start, op_name(op));

        switch (op) {
        case OP_CONST:
            printf(" %ld", read32(&pc));
            break;
        case OP_LOAD:
        case OP_STORE:
            printf(" slot %d", g_code[pc++]);
            break;
        case OP_JMP:
        case OP_JZ: {
            int  operand_pos = pc;
            long off         = read32(&pc);
            printf(" -> %04d", operand_pos + 4 + (int)off);
            break;
        }
        }
        putchar('\n');
    }
}

/* ================================================================
 * 6. 栈式虚拟机
 * ================================================================ */
static long g_stack[512];
static long g_locals[64];
static int  g_sp;

static void run(void)
{
    g_sp = 0;
    memset(g_locals, 0, sizeof(g_locals));

    int pc = 0;
    for (;;) {
        int op = g_code[pc++];
        switch (op) {
        case OP_CONST: g_stack[g_sp++] = read32(&pc); break;
        case OP_LOAD:  g_stack[g_sp++] = g_locals[g_code[pc++]]; break;
        case OP_STORE: g_locals[g_code[pc++]] = g_stack[--g_sp]; break;

        case OP_ADD: { long b = g_stack[--g_sp], a = g_stack[--g_sp];
                       g_stack[g_sp++] = a + b; break; }
        case OP_SUB: { long b = g_stack[--g_sp], a = g_stack[--g_sp];
                       g_stack[g_sp++] = a - b; break; }
        case OP_MUL: { long b = g_stack[--g_sp], a = g_stack[--g_sp];
                       g_stack[g_sp++] = a * b; break; }
        case OP_DIV: { long b = g_stack[--g_sp], a = g_stack[--g_sp];
                       if (!b) { fprintf(stderr, "除零\n"); exit(1); }
                       g_stack[g_sp++] = a / b; break; }
        case OP_MOD: { long b = g_stack[--g_sp], a = g_stack[--g_sp];
                       if (!b) { fprintf(stderr, "取模零\n"); exit(1); }
                       g_stack[g_sp++] = a % b; break; }
        case OP_NEG: g_stack[g_sp - 1] = -g_stack[g_sp - 1]; break;

        case OP_EQ: { long b = g_stack[--g_sp], a = g_stack[--g_sp];
                      g_stack[g_sp++] = (a == b); break; }
        case OP_NE: { long b = g_stack[--g_sp], a = g_stack[--g_sp];
                      g_stack[g_sp++] = (a != b); break; }
        case OP_LT: { long b = g_stack[--g_sp], a = g_stack[--g_sp];
                      g_stack[g_sp++] = (a <  b); break; }
        case OP_GT: { long b = g_stack[--g_sp], a = g_stack[--g_sp];
                      g_stack[g_sp++] = (a >  b); break; }
        case OP_LE: { long b = g_stack[--g_sp], a = g_stack[--g_sp];
                      g_stack[g_sp++] = (a <= b); break; }
        case OP_GE: { long b = g_stack[--g_sp], a = g_stack[--g_sp];
                      g_stack[g_sp++] = (a >= b); break; }

        case OP_PRINT: printf("%ld\n", g_stack[--g_sp]); break;
        case OP_POP:   g_sp--; break;

        case OP_JMP: { long off = read32(&pc); pc += (int)off; break; }
        case OP_JZ:  { long off = read32(&pc);
                       if (g_stack[--g_sp] == 0) pc += (int)off;
                       break; }

        case OP_HALT: return;

        default:
            fprintf(stderr, "非法指令 %d @ %d\n", op, pc - 1);
            exit(1);
        }
    }
}

/* ================================================================
 * 7. 驱动
 * ================================================================ */
static void run_demo(const char *title, const char *src)
{
    printf("\n==================================================\n");
    printf("  %s\n", title);
    printf("==================================================\n");

    printf("--- 源码 ---\n%s\n", src);

    compile(src);

    printf("--- 字节码 (%d 字节) ---\n", g_code_len);
    disasm();

    printf("--- 运行结果 ---\n");
    run();
}

int main(void)
{
    printf("=== tiny_vm —— 迷你编译器 + 栈式虚拟机 ===\n");

    run_demo("1. 算术",
        "let x = 10;\n"
        "let y = 3;\n"
        "print x + y;\n"
        "print x - y;\n"
        "print x * y;\n"
        "print x / y;\n"
        "print x % y;\n"
    );

    run_demo("2. 条件分支",
        "let x = 7;\n"
        "if (x > 5) {\n"
        "    print 100;\n"
        "} else {\n"
        "    print 200;\n"
        "}\n"
    );

    run_demo("3. 循环：1 到 10 求和",
        "let i = 1;\n"
        "let sum = 0;\n"
        "while (i <= 10) {\n"
        "    sum = sum + i;\n"
        "    i = i + 1;\n"
        "}\n"
        "print sum;\n"
    );

    run_demo("4. 阶乘 6!",
        "let n = 6;\n"
        "let f = 1;\n"
        "while (n > 0) {\n"
        "    f = f * n;\n"
        "    n = n - 1;\n"
        "}\n"
        "print f;\n"
    );

    run_demo("5. FizzBuzz（数字版：15的倍数→15，3的倍数→3，5的倍数→5）",
        "let i = 1;\n"
        "while (i <= 15) {\n"
        "    if (i % 15 == 0) {\n"
        "        print 15;\n"
        "    } else {\n"
        "        if (i % 3 == 0) {\n"
        "            print 3;\n"
        "        } else {\n"
        "            if (i % 5 == 0) {\n"
        "                print 5;\n"
        "            } else {\n"
        "                print i;\n"
        "            }\n"
        "        }\n"
        "    }\n"
        "    i = i + 1;\n"
        "}\n"
    );

    return 0;
}