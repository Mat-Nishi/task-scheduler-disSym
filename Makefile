# Default number of nodes if not specified
NUM_NODES ?= 3
START_PORT = 8080

ZIG_BUILD = zig build-exe src/main.zig -O ReleaseSafe
ZIG_BUILD_CLIENT = zig build-exe src/task_generator.zig -O ReleaseSafe

.PHONY: all build setup run stop clean

all: run

build:
	@echo "Compiling binaries..."
	@$(ZIG_BUILD)
	@$(ZIG_BUILD_CLIENT)

setup: build
	@echo "Generating cluster.nodes for $(NUM_NODES) nodes..."
	@rm -f cluster.nodes
	@for i in $$(seq 1 $(NUM_NODES)); do \
		PORT=$$(( $(START_PORT) + $$i )); \
		echo "$$i $$PORT" >> cluster.nodes; \
	done
	@echo "Cluster configuration saved."

run: setup stop
	@echo "Starting $(NUM_NODES) nodes in the background..."
	@mkdir -p logs
	@rm -f logs/*.log
	@touch logs/client.log
	@for i in $$(seq 1 $(NUM_NODES)); do \
		PORT=$$(( $(START_PORT) + $$i )); \
		touch logs/node-$$i.log; \
		./main $$i $$PORT > logs/node-$$i.log 2>&1 & \
	done
	@echo "Starting task generator..."
	@./task_generator >> logs/client.log 2>&1 &
	@echo "================================================="
	@echo "   Local Cluster Running! Tailing logs...        "
	@echo "   (Press Ctrl+C to exit log view. Run 'make stop' to kill)"
	@echo "================================================="
	@sleep 0.5
	@tail -f logs/*.log

stop:
	@echo "Stopping any running cluster processes..."
	@pkill -x main 2>/dev/null || true
	@pkill -x task_generator 2>/dev/null || true

clean: stop
	@echo "Cleaning up workspace..."
	@rm -f main main.o task_generator task_generator.o cluster.nodes
	@rm -rf logs/
	@echo "Cleanup complete."
