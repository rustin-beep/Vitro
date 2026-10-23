#ifndef GAME_H
#define GAME_H

#define GAME_SIZE  3
#define GAME_CELLS 9

typedef enum {
    CELL_EMPTY = 0,
    CELL_X = 1,
    CELL_O = 2
} Cell;

typedef struct {
    Cell cells[GAME_CELLS];
    int moves;
    int winner;
} Game;

/* number of AI decisions taken so far; defined in game.c */
extern int game_ai_calls;

void game_init(Game *game);
int game_apply(Game *game, int pos, Cell player);
int game_is_over(const Game *game);
int game_winner(const Game *game);
void game_print(const Game *game);
int game_apply_ai(Game *game, Cell player);
int game_move_count(const Game *game);

#endif /* GAME_H */
