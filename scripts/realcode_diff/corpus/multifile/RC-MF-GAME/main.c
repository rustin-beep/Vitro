#include <stdio.h>
#include "game.h"
#include "ai.h"

int main(void)
{
    Game game;
    int human_moves[6];
    int move_count;
    int i;
    int rc;
    int pos;

    human_moves[0] = 0;
    human_moves[1] = 4;
    human_moves[2] = 8;
    human_moves[3] = 2;
    human_moves[4] = 6;
    human_moves[5] = 1;
    move_count = 6;

    game_init(&game);
    ai_nodes_visited = 0;

    printf("=== initial board ===\n");
    game_print(&game);

    for (i = 0; i < move_count; i++) {
        if (game_is_over(&game)) {
            break;
        }
        pos = human_moves[i];
        rc = game_apply(&game, pos, CELL_X);
        printf("=== move %d: human X at %d rc=%d ===\n", i + 1, pos, rc);
        game_print(&game);
        if (game_is_over(&game)) {
            break;
        }
        rc = game_apply_ai(&game, CELL_O);
        printf("=== move %d: AI O at %d rc=%d ===\n", i + 1, rc, rc);
        game_print(&game);
    }

    printf("=== final ===\n");
    game_print(&game);
    if (game_winner(&game) == CELL_X) {
        printf("result = human wins\n");
    } else if (game_winner(&game) == CELL_O) {
        printf("result = AI wins\n");
    } else {
        printf("result = draw\n");
    }
    printf("moves=%d ai_calls=%d minimax_nodes=%d\n",
           game_move_count(&game), game_ai_calls, ai_nodes_visited);
    return 0;
}
