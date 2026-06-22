const std = @import("std");
const BullyEngine = @import("bully.zig").BullyEngine;
const protocol = @import("protocol.zig");
const Network = @import("network.zig").Network;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len != 3) {
        std.debug.print("Usage: {s} <node_id> <port>\n", .{args[0]});
        return;
    }

    const node_id = try std.fmt.parseInt(u32, args[1], 10);
    const port = try std.fmt.parseInt(u16, args[2], 10);

    var election_engine = try BullyEngine.init(allocator, node_id, port);
    defer election_engine.deinit();
    try election_engine.loadPeers("cluster.nodes"); 

    var task_queue: std.ArrayList(protocol.Message) = .empty;
    defer task_queue.deinit(allocator);

    var is_busy = false;
    var current_task_id: u32 = 0;
    var busy_until: i64 = 0;
    var last_progress_print: i64 = 0;

    std.debug.print("[APP] NODE {d} started on port {d}.\n", .{ election_engine.id, election_engine.port });

    while (true) {
        // broadcast task queue
        if (try election_engine.pollOnce(is_busy, task_queue.items)) |app_msg| {
            
            if (app_msg.msg_type == .client_task) {
                if (election_engine.role == .leader) {
                    std.debug.print("\n[APP][LEADER] Queueing external TASK #{d} (Duration: {d}ms)\n", 
                        .{app_msg.payload, app_msg.duration_ms});
                    try task_queue.append(allocator, app_msg);
                }
            } 
            else if (app_msg.msg_type == .heartbeat and election_engine.role == .follower) {
                // update queue snapshot (in case of leader change)
                task_queue.clearRetainingCapacity();
                const copy_len = @min(app_msg.queue_len, 10);
                for (0..copy_len) |i| {
                    const backup_msg = protocol.newMsg(
                        .client_task, 999, 0, 
                        app_msg.queued_tasks[i].task_id, 
                        app_msg.queued_tasks[i].duration_ms
                    );
                    try task_queue.append(allocator, backup_msg);
                }
            }
            else if (app_msg.msg_type == .task and election_engine.role == .follower) {
                if (!is_busy) {
                    is_busy = true;
                    current_task_id = app_msg.payload;
                    busy_until = std.time.milliTimestamp() + app_msg.duration_ms;
                    last_progress_print = std.time.milliTimestamp();
                    std.debug.print("\n[APP][FOLLOWER] NODE {d} ACCEPTED TASK #{d}, starting work for {d}ms...\n", 
                        .{election_engine.id, current_task_id, app_msg.duration_ms});
                }
            }
            else if (app_msg.msg_type == .sync_queue and election_engine.role == .leader) {
                std.debug.print("\n[APP][LEADER] Received queue handover from previous leader! Recovering {d} tasks...\n", .{app_msg.queue_len});
                const copy_len = @min(app_msg.queue_len, 10);
                for (0..copy_len) |i| {
                    const recovered_msg = protocol.newMsg(
                        .client_task, 999, 0, 
                        app_msg.queued_tasks[i].task_id, 
                        app_msg.queued_tasks[i].duration_ms
                    );
                    try task_queue.append(allocator, recovered_msg);
                }
            }
        }

        const now = std.time.milliTimestamp();

        // leader - assign task
        if (election_engine.role == .leader and task_queue.items.len > 0) {
            for (election_engine.peers.items) |*peer| {
                if (now - peer.last_seen < 3000 and !peer.is_busy) {
                    const task_app_msg = task_queue.orderedRemove(0);
                    peer.is_busy = true; 

                    const task_msg = protocol.newMsg(
                        .task, election_engine.id, election_engine.port, 
                        task_app_msg.payload, task_app_msg.duration_ms
                    );

                    std.debug.print("\n[APP][LEADER] Assigned TASK #{d} to NODE {d} ({d} tasks left in queue)\n", 
                        .{task_msg.payload, peer.id, task_queue.items.len});
                    
                    Network.sendMessage(peer.port, task_msg) catch {};
                    break; 
                }
            }
        }

        // follower - process task 
        if (election_engine.role == .follower and is_busy) {
            if (now >= busy_until) {
                is_busy = false; 
                std.debug.print("[APP][FOLLOWER] NODE {d} FINISHED TASK #{d} and is now FREE\n", 
                    .{election_engine.id, current_task_id});
                
                if (election_engine.leader_id) |ldr_id| {
                    for (election_engine.peers.items) |peer| {
                        if (peer.id == ldr_id) {
                            const complete_msg = protocol.newMsg(.task_complete, election_engine.id, election_engine.port, current_task_id, 0);
                            Network.sendMessage(peer.port, complete_msg) catch {};
                            break;
                        }
                    }
                }
            } else if (now - last_progress_print >= 1000) {
                const seconds_left = @divTrunc(busy_until - now, 1000) + 1;
                std.debug.print("[APP][FOLLOWER] NODE {d} working... ({d}s remaining)\n", 
                    .{election_engine.id, seconds_left});
                last_progress_print = now;
            }
        }
    }
}
