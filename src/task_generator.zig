const std = @import("std");
const protocol = @import("protocol.zig");
const Network = @import("network.zig").Network;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ports = std.ArrayList(u16).empty;
    defer ports.deinit(allocator);

    const file = try std.fs.cwd().openFile("cluster.nodes", .{});
    const file_content = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(file_content);
    file.close();

    var lines_it = std.mem.tokenizeAny(u8, file_content, "\r\n");
    while (lines_it.next()) |line| {
        var tokens = std.mem.tokenizeAny(u8, line, " ");
        _ = tokens.next() orelse continue; 
        const port_str = tokens.next() orelse continue;
        const port = try std.fmt.parseInt(u16, port_str, 10);
        try ports.append(allocator, port);
    }

    std.debug.print("[CLIENT] task generator started, known cluster ports: {d}\n", .{ports.items.len});

    var prng = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.milliTimestamp())));
    const random = prng.random();

    while (true) {
        const task_id = random.intRangeAtMost(u32, 1000, 9999);
        const duration = random.intRangeAtMost(u32, 1000, 5000); // 1s to 5s
        
        const client_msg = protocol.newMsg(.client_task, 999, 0, task_id, duration);

        std.debug.print("\n[CLIENT] broadcasting TASK #{d} (Duration: {d}ms) to cluster...\n", .{task_id, duration});
        // broadcast (leader unkown for the client)
        for (ports.items) |port| {
            Network.sendMessage(port, client_msg) catch {};
        }

        const sleep_sec = random.intRangeAtMost(u64, 1, 2);
        std.Thread.sleep(std.time.ns_per_s * sleep_sec);
    }
}
