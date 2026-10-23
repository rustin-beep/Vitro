#include "ai.h"
#include <stddef.h>

int ai_nodes_visited = 0;

static Cell ai_other(Cell player)
{
    return (player == CELL_X) ? CELL_O : CELL_X;
}

static int ai_minimax(const Game *game, Cell player, int depth)
{
    Cell opponent = ai_other(player);
    int best = -1000;
    int i;

    ai_nodes_visited++;
    if (game_winner(game) == player) {
        return 10 - depth;
    }
    if (game_winner(game) == opponent) {
        return depth - 10;
    }
    if (game->moves >= GAME_CELLS) {
        return 0;
    }
    for (i = 0; i < GAME_CELLS; i++) {
        Game copy;
        int value;
        if (game->cells[i] != CELL_EMPTY) {
            continue;
        }
        copy = *game;
        copy.cells[i] = player;
        copy.moves = game->moves + 1;
        value = ai_minimax(&copy, opponent, depth + 1);
        if (value > best) {
            best = value;
        }
    }
    return best;
}

int ai_best_move(const Game *game, Cell player)
{
    int best_score = -1000;
    int best_move = -1;
    int i;

    if (game == NULL) {
        return -1;
    }
    for (i = 0; i < GAME_CELLS; i++) {
        Game copy;
        int value;
        if (game->cells[i] != CELL_EMPTY) {
            continue;
        }
        copy = *game;
        copy.cells[i] = player;
        copy.moves = game->moves + 1;
        value = -ai_minimax(&copy, ai_other(player), 0);
        if (value > best_score) {
            best_score = value;
            best_move = i;
        }
    }
    return best_move;
}
