# Hidden Markov Model (HMM) Map-Matching

Map-matching is the process of aligning a noisy, discretely sampled sequence of GPS coordinates onto a digital road network graph. Sensor multipath errors, urban canyon effects, and GPS jitter frequently place recorded coordinates dozens of meters away from the true road centerlines.

Rhumb implements the probabilistic Hidden Markov Model framework introduced by Paul Newson and John Krumm (ACM SIGSPATIAL 2009), optimized for high-throughput Viterbi trellis decoding.

---

## 1. Probabilistic Formulation

Given a sequence of `T` raw GPS observations `Z = (z_1, z_2, ..., z_T)` and a road network graph `G = (V, E)`, the goal is to determine the most probable sequence of road network states `S = (s_1, s_2, ..., s_T)` that generated the observations.

Each state `s_t` represents a specific projection onto a road segment `e in E`.

```
          z_1 (GPS Fix)          z_2 (GPS Fix)          z_3 (GPS Fix)
            o                      o                      o
            | (Emission)           | (Emission)           | (Emission)
            v                      v                      v
        [State s_1,1] --------> [State s_2,1] --------> [State s_3,1]
        [State s_1,2]    (Trans) [State s_2,2]    (Trans) [State s_3,2]
        [State s_1,3] --------> [State s_2,3] --------> [State s_3,3]
             t=1                    t=2                    t=3
```

By Bayes' theorem and the Markov property:
`P(S | Z) proportional to P(s_1) * p(z_1 | s_1) * Product_{t=2}^T [ p(z_t | s_t) * p(s_t | s_{t-1}) ]`

To avoid floating-point underflow, Rhumb operates strictly in log-likelihood space:
`L(S | Z) = ln p(z_1 | s_1) + Sum_{t=2}^T [ ln p(z_t | s_t) + ln p(s_t | s_{t-1}) ]`

---

## 2. Emission Probability Distribution

The emission probability `p(z_t | s_t)` models measurement error: the likelihood that a vehicle at network position `s_t` produces a recorded GPS fix `z_t`.

Rhumb models measurement error as a zero-mean Gaussian distribution with standard deviation `sigma_z` (typically 4.07 meters):
`p(z_t | s_t) = (1 / (sqrt(2 * pi) * sigma_z)) * exp(-0.5 * (||z_t - s_t|| / sigma_z)^2)`

In log-space:
`ln p(z_t | s_t) = -ln(sqrt(2 * pi) * sigma_z) - 0.5 * (d_m / sigma_z)^2`

Where `d_m = ||z_t - s_t||` is the orthogonal Haversine distance between the raw GPS fix `z_t` and its projection onto the road segment `s_t`. Projections with distances exceeding the spatial search radius (e.g. 50 meters) are pruned.

---

## 3. Transition Probability Distribution

The transition probability `p(s_t | s_{t-1})` models network connectivity: the likelihood that a vehicle moves from road state `s_{t-1}` to road state `s_t` during the elapsed sampling interval `Delta t`.

Newson and Krumm observe that on a road network, the actual road distance between two consecutive observations should closely match the straight-line Great-Circle distance between the raw GPS fixes:
- `d_euclid = Haversine(z_{t-1}, z_t)`
- `d_route = ShortestPath(s_{t-1}, s_t)`

The discrepancy `Delta d = |d_route - d_euclid|` is modeled using an exponential distribution with parameter `beta` (typically 3.0 meters):
`p(s_t | s_{t-1}) = (1 / beta) * exp(-|d_route - d_euclid| / beta)`

In log-space:
`ln p(s_t | s_{t-1}) = -ln(beta) - (|d_route - d_euclid| / beta)`

### Transition Penalties
- If two candidates lie on the same directed edge, `d_route` is calculated directly from their along-track fractions `(frac_t - frac_{t-1}) * length_m`.
- Moving backward against a oneway street is heavily penalized: `d_route = 100,000 m`.
- If two candidates are geographically disconnected in the road graph, `ln p(s_t | s_{t-1}) = -infinity`.

---

## 4. Viterbi Trellis Dynamic Programming

The optimal state sequence `S* = argmax_S L(S | Z)` is computed using the Viterbi dynamic programming algorithm over a trellis matrix:

1. **Initialization (t = 0):**
   For each candidate `j` at step 0:
   `V(0, j) = ln p(z_0 | s_{0,j})`
   `backtrack[0][j] = -1`

2. **Recursion (t = 1 to T - 1):**
   For each candidate `j` at step `t`:
   `V(t, j) = ln p(z_t | s_{t,j}) + max_i [ V(t - 1, i) + ln p(s_{t,j} | s_{t-1,i}) ]`
   `backtrack[t][j] = argmax_i [ V(t - 1, i) + ln p(s_{t,j} | s_{t-1,i}) ]`

3. **Termination:**
   `best_final = argmax_j V(T - 1, j)`

4. **Backtracking:**
   Trace `backtrack[t][current_state]` from `t = T - 1` back to `t = 0` to yield the globally optimal sequence of snapped road projections.

---

## 5. Discontinuity Handling and Gap Recovery

In real-world tracking datasets, vehicles pass through tunnels, experience GPS dropouts, or temporarily drive outside mapped areas.

Rhumb provides gap-resilient recovery:
- If observation `t` has zero road candidates within the search radius, the trellis treats step `t` as a discontinuity, resetting state expansion at step `t + 1`.
- When backtracking discovers a disconnected segment, the algorithm bridges the gap by retaining the raw GPS coordinate without injecting spurious long-distance jumps across the globe.
- Average match confidence is reported as the normalized mean of individual candidate emission confidences.
