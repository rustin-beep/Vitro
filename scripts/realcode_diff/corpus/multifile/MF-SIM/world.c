#include "world.h"
#include <math.h>
#include <stdio.h>
#include <string.h>

int world_total_steps = 0;

void world_init(World *world)
{
    if (world == NULL) {
        return;
    }
    memset(world, 0, sizeof(World));
    world->count = 0;
    world->step = 0;
    world->collision_count = 0;
}

int world_add(World *world, int id, double x, double y, double vx, double vy)
{
    Entity *entity;

    if (world == NULL) {
        return -1;
    }
    if (world->count >= WORLD_MAX_ENTITIES) {
        return -2;
    }
    entity = &world->entities[world->count];
    entity->id = id;
    entity->x = x;
    entity->y = y;
    entity->vx = vx;
    entity->vy = vy;
    entity->state = ENTITY_ACTIVE;
    entity->collide_with = -1;
    world->count++;
    return 0;
}

void world_step(World *world)
{
    int i;
    int j;

    if (world == NULL) {
        return;
    }
    for (i = 0; i < world->count; i++) {
        Entity *entity = &world->entities[i];
        if (entity->state == ENTITY_INACTIVE) {
            continue;
        }
        entity->x += entity->vx;
        entity->y += entity->vy;
    }
    for (i = 0; i < world->count; i++) {
        for (j = i + 1; j < world->count; j++) {
            Entity *a = &world->entities[i];
            Entity *b = &world->entities[j];
            double dx;
            double dy;
            if (a->state == ENTITY_INACTIVE || b->state == ENTITY_INACTIVE) {
                continue;
            }
            dx = a->x - b->x;
            dy = a->y - b->y;
            if (sqrt(dx * dx + dy * dy) < WORLD_COLLIDE_DIST) {
                a->state = ENTITY_COLLIDED;
                b->state = ENTITY_COLLIDED;
                a->collide_with = b->id;
                b->collide_with = a->id;
                world->collision_count++;
            }
        }
    }
    world->step++;
    world_total_steps++;
}

int world_query(const World *world, int id, Entity *out)
{
    int i;

    if (world == NULL || out == NULL) {
        return -1;
    }
    for (i = 0; i < world->count; i++) {
        if (world->entities[i].id == id) {
            *out = world->entities[i];
            return 0;
        }
    }
    return -1;
}

int world_collisions(const World *world)
{
    if (world == NULL) {
        return -1;
    }
    return world->collision_count;
}

int world_entity_count(const World *world)
{
    if (world == NULL) {
        return -1;
    }
    return world->count;
}

void world_print(const World *world)
{
    int i;

    if (world == NULL) {
        return;
    }
    printf("  step=%d collisions=%d\n", world->step, world->collision_count);
    for (i = 0; i < world->count; i++) {
        const Entity *entity = &world->entities[i];
        printf("    id=%d pos=(%8.4f, %8.4f) vel=(%6.3f, %6.3f) state=%d other=%d\n",
               entity->id, entity->x, entity->y, entity->vx, entity->vy,
               (int)entity->state, entity->collide_with);
    }
}
