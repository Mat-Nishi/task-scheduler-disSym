const std = @import("std");
const posix = std.posix;
const net = std.net;
const protocol = @import("protocol.zig");

pub const Network = struct {
    listen_fd: posix.socket_t,
    port: u16,

    pub fn init(port: u16) !Network {
        const fd = try posix.socket(posix.AF.INET, posix.SOCK.STREAM, 0);
        errdefer posix.close(fd);

        try posix.setsockopt(fd, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
        
        const address = try net.Address.parseIp4("0.0.0.0", port);
        try posix.bind(fd, &address.any, address.getOsSockLen());
        try posix.listen(fd, 10);

        return Network{
            .listen_fd = fd,
            .port = port,
        };
    }

    pub fn deinit(self: *Network) void {
        posix.close(self.listen_fd);
    }

    pub fn sendMessage(target_port: u16, msg: protocol.Message) !void {
        const fd = try posix.socket(posix.AF.INET, posix.SOCK.STREAM, 0);
        defer posix.close(fd);

        const address = try net.Address.parseIp4("127.0.0.1", target_port);

        try posix.connect(fd, &address.any, address.getOsSockLen()); 

        const msg_bytes = std.mem.asBytes(&msg);
        _ = try posix.send(fd, msg_bytes, 0);
    }

    pub fn pollForMessage(self: *Network, timeout_ms: i32) !?protocol.Message {
        var poll_fds = [_]posix.pollfd{
            .{ .fd = self.listen_fd, .events = posix.POLL.IN, .revents = 0 },
        };

        const num_events = try posix.poll(&poll_fds, timeout_ms);

        if (num_events > 0) {
            if ((poll_fds[0].revents & posix.POLL.IN) != 0) {
                var client_addr: net.Address = undefined;
                var client_addr_len: posix.socklen_t = @sizeOf(net.Address);
                
                const client_fd = try posix.accept(self.listen_fd, &client_addr.any, &client_addr_len, 0);
                defer posix.close(client_fd);
                
                var incoming_msg: protocol.Message = undefined;
                const msg_bytes = std.mem.asBytes(&incoming_msg);
                const bytes_read = try posix.recv(client_fd, msg_bytes, 0);
                
                if (bytes_read == @sizeOf(protocol.Message)) {
                    return incoming_msg;
                }
            }
        }
        
        return null;
    }
};
