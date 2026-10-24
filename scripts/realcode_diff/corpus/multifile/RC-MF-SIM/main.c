#include <stdio.h>
#include "world.h"

int main(void)
{
    World world;
    Entity entity;
    int i;
    int rc;

    world_init(&world);
    world_add(&world, 1, 0.0, 0.0, 0.10, 0.00);
    world_add(&world, 2, 1.0, 0.0, 0.05, 0.05);
    world_add(&world, 3, 5.0, 5.0, -0.10, 0.00);
    world_add(&world, 4, 9.0, 1.0, 0.00, 0.20);
    world_add(&world, 5, 2.0, 8.0, 0.15, -0.15);

    printf("=== 20 steps ===\n");
    for (i = 1; i <= 20; i++) {
        world_step(&world);
        if (i % 5 == 0) {
            printf("step %d:\n", i);
            world_print(&world);
        }
    }

    printf("=== query ===\n");
    rc = world_query(&world, 3, &entity);
    printf("query id=3 rc=%d pos=(%.4f, %.4f) state=%d\n", rc, entity.x, entity.y, (int)entity.state);
    rc = world_query(&world, 99, &entity);
    printf("query id=99 rc=%d\n", rc);

    printf("=== final state ===\n");
    world_print(&world);
    printf("entities=%d collisions=%d steps=%d total_steps=%d\n",
           world_entity_count(&world), world_collisions(&world), world.step, world_total_steps);
    return 0;
}
