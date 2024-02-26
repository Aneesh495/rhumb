#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include "../include/rhumb.h"

int main(void) {
    printf("========================================================\n");
    printf("RHUMB C ABI ROUTING DEMONSTRATION\n");
    printf("Engine Version: %s\n", rhumb_version());
    printf("========================================================\n\n");

    // 1. Geodesic distance calculation test
    double sf_lat = 37.7749;
    double sf_lon = -122.4194;
    double oak_lat = 37.8044;
    double oak_lon = -122.2712;

    double dist_hav = rhumb_distance_haversine(sf_lat, sf_lon, oak_lat, oak_lon);
    double dist_vinc = rhumb_distance_vincenty(sf_lat, sf_lon, oak_lat, oak_lon);

    printf("[1] Geodesic Distance Check (SF to Oakland):\n");
    printf("    Haversine: %.2f meters\n", dist_hav);
    printf("    Vincenty:  %.2f meters\n", dist_vinc);
    printf("    Delta:     %.2f meters\n\n", dist_hav - dist_vinc);

    assert(dist_hav > 13000.0 && dist_hav < 14500.0);

    // 2. Graph construction
    printf("[2] Constructing In-Memory Road Graph...\n");
    rhumb_graph_t* g = rhumb_create_graph();
    assert(g != NULL);

    // 4 Nodes forming a diamond street network
    uint32_t n0 = rhumb_add_node(g, 1001, 37.7740, -122.4200, 10.0);
    uint32_t n1 = rhumb_add_node(g, 1002, 37.7780, -122.4200, 12.0);
    uint32_t n2 = rhumb_add_node(g, 1003, 37.7740, -122.4140, 11.0);
    uint32_t n3 = rhumb_add_node(g, 1004, 37.7780, -122.4140, 14.0);

    // Edges
    rhumb_add_edge(g, n0, n1, 450.0, 50.0f, "Van Ness Ave");
    rhumb_add_edge(g, n1, n0, 450.0, 50.0f, "Van Ness Ave");

    rhumb_add_edge(g, n0, n2, 520.0, 40.0f, "Market St");
    rhumb_add_edge(g, n2, n0, 520.0, 40.0f, "Market St");

    rhumb_add_edge(g, n1, n3, 520.0, 40.0f, "Mission St");
    rhumb_add_edge(g, n3, n1, 520.0, 40.0f, "Mission St");

    rhumb_add_edge(g, n2, n3, 450.0, 50.0f, "South Van Ness");
    rhumb_add_edge(g, n3, n2, 450.0, 50.0f, "South Van Ness");

    bool finalized = rhumb_finalize_graph(g);
    assert(finalized);
    printf("    Network finalized into forward-star CSR format.\n\n");

    // 3. Shortest Path Search (Dijkstra)
    printf("[3] Querying Dijkstra Path from (37.7740, -122.4200) to (37.7780, -122.4140)...\n");
    rhumb_route_result_t* res_dijkstra = rhumb_route_dijkstra(g, 37.7740, -122.4200, 37.7780, -122.4140);
    assert(res_dijkstra != NULL);
    assert(res_dijkstra->found);

    printf("    Route Status:      FOUND\n");
    printf("    Total Distance:    %.1f meters\n", res_dijkstra->total_distance_m);
    printf("    Estimated Time:    %.2f seconds\n", (double)res_dijkstra->total_duration_ms / 1000.0);
    printf("    Nodes Traversed:   %zu (", res_dijkstra->node_count);
    for (size_t i = 0; i < res_dijkstra->node_count; i++) {
        printf("%u%s", res_dijkstra->node_path[i], (i + 1 < res_dijkstra->node_count) ? " -> " : "");
    }
    printf(")\n\n");

    // 4. Shortest Path Search (A*)
    printf("[4] Querying A* Path (Heuristic Guided)...\n");
    rhumb_route_result_t* res_astar = rhumb_route_astar(g, 37.7740, -122.4200, 37.7780, -122.4140);
    assert(res_astar != NULL);
    assert(res_astar->found);
    printf("    Route Status:      FOUND\n");
    printf("    Total Distance:    %.1f meters\n", res_astar->total_distance_m);
    printf("    A* matches Dijkstra distance: %s\n\n",
           (res_astar->total_distance_m == res_dijkstra->total_distance_m) ? "YES" : "NO");

    // Cleanup
    rhumb_free_route_result(res_dijkstra);
    rhumb_free_route_result(res_astar);
    rhumb_free_graph(g);

    printf("Memory freed successfully. All C ABI assertions passed.\n");
    printf("========================================================\n");
    return 0;
}
