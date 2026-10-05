#include <stdio.h>
#include <ctype.h>
#include <string.h>
#include <stdlib.h>
#define EOF -1
#define MAXWORD 100
struct linklist {
    int lnum;
    struct linklist *ptr;
};
struct tnode {
    char *word;
    struct linklist *lines;
    struct tnode *left;
    struct tnode *right;
};
struct tnode *addtreex(struct tnode *, char *, int);
void treexprint(struct tnode *);
int getword(char *, int);
int lineno = 1;
int main() {
    struct tnode *root;
    char word[MAXWORD];
    root = NULL;
    while (getword(word, MAXWORD) != EOF)
        if (isalpha(word[0]))
            root = addtreex(root, word, lineno);
    treexprint(root);
    return 0;
}
struct tnode *talloc(void) {
    return (struct tnode *)malloc(sizeof(struct tnode));
}
struct linklist *lalloc(void) {
    return (struct linklist *)malloc(sizeof(struct linklist));
}
void addln(struct tnode *p, int linenum) {
    struct linklist *temp;
    temp = p->lines;
    while (temp->ptr != NULL && temp->lnum != linenum)
        temp = temp->ptr;
    if (temp->lnum != linenum) {
        temp->ptr = lalloc();
        temp->ptr->lnum = linenum;
        temp->ptr->ptr = NULL;
    }
}
struct tnode *addtreex(struct tnode *p, char *w, int linenum) {
    int cond;
    if (p == NULL) {
        p = talloc();
        p->word = strdup(w);
        p->lines = lalloc();
        p->lines->lnum = linenum;
        p->lines->ptr = NULL;
        p->left = p->right = NULL;
    } else if ((cond = strcmp(w, p->word)) == 0)
        addln(p, linenum);
    else if (cond < 0)
        p->left = addtreex(p->left, w, linenum);
    else
        p->right = addtreex(p->right, w, linenum);
    return p;
}
void treexprint(struct tnode *p) {
    struct linklist *temp;
    if (p != NULL) {
        treexprint(p->left);
        printf("%s: ", p->word);
        for (temp = p->lines; temp != NULL; temp = temp->ptr)
            printf("%d ", temp->lnum);
        printf("\n");
        treexprint(p->right);
    }
}
int getword(char *word, int lim) {
    int c;
    char *w = word;
    while (isspace(c = getchar()))
        ;
    if (c == '\n')
        lineno++;
    if (c != EOF)
        *w++ = c;
    if (!isalpha(c)) {
        *w = '\0';
        return c;
    }
    for (; --lim > 0; w++)
        if (!isalnum(*w = getchar())) {
            ungetc(*w, stdin);
            break;
        }
    *w = '\0';
    return word[0];
}
