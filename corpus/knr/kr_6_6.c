#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#define HASHSIZE 101
struct nlist {
    struct nlist *next;
    char *name;
    char *defn;
};
static struct nlist *hashtab[HASHSIZE];
unsigned hash(char *s) {
    unsigned hashval;
    for (hashval = 0; *s != '\0'; s++)
        hashval = *s + 31 * hashval;
    return hashval % HASHSIZE;
}
struct nlist *lookup(char *s) {
    struct nlist *np;
    for (np = hashtab[hash(s)]; np != NULL; np = np->next)
        if (strcmp(s, np->name) == 0)
            return np;
    return NULL;
}
struct nlist *install(char *name, char *defn) {
    struct nlist *np;
    unsigned hashval;
    if ((np = lookup(name)) == NULL) {
        np = (struct nlist *) malloc(sizeof(*np));
        if (np == NULL || (np->name = strdup(name)) == NULL)
            return NULL;
        hashval = hash(name);
        np->next = hashtab[hashval];
        hashtab[hashval] = np;
    } else
        free((void *) np->defn);
    if ((np->defn = strdup(defn)) == NULL)
        return NULL;
    return np;
}
void undef(char *name) {
    struct nlist *np, *prev;
    unsigned hashval = hash(name);
    for (prev = NULL, np = hashtab[hashval]; np != NULL; prev = np, np = np->next)
        if (strcmp(name, np->name) == 0)
            break;
    if (np != NULL) {
        if (prev == NULL)
            hashtab[hashval] = np->next;
        else
            prev->next = np->next;
        free((void *) np->name);
        free((void *) np->defn);
        free((void *) np);
    }
}
int main() {
    install("MAX", "100");
    install("MIN", "0");
    undef("MAX");
    struct nlist *np = lookup("MAX");
    if (np == NULL)
        printf("MAX undefined\n");
    np = lookup("MIN");
    if (np != NULL)
        printf("%s = %s\n", np->name, np->defn);
    return 0;
}
