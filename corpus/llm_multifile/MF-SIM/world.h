#ifndef WORLD_H
#define WORLD_H

#define WORLD_MAX_ENTITIES 16
#define WORLD_COLLIDE_DIST 1.0

typedef enum {
    ENTITY_ACTIVE = 0,
    ENTITY_COLLIDED = 1,
    ENTITY_INACTIVE = 2
} EntityState;

typedef struct {
    int id;
    double x;
    double y;
    double vx;
    double vy;
    EntityState state;
    int collide_with;
} Entity;

typedef struct {
    Entity entities[WORLD_MAX_ENTITIES];
    int count;
    int step;
    int collision_count;
} World;

/* total number of simulated steps across the whole program; defined in world.c */
extern int world_total_steps;

void world_init(World *world);
int world_add(World *world, int id, double x, double y, double vx, double vy);
void world_step(World *world);
int world_query(const World *world, int id, Entity *out);
int world_collisions(const World *world);
int world_entity_count(const World *world);
void world_print(const World *world);

#endif /* WORLD_H */
