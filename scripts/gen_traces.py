#!/usr/bin/env python3
"""
Member 5 trace generator for the 1 KB direct-mapped cache.

Writes four address traces to traces/ (sequential, random, repeated and
conflicting addresses). Every line holds one CPU read:

    <address> <expected data> <expected hit>

    address        32-bit byte address, hex
    expected data  32-bit word the cache must return, hex
    expected hit   1 = cache hit expected, 0 = miss expected

Lines starting with '#' are comments. The expected values come from an
independent Python reference model:

  * memory contents follow the deterministic default pattern documented in
    rtl/main_memory_model.v (no testbench overrides are used), and
  * hits/misses come from a 64-line, 16-byte-block direct-mapped cache that
    starts empty (all lines invalid) at the beginning of every trace.

The output is deterministic (fixed random seed), so regenerating the traces
gives byte-identical files.

Usage:  python3 scripts/gen_traces.py [output_dir]
"""

import os
import random
import sys

NUM_LINES = 64
BLOCK_BYTES = 16
CACHE_BYTES = NUM_LINES * BLOCK_BYTES  # 1 KB
MASK32 = 0xFFFFFFFF


def memory_word(addr):
    """Reference for main_memory_model.get_default_word()."""
    aligned = addr & ~0x3 & MASK32
    upper = ((aligned >> 16) ^ 0x5A5A) & 0xFFFF
    lower = aligned & 0xFFFF
    return ((upper << 16) | lower) ^ 0xA5A5A5A5


def split(addr):
    tag = (addr >> 10) & 0x3FFFFF
    index = (addr >> 4) & 0x3F
    return tag, index


def annotate(addresses):
    """Run the reference cache over a trace; return (addr, data, hit) rows."""
    tags = [None] * NUM_LINES  # None = invalid line
    rows = []
    for addr in addresses:
        addr &= MASK32
        tag, index = split(addr)
        hit = tags[index] == tag
        if not hit:
            tags[index] = tag
        rows.append((addr, memory_word(addr), 1 if hit else 0))
    return rows


# -----------------------------------------------------------------------------
# Trace definitions
# -----------------------------------------------------------------------------
def trace_sequential():
    """Word-by-word sweep over 2 KB (twice the cache size).

    One compulsory miss per 16-byte block, then three hits on the remaining
    words of that block: expected hit ratio 75 %.
    """
    base = 0x0001_0000
    return [base + 4 * i for i in range(2 * CACHE_BYTES // 4)]


def trace_random():
    """512 random byte addresses in a 4 KB window (4x the cache size).

    Byte offsets are random too, so unaligned addresses are covered; the cache
    must still return the full containing word.
    """
    rng = random.Random(0x5EED)
    base = 0x0002_0000
    return [base + rng.randrange(4 * CACHE_BYTES) for _ in range(512)]


def trace_repeated():
    """Four passes over a 512-byte array that fits in the cache.

    Pass 1 has one compulsory miss per block; passes 2-4 must be all hits.
    """
    base = 0x0003_0000
    array_bytes = CACHE_BYTES // 2
    one_pass = [base + 4 * i for i in range(array_bytes // 4)]
    return one_pass * 4


def trace_conflict():
    """Addresses that share a cache index but have different tags.

    Part 1: three blocks A, B, C 1 KB apart all map to index 4. Accessing
            them round-robin evicts the line every time (thrashing); a second
            word of the just-filled block is read in between to prove the
            refilled line is usable (hit) before it is evicted again.
    Part 2: index 63 with the smallest and largest possible tags
            (0x000003F0 vs 0xFFFFFFF0) ping-ponged at every word offset.
    Part 3: index 0 ping-pong between tag 0 and tag 1.
    """
    a = 0x0004_0040
    b = a + CACHE_BYTES
    c = a + 2 * CACHE_BYTES
    trace = []
    for r in range(16):
        off = 4 * (r % 4)
        trace += [a + off, a + (off ^ 0x8), b + off, b + (off ^ 0x4), c + off]
    for r in range(16):
        off = 4 * (r % 4)
        trace += [0x0000_03F0 + off, 0xFFFF_FFF0 + off]
    for r in range(16):
        trace += [0x0000_0000 + 4 * (r % 4), 0x0000_0400 + 4 * (r % 4)]
    return trace


TRACES = [
    ("sequential", trace_sequential),
    ("random", trace_random),
    ("repeated", trace_repeated),
    ("conflict", trace_conflict),
]


def write_trace(out_dir, name, func):
    rows = annotate(func())
    hits = sum(r[2] for r in rows)
    path = os.path.join(out_dir, f"{name}.trace")
    with open(path, "w") as f:
        f.write(f"# Trace: {name}\n")
        for line in (func.__doc__ or "").strip().splitlines():
            f.write(f"# {line.strip()}\n".rstrip() + "\n")
        f.write(f"# Requests: {len(rows)}  expected hits: {hits}  "
                f"expected misses: {len(rows) - hits}\n")
        f.write("# Format: <address hex> <expected data hex> <expected hit 1/0>\n")
        for addr, data, hit in rows:
            f.write(f"{addr:08x} {data:08x} {hit}\n")
    return path, len(rows), hits


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "traces")
    os.makedirs(out_dir, exist_ok=True)
    for name, func in TRACES:
        path, n, hits = write_trace(out_dir, name, func)
        print(f"{os.path.relpath(path)}: {n} requests, {hits} hits, "
              f"{n - hits} misses ({100.0 * hits / n:.2f} % hit)")


if __name__ == "__main__":
    main()
