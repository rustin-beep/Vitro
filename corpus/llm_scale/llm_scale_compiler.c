// @category: llm_scale
// 规模压力面：C 子集编译器：词法 + 递归下降 AST + 作用域符号表 + 直接解释执行 AST
// 来源：LLM 千行语料 HUGE-COMPILER（1626 行，2026-10-21 入库；clang golden 由 clang_direct 现场生成）
// 注：本档 member_accesses 上限 400（#236 分档），见 scripts/perf_budget/rules.json
/*
 * HUGE-COMPILER -- a compiler for a small C dialect in one C23 file.
 *
 * The compiler works in three stages.
 *
 * The lexer turns the source text into a token array. It recognises
 * identifiers, integer literals, string literals, the operators
 *
 *     + - * / % = == != < > <= >= && || !
 *
 * the delimiters ( ) { } ; , and the keywords int, if, else, while,
 * return and print. Every token remembers the line and the column it was
 * found at.
 *
 * The parser is a recursive descent parser that builds an abstract syntax
 * tree in a static node array. Expressions are parsed with precedence
 * climbing, statements cover variable declarations, assignments, if and
 * else, while loops, return, print and blocks. A function definition
 * starts with the keyword int, a name and a parameter list.
 *
 * The symbol table maps names to value slots and supports block scopes
 * that are pushed and popped while the tree is walked.
 *
 * The interpreter executes the tree directly. Function calls are supported
 * for up to eight functions and recursion works, every call gets its own
 * scope.
 *
 * A fixed source program with a recursive factorial, a recursive
 * Fibonacci, a while loop, a nested if and string output is compiled and
 * executed. The run prints the number of tokens, the number of tree
 * nodes, the results of the program, the final symbol table and the number
 * of executed steps. Three broken programs show how the errors are
 * reported.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

/* ------------------------------------------------------------------ */
/* limits                                                             */
/* ------------------------------------------------------------------ */

#define MAX_TOKENS 512
#define MAX_NODES 512
#define MAX_SYMS 256
#define MAX_SCOPES 64
#define MAX_SLOTS 256
#define MAX_FUNCS 8
#define MAX_PARAMS 4
#define MAX_CALL_DEPTH 64
#define NAME_LEN 24
#define TEXT_LEN 48
#define SRC_LEN 2048

/* ------------------------------------------------------------------ */
/* token kinds                                                        */
/* ------------------------------------------------------------------ */

typedef enum {
    TOK_EOF = 0,
    TOK_INT,
    TOK_IDENT,
    TOK_STRING,
    TOK_KEYWORD,
    TOK_OP
} TokenKind;

typedef struct {
    TokenKind kind;
    int value;
    char text[NAME_LEN];
    int line;
    int column;
} Token;

typedef struct {
    char name[NAME_LEN];
    int scope;
    int slot;
} Symbol;

typedef struct {
    Symbol symbols[MAX_SYMS];
    int count;
    int scope_depth;
    int scope_start[MAX_SCOPES];
    int slots[MAX_SLOTS];
    int slot_count;
} Env;

typedef struct {
    char name[NAME_LEN];
    char params[MAX_PARAMS][NAME_LEN];
    int param_count;
    int body;
    int defined;
} Function;

/* ------------------------------------------------------------------ */
/* tree node kinds                                                    */
/* ------------------------------------------------------------------ */

enum {
    AST_INT = 1,
    AST_STR,
    AST_IDENT,
    AST_BINOP,
    AST_UNOP,
    AST_ASSIGN,
    AST_VAR,
    AST_IF,
    AST_WHILE,
    AST_RETURN,
    AST_PRINT,
    AST_BLOCK,
    AST_CALL,
    AST_FUNC
};

enum {
    OP_ADD = 1,
    OP_SUB,
    OP_MUL,
    OP_DIV,
    OP_MOD,
    OP_ASSIGN,
    OP_EQ,
    OP_NE,
    OP_LT,
    OP_GT,
    OP_LE,
    OP_GE,
    OP_AND,
    OP_OR,
    OP_NOT,
    OP_NEG
};

typedef struct {
    int kind;
    int line;
    int value;
    int op;
    char text[NAME_LEN];
    int a;
    int b;
    int c;
    int next;
} AstNode;

typedef struct {
    Token tokens[MAX_TOKENS];
    int count;
    int position;
    int line;
    int column;
    int line_start;
    int failed;
    char error[TEXT_LEN];
    AstNode nodes[MAX_NODES];
    int node_count;
    Function functions[MAX_FUNCS];
    int function_count;
    Env env;
    int steps;
    int output_lines;
    int returning;
    int return_value;
    int call_depth;
} Compiler;

static const char *const KEYWORDS[] = {
    "int", "if", "else", "while", "return", "print"
};

static const int KEYWORD_COUNT = (int)(sizeof KEYWORDS / sizeof KEYWORDS[0]);

static const char *const OPERATORS[] = {
    "==", "!=", "<=", ">=", "&&", "||",
    "+", "-", "*", "/", "%", "=", "<", ">", "!"
};

static const int OPERATOR_COUNT = (int)(sizeof OPERATORS / sizeof OPERATORS[0]);

/* ------------------------------------------------------------------ */
/* helpers                                                            */
/* ------------------------------------------------------------------ */

static void cmp_copy(char *dst, size_t cap, const char *src)
{
    size_t n;

    if (dst == NULL || src == NULL || cap == 0) {
        return;
    }
    n = strlen(src);
    if (n > cap - 1) {
        n = cap - 1;
    }
    memcpy(dst, src, n);
    dst[n] = '\0';
}

static int cmp_is_keyword(const char *text)
{
    int i;

    for (i = 0; i < KEYWORD_COUNT; i++) {
        if (strcmp(KEYWORDS[i], text) == 0) {
            return 1;
        }
    }
    return 0;
}

static int cmp_is_operator(const char *text)
{
    int i;

    for (i = 0; i < OPERATOR_COUNT; i++) {
        if (strcmp(OPERATORS[i], text) == 0) {
            return 1;
        }
    }
    return 0;
}

static int cmp_operator_code(const char *text)
{
    if (strcmp(text, "+") == 0) {
        return OP_ADD;
    }
    if (strcmp(text, "-") == 0) {
        return OP_SUB;
    }
    if (strcmp(text, "*") == 0) {
        return OP_MUL;
    }
    if (strcmp(text, "/") == 0) {
        return OP_DIV;
    }
    if (strcmp(text, "%") == 0) {
        return OP_MOD;
    }
    if (strcmp(text, "=") == 0) {
        return OP_ASSIGN;
    }
    if (strcmp(text, "==") == 0) {
        return OP_EQ;
    }
    if (strcmp(text, "!=") == 0) {
        return OP_NE;
    }
    if (strcmp(text, "<") == 0) {
        return OP_LT;
    }
    if (strcmp(text, ">") == 0) {
        return OP_GT;
    }
    if (strcmp(text, "<=") == 0) {
        return OP_LE;
    }
    if (strcmp(text, ">=") == 0) {
        return OP_GE;
    }
    if (strcmp(text, "&&") == 0) {
        return OP_AND;
    }
    if (strcmp(text, "||") == 0) {
        return OP_OR;
    }
    if (strcmp(text, "!") == 0) {
        return OP_NOT;
    }
    return 0;
}

/* ------------------------------------------------------------------ */
/* lexer                                                              */
/* ------------------------------------------------------------------ */

static void cmp_fail(Compiler *compiler, int line, const char *message)
{
    if (compiler->failed) {
        return;
    }
    compiler->failed = 1;
    sprintf(compiler->error, "line %d: %s", line, message);
}

static Token *cmp_add_token(Compiler *compiler, TokenKind kind, int line, int column)
{
    Token *token;

    if (compiler->count >= MAX_TOKENS) {
        cmp_fail(compiler, line, "too many tokens");
        return NULL;
    }
    token = &compiler->tokens[compiler->count];
    token->kind = kind;
    token->value = 0;
    token->text[0] = '\0';
    token->line = line;
    token->column = column;
    compiler->count++;
    return token;
}

static void cmp_advance(Compiler *compiler, char c)
{
    if (c == '\n') {
        compiler->line++;
        compiler->line_start = compiler->column;
    }
    compiler->column++;
}

/* the column inside the current line, the column field itself is the source offset */
static int cmp_current_column(const Compiler *compiler)
{
    return compiler->column - compiler->line_start + 1;
}

static int cmp_lex_number(Compiler *compiler, const char *source)
{
    int start = cmp_current_column(compiler);
    int value = 0;
    Token *token;

    while (isdigit((unsigned char)source[compiler->column - 1])) {        value = value * 10 + (source[compiler->column - 1] - '0');
        cmp_advance(compiler, source[compiler->column - 1]);
    }
    token = cmp_add_token(compiler, TOK_INT, compiler->line, start);
    if (token != NULL) {
        token->value = value;
        sprintf(token->text, "%d", value);
    }
    return 0;
}

static int cmp_lex_identifier(Compiler *compiler, const char *source)
{
    int start = cmp_current_column(compiler);
    int length = 0;
    char buffer[NAME_LEN];
    Token *token;

    while (isalpha((unsigned char)source[compiler->column - 1]) ||
           source[compiler->column - 1] == '_') {
        if (length < NAME_LEN - 1) {
            buffer[length] = source[compiler->column - 1];
            length++;
        }
        cmp_advance(compiler, source[compiler->column - 1]);
    }
    buffer[length] = '\0';
    token = cmp_add_token(compiler,
                          cmp_is_keyword(buffer) ? TOK_KEYWORD : TOK_IDENT,
                          compiler->line, start);
    if (token != NULL) {
        cmp_copy(token->text, NAME_LEN, buffer);
    }
    return 0;
}

static int cmp_lex_string(Compiler *compiler, const char *source)
{
    int start = cmp_current_column(compiler);
    char buffer[TEXT_LEN];
    int length = 0;
    Token *token;

    cmp_advance(compiler, source[compiler->column - 1]);
    while (source[compiler->column - 1] != '"' && source[compiler->column - 1] != '\0') {
        char c = source[compiler->column - 1];
        if (c == '\\' && source[compiler->column] == 'n') {
            if (length < TEXT_LEN - 1) {
                buffer[length] = '\n';
                length++;
            }
            cmp_advance(compiler, c);
            cmp_advance(compiler, source[compiler->column - 1]);
            continue;
        }
        if (length < TEXT_LEN - 1) {
            buffer[length] = c;
            length++;
        }
        cmp_advance(compiler, c);
    }
    if (source[compiler->column - 1] != '"') {
        cmp_fail(compiler, compiler->line, "unterminated string literal");
        return -1;
    }
    buffer[length] = '\0';
    cmp_advance(compiler, source[compiler->column - 1]);
    token = cmp_add_token(compiler, TOK_STRING, compiler->line, start);
    if (token != NULL) {
        cmp_copy(token->text, TEXT_LEN, buffer);
    }
    return 0;
}

static int cmp_lex_operator(Compiler *compiler, const char *source)
{
    char buffer[4];
    int i;
    int doubled = 0;
    Token *token;

    buffer[0] = source[compiler->column - 1];
    buffer[1] = '\0';
    for (i = 0; i < OPERATOR_COUNT; i++) {
        if (strlen(OPERATORS[i]) == 2 &&
            source[compiler->column - 1] == OPERATORS[i][0] &&
            source[compiler->column] == OPERATORS[i][1]) {
            buffer[0] = OPERATORS[i][0];
            buffer[1] = OPERATORS[i][1];
            buffer[2] = '\0';
            doubled = 1;
            break;
        }
    }
    cmp_advance(compiler, buffer[0]);
    if (doubled) {
        cmp_advance(compiler, buffer[1]);
    }
    if (!cmp_is_operator(buffer)) {
        char message[TEXT_LEN];
        sprintf(message, "unknown character '%s'", buffer);
        cmp_fail(compiler, compiler->line, message);
        return -1;
    }
    token = cmp_add_token(compiler, TOK_OP, compiler->line, cmp_current_column(compiler));
    if (token != NULL) {
        cmp_copy(token->text, NAME_LEN, buffer);
    }
    return 0;
}

static int cmp_lex(Compiler *compiler, const char *source)
{
    compiler->count = 0;
    compiler->line = 1;
    compiler->column = 1;
    compiler->line_start = 1;
    compiler->failed = 0;
    compiler->error[0] = '\0';
    while (source[compiler->column - 1] != '\0') {
        char c = source[compiler->column - 1];
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
            cmp_advance(compiler, c);
            continue;
        }
        if (c == '/' && source[compiler->column] == '/') {
            while (source[compiler->column - 1] != '\0' && source[compiler->column - 1] != '\n') {
                cmp_advance(compiler, source[compiler->column - 1]);
            }
            continue;
        }
        if (isdigit((unsigned char)c)) {
            cmp_lex_number(compiler, source);
            continue;
        }
        if (isalpha((unsigned char)c) || c == '_') {
            cmp_lex_identifier(compiler, source);
            continue;
        }
        if (c == '"') {
            if (cmp_lex_string(compiler, source) != 0) {
                return -1;
            }
            continue;
        }
        if (strchr("(){};,", c) != NULL) {
            Token *token = cmp_add_token(compiler, TOK_OP, compiler->line, cmp_current_column(compiler));
            if (token != NULL) {
                token->text[0] = c;
                token->text[1] = '\0';
            }
            cmp_advance(compiler, c);
            continue;
        }
        cmp_lex_operator(compiler, source);
    }
    cmp_add_token(compiler, TOK_EOF, compiler->line, compiler->column);
    return compiler->failed ? -1 : 0;
}

static const char *cmp_token_kind_name(TokenKind kind)
{
    switch (kind) {
        case TOK_EOF:
            return "eof";
        case TOK_INT:
            return "int";
        case TOK_IDENT:
            return "ident";
        case TOK_STRING:
            return "string";
        case TOK_KEYWORD:
            return "keyword";
        case TOK_OP:
            return "op";
        default:
            return "token";
    }
}

static void cmp_print_tokens(const Compiler *compiler)
{
    int i;

    printf("  token count = %d\n", compiler->count);
    for (i = 0; i < compiler->count && i < 24; i++) {
        const Token *token = &compiler->tokens[i];
        printf("    %3d  %-7s %-8s line=%d col=%d\n", i, cmp_token_kind_name(token->kind),
               token->text, token->line, token->column);
    }
    if (compiler->count > 24) {
        printf("    ... %d more tokens\n", compiler->count - 24);
    }
}

/* ------------------------------------------------------------------ */
/* tree construction                                                   */
/* ------------------------------------------------------------------ */

static int cmp_node_new(Compiler *compiler, int kind, int line)
{
    AstNode *node;

    if (compiler->node_count >= MAX_NODES) {
        cmp_fail(compiler, line, "the tree is full");
        return -1;
    }
    node = &compiler->nodes[compiler->node_count];
    memset(node, 0, sizeof(AstNode));
    node->kind = kind;
    node->line = line;
    node->a = -1;
    node->b = -1;
    node->c = -1;
    node->next = -1;
    return compiler->node_count++;
}

static Token *cmp_peek(Compiler *compiler)
{
    return &compiler->tokens[compiler->position];
}

static Token *cmp_take(Compiler *compiler)
{
    Token *token = &compiler->tokens[compiler->position];

    if (token->kind != TOK_EOF) {
        compiler->position++;
    }
    return token;
}

static int cmp_check_op(Compiler *compiler, const char *text)
{
    Token *token = cmp_peek(compiler);

    return (token->kind == TOK_OP && strcmp(token->text, text) == 0) ? 1 : 0;
}

static int cmp_check_keyword(Compiler *compiler, const char *text)
{
    Token *token = cmp_peek(compiler);

    return (token->kind == TOK_KEYWORD && strcmp(token->text, text) == 0) ? 1 : 0;
}

static int cmp_expect_op(Compiler *compiler, const char *text)
{
    if (!cmp_check_op(compiler, text)) {
        char message[TEXT_LEN];
        sprintf(message, "expected '%s' but found '%s'", text, cmp_peek(compiler)->text);
        cmp_fail(compiler, cmp_peek(compiler)->line, message);
        return -1;
    }
    cmp_take(compiler);
    return 0;
}

static int cmp_precedence(const char *op)
{
    if (strcmp(op, "||") == 0) {
        return 1;
    }
    if (strcmp(op, "&&") == 0) {
        return 2;
    }
    if (strcmp(op, "==") == 0 || strcmp(op, "!=") == 0) {
        return 3;
    }
    if (strcmp(op, "<") == 0 || strcmp(op, ">") == 0 ||
        strcmp(op, "<=") == 0 || strcmp(op, ">=") == 0) {
        return 4;
    }
    if (strcmp(op, "+") == 0 || strcmp(op, "-") == 0) {
        return 5;
    }
    if (strcmp(op, "*") == 0 || strcmp(op, "/") == 0 || strcmp(op, "%") == 0) {
        return 6;
    }
    return 0;
}

/* ------------------------------------------------------------------ */
/* parser                                                             */
/* ------------------------------------------------------------------ */

static int cmp_parse_expression(Compiler *compiler, int min_precedence);
static int cmp_parse_statement(Compiler *compiler);
static int cmp_parse_block(Compiler *compiler);

static int cmp_parse_primary(Compiler *compiler)
{
    Token *token = cmp_peek(compiler);

    if (token->kind == TOK_INT) {
        int node = cmp_node_new(compiler, AST_INT, token->line);
        if (node < 0) {
            return -1;
        }
        compiler->nodes[node].value = token->value;
        cmp_take(compiler);
        return node;
    }
    if (token->kind == TOK_STRING) {
        int node = cmp_node_new(compiler, AST_STR, token->line);
        if (node < 0) {
            return -1;
        }
        cmp_copy(compiler->nodes[node].text, NAME_LEN, token->text);
        cmp_take(compiler);
        return node;
    }
    if (token->kind == TOK_IDENT) {
        char name[NAME_LEN];
        int node;
        cmp_copy(name, NAME_LEN, token->text);
        cmp_take(compiler);
        if (cmp_check_op(compiler, "(")) {
            int first = -1;
            int last = -1;
            int func = -1;
            int i;
            cmp_take(compiler);
            for (i = 0; i < compiler->function_count; i++) {
                if (strcmp(compiler->functions[i].name, name) == 0) {
                    func = i;
                }
            }
            while (!cmp_check_op(compiler, ")")) {
                int argument = cmp_parse_expression(compiler, 0);
                if (argument < 0) {
                    return -1;
                }
                if (first < 0) {
                    first = argument;
                } else {
                    compiler->nodes[last].next = argument;
                }
                last = argument;
                if (cmp_check_op(compiler, ",")) {
                    cmp_take(compiler);
                    continue;
                }
                break;
            }
            if (cmp_expect_op(compiler, ")") != 0) {
                return -1;
            }
            node = cmp_node_new(compiler, AST_CALL, token->line);
            if (node < 0) {
                return -1;
            }
            cmp_copy(compiler->nodes[node].text, NAME_LEN, name);
            compiler->nodes[node].a = first;
            compiler->nodes[node].value = func;
            return node;
        }
        node = cmp_node_new(compiler, AST_IDENT, token->line);
        if (node < 0) {
            return -1;
        }
        cmp_copy(compiler->nodes[node].text, NAME_LEN, name);
        return node;
    }
    if (cmp_check_op(compiler, "(")) {
        int inner;
        cmp_take(compiler);
        inner = cmp_parse_expression(compiler, 0);
        if (inner < 0) {
            return -1;
        }
        if (cmp_expect_op(compiler, ")") != 0) {
            return -1;
        }
        return inner;
    }
    {
        char message[TEXT_LEN];
        sprintf(message, "unexpected token '%s' in an expression", token->text);
        cmp_fail(compiler, token->line, message);
    }
    return -1;
}

static int cmp_parse_unary(Compiler *compiler)
{
    Token *token = cmp_peek(compiler);

    if (token->kind == TOK_OP && (strcmp(token->text, "!") == 0 || strcmp(token->text, "-") == 0)) {
        int operand;
        int node;
        int op = (strcmp(token->text, "!") == 0) ? OP_NOT : OP_NEG;
        cmp_take(compiler);
        operand = cmp_parse_unary(compiler);
        if (operand < 0) {
            return -1;
        }
        node = cmp_node_new(compiler, AST_UNOP, token->line);
        if (node < 0) {
            return -1;
        }
        compiler->nodes[node].op = op;
        compiler->nodes[node].a = operand;
        return node;
    }
    return cmp_parse_primary(compiler);
}

static int cmp_parse_expression(Compiler *compiler, int min_precedence)
{
    int left = cmp_parse_unary(compiler);

    if (left < 0) {
        return -1;
    }
    for (;;) {
        Token *token = cmp_peek(compiler);
        int precedence;
        int right;
        int node;
        if (token->kind != TOK_OP) {
            break;
        }
        precedence = cmp_precedence(token->text);
        if (precedence == 0 || precedence < min_precedence) {
            break;
        }
        cmp_take(compiler);
        right = cmp_parse_expression(compiler, precedence + 1);
        if (right < 0) {
            return -1;
        }
        node = cmp_node_new(compiler, AST_BINOP, token->line);
        if (node < 0) {
            return -1;
        }
        compiler->nodes[node].op = cmp_operator_code(token->text);
        compiler->nodes[node].a = left;
        compiler->nodes[node].b = right;
        left = node;
    }
    return left;
}

static int cmp_parse_block(Compiler *compiler)
{
    int first = -1;
    int last = -1;

    if (cmp_expect_op(compiler, "{") != 0) {
        return -1;
    }
    while (!cmp_check_op(compiler, "}")) {
        Token *token = cmp_peek(compiler);
        int statement;
        if (token->kind == TOK_EOF) {
            cmp_fail(compiler, token->line, "the block is not closed");
            return -1;
        }
        statement = cmp_parse_statement(compiler);
        if (statement < 0) {
            return -1;
        }
        if (first < 0) {
            first = statement;
        } else {
            compiler->nodes[last].next = statement;
        }
        last = statement;
    }
    cmp_take(compiler);
    {
        int node = cmp_node_new(compiler, AST_BLOCK, cmp_peek(compiler)->line);
        if (node < 0) {
            return -1;
        }
        compiler->nodes[node].a = first;
        return node;
    }
}

static int cmp_parse_function(Compiler *compiler, int line)
{
    Token *name_token = cmp_take(compiler);
    Function *function;
    int index;
    int body;

    if (compiler->function_count >= MAX_FUNCS) {
        cmp_fail(compiler, line, "too many functions");
        return -1;
    }
    index = compiler->function_count;
    function = &compiler->functions[index];
    memset(function, 0, sizeof(Function));
    cmp_copy(function->name, NAME_LEN, name_token->text);
    /* the function is registered before the body is parsed so that a recursive
     * call inside the body can already find it */
    compiler->function_count++;
    if (cmp_expect_op(compiler, "(") != 0) {
        return -1;
    }    while (!cmp_check_op(compiler, ")")) {
        if (cmp_check_keyword(compiler, "int")) {
            cmp_take(compiler);
        }
        if (cmp_peek(compiler)->kind != TOK_IDENT) {
            cmp_fail(compiler, cmp_peek(compiler)->line, "a parameter needs a name");
            return -1;
        }
        if (function->param_count >= MAX_PARAMS) {
            cmp_fail(compiler, cmp_peek(compiler)->line, "too many parameters");
            return -1;
        }
        cmp_copy(function->params[function->param_count], NAME_LEN, cmp_take(compiler)->text);
        function->param_count++;
        if (cmp_check_op(compiler, ",")) {
            cmp_take(compiler);
            continue;
        }
        break;
    }
    if (cmp_expect_op(compiler, ")") != 0) {
        return -1;
    }
    body = cmp_parse_block(compiler);
    if (body < 0) {
        return -1;
    }
    function->body = body;
    function->defined = 1;
    {
        int node = cmp_node_new(compiler, AST_FUNC, line);
        if (node < 0) {
            return -1;
        }
        cmp_copy(compiler->nodes[node].text, NAME_LEN, function->name);
        compiler->nodes[node].a = body;
        compiler->nodes[node].value = index;
        return node;
    }
}

static int cmp_parse_statement(Compiler *compiler)
{
    Token *token = cmp_peek(compiler);

    if (cmp_check_keyword(compiler, "int")) {
        cmp_take(compiler);
        if (cmp_peek(compiler)->kind == TOK_IDENT &&
            compiler->tokens[compiler->position + 1].kind == TOK_OP &&
            strcmp(compiler->tokens[compiler->position + 1].text, "(") == 0) {
            return cmp_parse_function(compiler, token->line);
        }
        if (cmp_peek(compiler)->kind != TOK_IDENT) {
            cmp_fail(compiler, token->line, "a declaration needs a name");
            return -1;
        }
        {
            char name[NAME_LEN];
            int node;
            cmp_copy(name, NAME_LEN, cmp_take(compiler)->text);
            if (cmp_check_op(compiler, "=")) {
                int expression;
                cmp_take(compiler);
                expression = cmp_parse_expression(compiler, 0);
                if (expression < 0) {
                    return -1;
                }
                node = cmp_node_new(compiler, AST_VAR, token->line);
                if (node < 0) {
                    return -1;
                }
                cmp_copy(compiler->nodes[node].text, NAME_LEN, name);
                compiler->nodes[node].a = expression;
            } else {
                node = cmp_node_new(compiler, AST_VAR, token->line);
                if (node < 0) {
                    return -1;
                }
                cmp_copy(compiler->nodes[node].text, NAME_LEN, name);
            }
            if (cmp_expect_op(compiler, ";") != 0) {
                return -1;
            }
            return node;
        }
    }
    if (cmp_check_keyword(compiler, "if")) {
        int node;
        int condition;
        int then_branch;
        int else_branch = -1;
        cmp_take(compiler);
        if (cmp_expect_op(compiler, "(") != 0) {
            return -1;
        }
        condition = cmp_parse_expression(compiler, 0);
        if (condition < 0) {
            return -1;
        }
        if (cmp_expect_op(compiler, ")") != 0) {
            return -1;
        }
        then_branch = cmp_parse_statement(compiler);
        if (then_branch < 0) {
            return -1;
        }
        if (cmp_check_keyword(compiler, "else")) {
            cmp_take(compiler);
            else_branch = cmp_parse_statement(compiler);
            if (else_branch < 0) {
                return -1;
            }
        }
        node = cmp_node_new(compiler, AST_IF, token->line);
        if (node < 0) {
            return -1;
        }
        compiler->nodes[node].a = condition;
        compiler->nodes[node].b = then_branch;
        compiler->nodes[node].c = else_branch;
        return node;
    }
    if (cmp_check_keyword(compiler, "while")) {
        int node;
        int condition;
        int body;
        cmp_take(compiler);
        if (cmp_expect_op(compiler, "(") != 0) {
            return -1;
        }
        condition = cmp_parse_expression(compiler, 0);
        if (condition < 0) {
            return -1;
        }
        if (cmp_expect_op(compiler, ")") != 0) {
            return -1;
        }
        body = cmp_parse_statement(compiler);
        if (body < 0) {
            return -1;
        }
        node = cmp_node_new(compiler, AST_WHILE, token->line);
        if (node < 0) {
            return -1;
        }
        compiler->nodes[node].a = condition;
        compiler->nodes[node].b = body;
        return node;
    }
    if (cmp_check_keyword(compiler, "return")) {
        int node;
        int value = -1;
        cmp_take(compiler);
        if (!cmp_check_op(compiler, ";")) {
            value = cmp_parse_expression(compiler, 0);
            if (value < 0) {
                return -1;
            }
        }
        if (cmp_expect_op(compiler, ";") != 0) {
            return -1;
        }
        node = cmp_node_new(compiler, AST_RETURN, token->line);
        if (node < 0) {
            return -1;
        }
        compiler->nodes[node].a = value;
        return node;
    }
    if (cmp_check_keyword(compiler, "print")) {
        int node;
        int value;
        cmp_take(compiler);
        value = cmp_parse_expression(compiler, 0);
        if (value < 0) {
            return -1;
        }
        if (cmp_expect_op(compiler, ";") != 0) {
            return -1;
        }
        node = cmp_node_new(compiler, AST_PRINT, token->line);
        if (node < 0) {
            return -1;
        }
        compiler->nodes[node].a = value;
        return node;
    }
    if (cmp_check_op(compiler, "{")) {
        return cmp_parse_block(compiler);
    }
    if (token->kind == TOK_IDENT && compiler->tokens[compiler->position + 1].kind == TOK_OP &&
        strcmp(compiler->tokens[compiler->position + 1].text, "=") == 0) {
        int node;
        char name[NAME_LEN];
        int value;
        cmp_copy(name, NAME_LEN, token->text);
        cmp_take(compiler);
        cmp_take(compiler);
        value = cmp_parse_expression(compiler, 0);
        if (value < 0) {
            return -1;
        }
        if (cmp_expect_op(compiler, ";") != 0) {
            return -1;
        }
        node = cmp_node_new(compiler, AST_ASSIGN, token->line);
        if (node < 0) {
            return -1;
        }
        cmp_copy(compiler->nodes[node].text, NAME_LEN, name);
        compiler->nodes[node].a = value;
        return node;
    }
    {
        char message[TEXT_LEN];
        sprintf(message, "unexpected token '%s' at the start of a statement", token->text);
        cmp_fail(compiler, token->line, message);
    }
    return -1;
}

/* ------------------------------------------------------------------ */
/* symbol table with block scopes                                     */
/* ------------------------------------------------------------------ */

static void env_init(Env *env)
{
    memset(env, 0, sizeof(Env));
    env->scope_depth = 0;
    env->scope_start[0] = 0;
    env->slot_count = 0;
    env->count = 0;
}

static void env_push_scope(Env *env)
{
    if (env->scope_depth + 1 < MAX_SCOPES) {
        env->scope_depth++;
        env->scope_start[env->scope_depth] = env->count;
    }
}

static void env_pop_scope(Env *env)
{
    while (env->count > env->scope_start[env->scope_depth]) {
        env->count--;
    }
    if (env->scope_depth > 0) {
        env->scope_depth--;
    }
}

static int env_declare(Env *env, const char *name)
{
    Symbol *symbol;

    if (env->count >= MAX_SYMS) {
        return -1;
    }
    if (env->slot_count >= MAX_SLOTS) {
        return -1;
    }
    symbol = &env->symbols[env->count];
    cmp_copy(symbol->name, NAME_LEN, name);
    symbol->scope = env->scope_depth;
    symbol->slot = env->slot_count;
    env->slots[env->slot_count] = 0;
    env->slot_count++;
    env->count++;
    return symbol->slot;
}

static int env_lookup(const Env *env, const char *name)
{
    int i;

    for (i = env->count - 1; i >= 0; i--) {
        if (strcmp(env->symbols[i].name, name) == 0) {
            return i;
        }
    }
    return -1;
}

static int env_set(Env *env, const char *name, int value)
{
    int index = env_lookup(env, name);

    if (index < 0) {
        return -1;
    }
    env->slots[env->symbols[index].slot] = value;
    return 0;
}

static void env_print(const Env *env)
{
    int i;

    printf("  symbol table entries = %d slots = %d scopes = %d\n",
           env->count, env->slot_count, env->scope_depth + 1);
    for (i = 0; i < env->count; i++) {
        printf("    %-12s scope=%d slot=%d value=%d\n",
               env->symbols[i].name, env->symbols[i].scope,
               env->symbols[i].slot, env->slots[env->symbols[i].slot]);
    }
}

/* ------------------------------------------------------------------ */
/* interpreter                                                        */
/* ------------------------------------------------------------------ */

static int cmp_eval(Compiler *compiler, int node_index, int *out);
static int cmp_exec(Compiler *compiler, int node_index);

static int cmp_call_function(Compiler *compiler, int func_index, int *args, int arg_count, int *out)
{
    Function *function;
    int i;
    int saved_returning;
    int saved_return_value;

    if (func_index < 0 || func_index >= compiler->function_count) {
        cmp_fail(compiler, 0, "unknown function");
        return -1;
    }
    if (compiler->call_depth >= MAX_CALL_DEPTH) {
        cmp_fail(compiler, 0, "the call stack is too deep");
        return -1;
    }
    function = &compiler->functions[func_index];
    compiler->call_depth++;
    env_push_scope(&compiler->env);
    for (i = 0; i < function->param_count; i++) {
        int slot = env_declare(&compiler->env, function->params[i]);
        if (slot < 0) {
            cmp_fail(compiler, 0, "the symbol table is full");
            compiler->call_depth--;
            env_pop_scope(&compiler->env);
            return -1;
        }
        if (i < arg_count) {
            compiler->env.slots[slot] = args[i];
        }
    }
    saved_returning = compiler->returning;
    saved_return_value = compiler->return_value;
    compiler->returning = 0;
    compiler->return_value = 0;
    cmp_exec(compiler, function->body);
    *out = compiler->return_value;
    compiler->returning = saved_returning;
    compiler->return_value = saved_return_value;
    env_pop_scope(&compiler->env);
    compiler->call_depth--;
    if (compiler->failed) {
        return -1;
    }
    return 0;
}

static int cmp_eval(Compiler *compiler, int node_index, int *out)
{
    const AstNode *node;

    if (node_index < 0 || node_index >= compiler->node_count) {
        return 0;
    }
    compiler->steps++;
    node = &compiler->nodes[node_index];
    switch (node->kind) {
        case AST_INT:
            *out = node->value;
            return 0;
        case AST_IDENT: {
            int index = env_lookup(&compiler->env, node->text);
            if (index < 0) {
                char message[TEXT_LEN];
                sprintf(message, "undeclared variable '%s'", node->text);
                cmp_fail(compiler, node->line, message);
                return -1;
            }
            *out = compiler->env.slots[compiler->env.symbols[index].slot];
            return 0;
        }
        case AST_BINOP: {
            int left = 0;
            int right = 0;
            int result = 0;
            if (cmp_eval(compiler, node->a, &left) != 0) {
                return -1;
            }
            if (cmp_eval(compiler, node->b, &right) != 0) {
                return -1;
            }
            switch (node->op) {
                case OP_ADD:
                    result = left + right;
                    break;
                case OP_SUB:
                    result = left - right;
                    break;
                case OP_MUL:
                    result = left * right;
                    break;
                case OP_DIV:
                    if (right == 0) {
                        cmp_fail(compiler, node->line, "division by zero");
                        return -1;
                    }
                    result = left / right;
                    break;
                case OP_MOD:
                    if (right == 0) {
                        cmp_fail(compiler, node->line, "modulo by zero");
                        return -1;
                    }
                    result = left % right;
                    break;
                case OP_EQ:
                    result = (left == right) ? 1 : 0;
                    break;
                case OP_NE:
                    result = (left != right) ? 1 : 0;
                    break;
                case OP_LT:
                    result = (left < right) ? 1 : 0;
                    break;
                case OP_GT:
                    result = (left > right) ? 1 : 0;
                    break;
                case OP_LE:
                    result = (left <= right) ? 1 : 0;
                    break;
                case OP_GE:
                    result = (left >= right) ? 1 : 0;
                    break;
                case OP_AND:
                    result = ((left != 0) && (right != 0)) ? 1 : 0;
                    break;
                case OP_OR:
                    result = ((left != 0) || (right != 0)) ? 1 : 0;
                    break;
                default:
                    cmp_fail(compiler, node->line, "unknown binary operator");
                    return -1;
            }
            *out = result;
            return 0;
        }
        case AST_UNOP: {
            int value = 0;
            if (cmp_eval(compiler, node->a, &value) != 0) {
                return -1;
            }
            if (node->op == OP_NOT) {
                *out = (value == 0) ? 1 : 0;
            } else {
                *out = -value;
            }
            return 0;
        }
        case AST_CALL: {
            int args[8];
            int arg_count = 0;
            int argument = node->a;
            int result = 0;
            while (argument >= 0 && arg_count < 8) {
                if (cmp_eval(compiler, argument, &args[arg_count]) != 0) {
                    return -1;
                }
                arg_count++;
                argument = compiler->nodes[argument].next;
            }
            if (cmp_call_function(compiler, node->value, args, arg_count, &result) != 0) {
                return -1;
            }
            *out = result;
            return 0;
        }
        default:
            break;
    }
    *out = 0;
    return 0;
}

static int cmp_exec(Compiler *compiler, int node_index)
{
    const AstNode *node;

    if (node_index < 0 || node_index >= compiler->node_count) {
        return 0;
    }
    if (compiler->returning) {
        return 0;
    }
    compiler->steps++;
    node = &compiler->nodes[node_index];
    switch (node->kind) {
        case AST_FUNC:
            return 0;
        case AST_BLOCK: {
            int statement = node->a;
            env_push_scope(&compiler->env);
            while (statement >= 0) {
                if (cmp_exec(compiler, statement) != 0) {
                    env_pop_scope(&compiler->env);
                    return -1;
                }
                if (compiler->returning) {
                    break;
                }
                statement = compiler->nodes[statement].next;
            }
            env_pop_scope(&compiler->env);
            return 0;
        }
        case AST_VAR: {
            int value = 0;
            int slot;
            if (node->a >= 0) {
                if (cmp_eval(compiler, node->a, &value) != 0) {
                    return -1;
                }
            }
            slot = env_declare(&compiler->env, node->text);
            if (slot < 0) {
                cmp_fail(compiler, node->line, "the symbol table is full");
                return -1;
            }
            compiler->env.slots[slot] = value;
            return 0;
        }
        case AST_ASSIGN: {
            int value = 0;
            if (cmp_eval(compiler, node->a, &value) != 0) {
                return -1;
            }
            if (env_set(&compiler->env, node->text, value) != 0) {
                char message[TEXT_LEN];
                sprintf(message, "undeclared variable '%s'", node->text);
                cmp_fail(compiler, node->line, message);
                return -1;
            }
            return 0;
        }
        case AST_IF: {
            int condition = 0;
            if (cmp_eval(compiler, node->a, &condition) != 0) {
                return -1;
            }
            if (condition != 0) {
                return cmp_exec(compiler, node->b);
            }
            if (node->c >= 0) {
                return cmp_exec(compiler, node->c);
            }
            return 0;
        }
        case AST_WHILE: {
            for (;;) {
                int condition = 0;
                if (cmp_eval(compiler, node->a, &condition) != 0) {
                    return -1;
                }
                if (condition == 0) {
                    break;
                }
                if (cmp_exec(compiler, node->b) != 0) {
                    return -1;
                }
                if (compiler->returning) {
                    break;
                }
            }
            return 0;
        }
        case AST_RETURN: {
            int value = 0;
            if (node->a >= 0) {
                if (cmp_eval(compiler, node->a, &value) != 0) {
                    return -1;
                }
            }
            compiler->return_value = value;
            compiler->returning = 1;
            return 0;
        }
        case AST_PRINT: {
            int argument = node->a;
            if (argument >= 0 && compiler->nodes[argument].kind == AST_STR) {
                printf("  program: %s\n", compiler->nodes[argument].text);
                compiler->output_lines++;
                return 0;
            }
            {
                int value = 0;
                if (cmp_eval(compiler, argument, &value) != 0) {
                    return -1;
                }
                printf("  program: %d\n", value);
                compiler->output_lines++;
            }
            return 0;
        }
        default:
            return 0;
    }
}

/* ------------------------------------------------------------------ */
/* driver                                                             */
/* ------------------------------------------------------------------ */

static int cmp_parse_program(Compiler *compiler)
{
    int first = -1;
    int last = -1;

    while (cmp_peek(compiler)->kind != TOK_EOF) {
        int statement = cmp_parse_statement(compiler);
        if (statement < 0) {
            return -1;
        }
        if (first < 0) {
            first = statement;
        } else {
            compiler->nodes[last].next = statement;
        }
        last = statement;
    }
    return first;
}

static int cmp_find_function(const Compiler *compiler, const char *name)
{
    int i;

    for (i = 0; i < compiler->function_count; i++) {
        if (strcmp(compiler->functions[i].name, name) == 0) {
            return i;
        }
    }
    return -1;
}

static void cmp_print_tree(const Compiler *compiler)
{
    int i;

    printf("  ast nodes = %d functions = %d\n", compiler->node_count, compiler->function_count);
    for (i = 0; i < compiler->function_count; i++) {
        printf("    function %-10s params=%d body=%d\n",
               compiler->functions[i].name, compiler->functions[i].param_count,
               compiler->functions[i].body);
    }
}

static int cmp_compile_and_run(const char *source, int verbose)
{
    Compiler *compiler;
    int program;
    int main_function;
    int result = 0;
    int rc = 0;

    compiler = (Compiler *)malloc(sizeof(Compiler));
    if (compiler == NULL) {
        printf("  out of memory\n");
        return -1;
    }
    memset(compiler, 0, sizeof(Compiler));
    env_init(&compiler->env);
    if (cmp_lex(compiler, source) != 0) {
        printf("  lexer error: %s\n", compiler->error);
        free(compiler);
        return -1;
    }
    if (verbose) {
        cmp_print_tokens(compiler);
    }
    program = cmp_parse_program(compiler);
    if (program < 0) {
        printf("  parser error: %s\n", compiler->error);
        free(compiler);
        return -1;
    }
    if (verbose) {
        cmp_print_tree(compiler);
    }
    main_function = cmp_find_function(compiler, "main");
    if (main_function < 0) {
        printf("  error: the program has no main function\n");
        free(compiler);
        return -1;
    }
    compiler->returning = 0;
    compiler->return_value = 0;
    if (cmp_call_function(compiler, main_function, NULL, 0, &result) != 0) {
        printf("  runtime error: %s\n", compiler->error);
        rc = -1;
    }
    if (verbose) {
        printf("  execution steps = %d printed lines = %d main returned %d\n",
               compiler->steps, compiler->output_lines, result);
        env_print(&compiler->env);
    }
    free(compiler);
    return rc;
}

static const char *const PROGRAM_SOURCE =
    "int fact(int n) {\n"
    "    if (n <= 1) { return 1; }\n"
    "    return n * fact(n - 1);\n"
    "}\n"
    "\n"
    "int fib(int n) {\n"
    "    if (n < 2) { return n; }\n"
    "    return fib(n - 1) + fib(n - 2);\n"
    "}\n"
    "\n"
    "int classify(int value) {\n"
    "    if (value < 0) { return -1; }\n"
    "    if (value == 0) { return 0; }\n"
    "    if (value < 10) { return 1; }\n"
    "    return 2;\n"
    "}\n"
    "\n"
    "int main() {\n"
    "    int i = 0;\n"
    "    int total = 0;\n"
    "    while (i < 5) {\n"
    "        if (i == 3) {\n"
    "            print \"skipping three\\n\";\n"
    "        } else {\n"
    "            total = total + i;\n"
    "        }\n"
    "        i = i + 1;\n"
    "    }\n"
    "    print \"total = \";\n"
    "    print total;\n"
    "    print \"\\n\";\n"
    "    print \"fact(5) = \";\n"
    "    print fact(5);\n"
    "    print \"\\n\";\n"
    "    print \"fib(10) = \";\n"
    "    print fib(10);\n"
    "    print \"\\n\";\n"
    "    print \"classify(-2) = \";\n"
    "    print classify(-2);\n"
    "    print \"\\n\";\n"
    "    return 0;\n"
    "}\n";

static const char *const BROKEN_SEMICOLON =
    "int main() {\n"
    "    int x = 5\n"
    "    int y = 6;\n"
    "    return x;\n"
    "}\n";

static const char *const BROKEN_PAREN =
    "int main() {\n"
    "    int x = (1 + 2;\n"
    "    return x;\n"
    "}\n";

static const char *const BROKEN_UNDECLARED =
    "int main() {\n"
    "    return unknownVariable;\n"
    "}\n";

/* ------------------------------------------------------------------ */
/* main                                                               */
/* ------------------------------------------------------------------ */

int main(void)
{
    printf("=== compile and run the fixed program ===\n");
    cmp_compile_and_run(PROGRAM_SOURCE, 1);

    printf("=== error handling ===\n");
    printf("  broken source 1: a missing semicolon\n");
    cmp_compile_and_run(BROKEN_SEMICOLON, 0);
    printf("  broken source 2: a parenthesis that does not match\n");
    cmp_compile_and_run(BROKEN_PAREN, 0);
    printf("  broken source 3: a variable that was never declared\n");
    cmp_compile_and_run(BROKEN_UNDECLARED, 0);
    printf("=== done ===\n");
    return 0;
}
