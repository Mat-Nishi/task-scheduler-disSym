const std = @import("std");

pub const MessageType = enum(u8) {
    election = 1,
    answer = 2,
    coordinator = 3,
    heartbeat = 4,
    task = 5,
    client_task = 6,
    heartbeat_ack = 7,
    task_complete = 8,
    sync_queue = 9,
};

pub const TaskInfo = extern struct {
    task_id: u32,
    duration_ms: u32,
};

pub const Message = extern struct {
    msg_type: MessageType,
    sender_id: u32,
    sender_port: u16,
    payload: u32,
    duration_ms: u32,
    queued_tasks: [10]TaskInfo,
    queue_len: u8,
};

pub const Role = enum {
    follower,
    candidate,
    leader,
};

pub const Peer = struct {
    id: u32,
    port: u16,
    last_seen: i64,
    is_busy: bool,
};

pub fn newMsg(m_type: MessageType, id: u32, port: u16, payload: u32, duration: u32) Message{
    return Message{
        .msg_type = m_type,
        .sender_id = id,
        .sender_port = port,
        .payload = payload,
        .duration_ms = duration,
        .queued_tasks = [_]TaskInfo{.{ .task_id = 0, .duration_ms = 0 }} ** 10,
        .queue_len = 0,
    };
}
