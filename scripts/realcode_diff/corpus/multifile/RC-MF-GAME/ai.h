#ifndef AI_H
#define AI_H

#include "game.h"

/* number of minimax nodes visited; defined in ai.c */
extern int ai_nodes_visited;

/* best column for the given player, or -1 when the board is full */
int ai_best_move(const Game *game, Cell player);

#endif /* AI_H */
