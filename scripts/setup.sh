#!/bin/bash
set -e

cd "$(dirname "$0")/.."

NUM_NODES=9
START_PORT=8080
FILE="cluster.nodes"

echo "Generating cluster.nodes..."
rm -f $FILE

for i in $(seq 1 $NUM_NODES); do
    PORT=$((START_PORT + i))
    echo "$i $PORT" >> $FILE
done

echo "✅ Setup complete."
