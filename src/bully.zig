const std = @import("std");
const protocol = @import("protocol.zig");
const Network = @import("network.zig").Network;

const Message = protocol.Message;
const Role = protocol.Role;
const Peer = protocol.Peer;

pub const BullyEngine = struct {
    id: u32,
    role: Role,
    leader_id: ?u32,
    port: u16,
    network: Network,
    peers: std.ArrayList(Peer),
    allocator: std.mem.Allocator,
    last_heartbeat: i64,
    last_heartbeat_sent: i64,

    pub fn init(allocator: std.mem.Allocator, id: u32, port: u16) !BullyEngine {
        const net = try Network.init(port);
        const now = std.time.milliTimestamp();

        return BullyEngine{
            .id = id,
            .role = .candidate, 
            .leader_id = null,
            .port = port,
            .network = net,
            .peers = .empty,
            .allocator = allocator,
            .last_heartbeat = now,
            .last_heartbeat_sent = now,
        };
    }

    pub fn deinit(self: *BullyEngine) void {
        self.network.deinit();
        self.peers.deinit(self.allocator);
    }

    pub fn loadPeers(self: *BullyEngine, file_path: []const u8) !void {
        const file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close(); 
        const file_content = try file.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(file_content);
        var lines_it = std.mem.tokenizeAny(u8, file_content, "\r\n");
        while (lines_it.next()) |line| {
            var tokens = std.mem.tokenizeAny(u8, line, " ");
            const id_str = tokens.next() orelse continue;
            const port_str = tokens.next() orelse continue;
            const peer_id = try std.fmt.parseInt(u32, id_str, 10);
            const peer_port = try std.fmt.parseInt(u16, port_str, 10);
            if (peer_id != self.id) {
                try self.peers.append(self.allocator, Peer{ 
                    .id = peer_id, .port = peer_port, .last_seen = 0, .is_busy = false 
                });
            }
        }
    }

    pub fn startElection(self: *BullyEngine) !void {
        std.debug.print("\n[NODE {d}] starting election\n", .{self.id});
        self.role = .candidate;
        var higher_nodes: u32 = 0;
        
        const msg = protocol.newMsg(.election, self.id, self.port, 0, 0);

        for (self.peers.items) |peer| {
            if (peer.id > self.id) {
                Network.sendMessage(peer.port, msg) catch continue;
                higher_nodes += 1;
            }
        }
        if (higher_nodes == 0) try self.declareVictory();
    }

    pub fn declareVictory(self: *BullyEngine) !void {
        std.debug.print("\n[NODE {d}][FINSHED ELECTION] I am the new LEADER\n", .{self.id});
        self.role = .leader;
        self.leader_id = self.id;
        
        const msg = protocol.newMsg(.coordinator, self.id, self.port, 0, 0);
        for (self.peers.items) |peer| {
            Network.sendMessage(peer.port, msg) catch continue;
        }
    }

    pub fn pollOnce(self: *BullyEngine, is_busy: bool, current_queue: []const protocol.Message) !?Message {
        const now = std.time.milliTimestamp();
        var returned_msg: ?Message = null;

        if (try self.network.pollForMessage(100)) |incoming_msg| {
            switch (incoming_msg.msg_type) {
                .election => {
                    if (self.id > incoming_msg.sender_id) {
                        const reply = protocol.newMsg(.answer, self.id, self.port, 0, 0);
                        Network.sendMessage(incoming_msg.sender_port, reply) catch {};
                        try self.startElection();
                    }
                },
                .answer => {
                    self.role = .follower;
                },
                 .coordinator => {
                    if (self.role == .leader and current_queue.len > 0) {
                        std.debug.print("\n[NODE {d}][MUTINY] new LEADER {d}. Handing over {d} tasks\n", 
                            .{self.id, incoming_msg.sender_id, current_queue.len});
                            
                        var sync_msg = protocol.newMsg(.sync_queue, self.id, self.port, 0, 0);
                        const copy_len = @min(current_queue.len, 10);
                        sync_msg.queue_len = @as(u8, @intCast(copy_len));
                        
                        for (0..copy_len) |i| {
                            sync_msg.queued_tasks[i] = .{ 
                                .task_id = current_queue[i].payload, 
                                .duration_ms = current_queue[i].duration_ms 
                            };
                        }
                        Network.sendMessage(incoming_msg.sender_port, sync_msg) catch {};
                    }

                    std.debug.print("\n[NODE {d}] NODE {d} is the new LEADER\n", .{self.id, incoming_msg.sender_id});
                    self.role = .follower;
                    self.leader_id = incoming_msg.sender_id;
                    self.last_heartbeat = now;
                },
                .sync_queue => {
                    returned_msg = incoming_msg;
                },
                .heartbeat => {
                    if (incoming_msg.sender_id < self.id) {
                        try self.startElection();
                    } else {
                        self.last_heartbeat = now;
                        if (self.leader_id != incoming_msg.sender_id) {
                            self.leader_id = incoming_msg.sender_id;
                            self.role = .follower;
                        }
                        const ack = protocol.newMsg(.heartbeat_ack, self.id, self.port, @intFromBool(is_busy), 0);
                        Network.sendMessage(incoming_msg.sender_port, ack) catch {};
                        
                        returned_msg = incoming_msg; 
                    }
                },
                .heartbeat_ack => {
                    if (self.role == .leader) {
                        for (self.peers.items) |*peer| {
                            if (peer.id == incoming_msg.sender_id) {
                                peer.last_seen = now;
                                peer.is_busy = (incoming_msg.payload == 1);
                                break;
                            }
                        }
                    }
                },
                .task_complete => {
                    if (self.role == .leader) {
                        for (self.peers.items) |*peer| {
                            if (peer.id == incoming_msg.sender_id) {
                                peer.last_seen = now;
                                peer.is_busy = false; 
                                break;
                            }
                        }
                    }
                },
                .task, .client_task => {
                    returned_msg = incoming_msg;
                },
            }
        } 
        
        if (self.role == .leader) {
            if (now - self.last_heartbeat_sent > 1000) {
                var msg = protocol.newMsg(.heartbeat, self.id, self.port, 0, 0);
                
                const copy_len = @min(current_queue.len, 10);
                msg.queue_len = @as(u8, @intCast(copy_len));
                for (0..copy_len) |i| {
                    msg.queued_tasks[i] = .{ 
                        .task_id = current_queue[i].payload, 
                        .duration_ms = current_queue[i].duration_ms 
                    };
                }

                for (self.peers.items) |peer| Network.sendMessage(peer.port, msg) catch continue;
                self.last_heartbeat_sent = now;
            }
        } else {
            if (now - self.last_heartbeat > 3000) {
                try self.startElection();
                self.last_heartbeat = now; 
            }
        }
        
        return returned_msg;
    }
};
