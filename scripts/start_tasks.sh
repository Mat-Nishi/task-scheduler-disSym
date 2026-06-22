#!/bin/bash
set -e

cd "$(dirname "$0")/.."

if [ ! -f "./local_zig" ]; then
    echo "Error: local_zig not found. Please run ./scripts/setup_zig.sh first."
    exit 1
fi

echo "Starting Task Generator..."
./local_zig run src/task_generator.zig
