#!/bin/bash
set -e

cd "$(dirname "$0")/.."

if [ -z "$1" ]; then
    echo "Usage: ./scripts/run.sh <node_id>"
    echo "Example: ./scripts/run.sh 1"
    exit 1
fi

ID=$1
PORT=$((8080 + ID))

if [ ! -f "./local_zig" ]; then
    echo "Error: local_zig not found. Please run ./scripts/zig.sh first."
    exit 1
fi

echo "Starting Node $ID on port $PORT..."
./local_zig run src/main.zig -- "$ID" "$PORT"
