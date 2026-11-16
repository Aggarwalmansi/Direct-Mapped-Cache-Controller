# Performance and baseline comparison

Cold cache per trace; all alternatives have 64 blocks of 16 bytes. Two-way and fully associative alternatives use LRU and are Python reference models, not implemented RTL. AMAT uses measured RTL hit time (2 cycles) and additional miss penalty (7 + 4L cycles). The simulation log is the source for measured latency; this script independently checks trace hit counts.

| Trace | Word latency | Hits / requests | Hit % | AMAT cycles | 2-way hit % | Fully associative hit % |
|---|---:|---:|---:|---:|---:|---:|
| sequential | 0 | 384/512 | 75.00 | 3.7500 | 75.00 | 75.00 |
| sequential | 1 | 384/512 | 75.00 | 4.7500 | 75.00 | 75.00 |
| sequential | 5 | 384/512 | 75.00 | 8.7500 | 75.00 | 75.00 |
| random | 0 | 112/512 | 21.88 | 7.4688 | 23.05 | 25.78 |
| random | 1 | 112/512 | 21.88 | 10.5938 | 23.05 | 25.78 |
| random | 5 | 112/512 | 21.88 | 23.0938 | 23.05 | 25.78 |
| repeated | 0 | 480/512 | 93.75 | 2.4375 | 93.75 | 93.75 |
| repeated | 1 | 480/512 | 93.75 | 2.6875 | 93.75 | 93.75 |
| repeated | 5 | 480/512 | 93.75 | 3.6875 | 93.75 | 93.75 |
| conflict | 0 | 32/144 | 22.22 | 7.4444 | 63.89 | 95.14 |
| conflict | 1 | 32/144 | 22.22 | 10.5556 | 63.89 | 95.14 |
| conflict | 5 | 32/144 | 22.22 | 23.0000 | 63.89 | 95.14 |

An associative model isolates placement conflicts but does not establish timing or area benefits: associativity requires additional comparators and replacement logic. Low locality can dominate capacity/conflict improvements. No-cache memory traffic baseline is one word per request; this cache reads four words per miss, so traffic is 4 × miss count. A cache can increase traffic on random/conflicting traces. A no-cache latency speed-up is not claimed because no uncached CPU adapter has been implemented.
