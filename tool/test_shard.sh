#!/usr/bin/env bash
# Prints the test files of shard $1 (0-based) out of $2, one per line.
# Files are dealt out in turn from the sorted list, so every file is in
# exactly one shard and the slow ones spread out.
set -euo pipefail
shard=${1:?shard index}
total=${2:?number of shards}
find test -name '*_test.dart' | LC_ALL=C sort | awk -v n="$total" -v i="$shard" '(NR - 1) % n == i'
