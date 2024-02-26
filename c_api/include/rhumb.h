#ifndef RHUMB_H
#define RHUMB_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque handles
typedef struct rhumb_graph rhumb_graph_t;
typedef struct rhumb_route_result rhumb_route_result_t;

// Coordinate representation
typedef struct {
    double lat;
    double lon;
} rhumb_coord_t;

// Bounding box representation
typedef struct {
    double min_lat;
    double min_lon;
    double max_lat;
    double max_lon;
} rhumb_bbox_t;

// Turn maneuver type
typedef enum {
    RHUMB_MANEUVER_DEPART = 0,
    RHUMB_MANEUVER_CONTINUE = 1,
    RHUMB_MANEUVER_TURN_SLIGHT_RIGHT = 2,
    RHUMB_MANEUVER_TURN_RIGHT = 3,
    RHUMB_MANEUVER_TURN_SHARP_RIGHT = 4,
    RHUMB_MANEUVER_UTURN = 5,
    RHUMB_MANEUVER_TURN_SHARP_LEFT = 6,
    RHUMB_MANEUVER_TURN_LEFT = 7,
    RHUMB_MANEUVER_TURN_SLIGHT_LEFT = 8,
    RHUMB_MANEUVER_ARRIVE = 9
} rhumb_maneuver_t;

// Route step instruction
typedef struct {
    rhumb_maneuver_t maneuver;
    double distance_m;
    uint32_t duration_ms;
    const char* street_name;
    const char* instruction;
} rhumb_step_t;

// Route result summary
struct rhumb_route_result {
    bool found;
    double total_distance_m;
    uint32_t total_duration_ms;
    size_t node_count;
    uint32_t* node_path;
    size_t edge_count;
    uint32_t* edge_path;
    size_t geometry_count;
    rhumb_coord_t* geometry;
};

// Engine Lifecycle
rhumb_graph_t* rhumb_create_graph(void);
void rhumb_free_graph(rhumb_graph_t* graph);

// Graph Construction
uint32_t rhumb_add_node(rhumb_graph_t* graph, int64_t osm_id, double lat, double lon, double elevation_m);
uint32_t rhumb_add_edge(rhumb_graph_t* graph, uint32_t u, uint32_t v, double length_m, float speed_kph, const char* name);
bool rhumb_finalize_graph(rhumb_graph_t* graph);

// Routing Algorithms
rhumb_route_result_t* rhumb_route_dijkstra(const rhumb_graph_t* graph, double from_lat, double from_lon, double to_lat, double to_lon);
rhumb_route_result_t* rhumb_route_astar(const rhumb_graph_t* graph, double from_lat, double from_lon, double to_lat, double to_lon);
void rhumb_free_route_result(rhumb_route_result_t* result);

// Geodesic Utilities
double rhumb_distance_haversine(double lat1, double lon1, double lat2, double lon2);
double rhumb_distance_vincenty(double lat1, double lon1, double lat2, double lon2);

// Metadata
const char* rhumb_version(void);

#ifdef __cplusplus
}
#endif

#endif // RHUMB_H
