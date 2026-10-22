#include "game.h"
#include "ai.h"
#include <stdio.h>
#include <string.h>

int game_ai_calls = 0;

void game_init(Game *game)
{
    int i;

    if (game == NULL) {
        return;
    }
    for (i = 0; i < GAME_CELLS; i++) {
        game->cells[i] = CELL_EMPTY;
    }
    game->moves = 0;
    game->winner = CELL_EMPTY;
}

int game_winner(const Game *game)
{
    int line[3];
    int i;

    if (game == NULL) {
        return CELL_EMPTY;
    }
    for (i = 0; i < GAME_SIZE; i++) {
        line[0] = game->cells[i * GAME_SIZE + 0];
        line[1] = game->cells[i * GAME_SIZE + 1];
        line[2] = game->cells[i * GAME_SIZE + 2];
        if (line[0] != CELL_EMPTY && line[0] == line[1] && line[1] == line[2]) {
            return line[0];
        }
    }
    for (i = 0; i < GAME_SIZE; i++) {
        line[0] = game->cells[0 * GAME_SIZE + i];
        line[1] = game->cells[1 * GAME_SIZE + i];
        line[2] = game->cells[2 * GAME_SIZE + i];
        if (line[0] != CELL_EMPTY && line[0] == line[1] && line[1] == line[2]) {
            return line[0];
        }
    }
    line[0] = game->cells[0];
    line[1] = game->cells[4];
    line[2] = game->cells[8];
    if (line[0] != CELL_EMPTY && line[0] == line[1] && line[1] == line[2]) {
        return line[0];
    }
    line[0] = game->cells[2];
    line[1] = game->cells[4];
    line[2] = game->cells[6];
    if (line[0] != CELL_EMPTY && line[0] == line[1] && line[1] == line[2]) {
        return line[0];
    }
    return CELL_EMPTY;
}

int game_is_over(const Game *game)
{
    if (game == NULL) {
        return 1;
    }
    if (game_winner(game) != CELL_EMPTY) {
        return 1;
    }
    return game->moves >= GAME_CELLS ? 1 : 0;
}

int game_apply(Game *game, int pos, Cell player)
{
    if (game == NULL) {
        return -1;
    }
    if (pos < 0 || pos >= GAME_CELLS) {
        return -2;
    }
    if (player != CELL_X && player != CELL_O) {
        return -3;
    }
    if (game_is_over(game)) {
        return -4;
    }
    if (game->cells[pos] != CELL_EMPTY) {
        return -5;
    }
    game->cells[pos] = player;
    game->moves++;
    game->winner = game_winner(game);
    return 0;
}

int game_apply_ai(Game *game, Cell player)
{
    int pos;
    int rc;

    if (game == NULL) {
        return -1;
    }
    if (game_is_over(game)) {
        return -4;
    }
    pos = ai_best_move(game, player);
    if (pos < 0) {
        return -6;
    }
    game_ai_calls++;
    rc = game_apply(game, pos, player);
    if (rc != 0) {
        return rc;
    }
    return pos;
}

int game_move_count(const Game *game)
{
    if (game == NULL) {
        return -1;
    }
    return game->moves;
}

void game_print(const Game *game)
{
    int r;
    int c;

    if (game == NULL) {
        return;
    }
    printf("  +---+---+---+\n");
    for (r = 0; r < GAME_SIZE; r++) {
        printf("  |");
        for (c = 0; c < GAME_SIZE; c++) {
            Cell cell = game->cells[r * GAME_SIZE + c];
            char mark = '.';
            if (cell == CELL_X) {
                mark = 'X';
            } else if (cell == CELL_O) {
                mark = 'O';
            }
            printf(" %c |", mark);
        }
        printf("\n  +---+---+---+\n");
    }
    printf("  moves=%d winner=%d\n", game->moves, game->winner);
}
