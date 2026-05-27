//! ServerState - stores the user and connection maps, locked
//! behind a mutex for thread safe access.
const Self = @This();
const std = @import("std");
const User = @import("User.zig");
const Connection = @import("Connection.zig");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const net = std.Io.net;
const log = std.log;

state_mutex: std.Io.Mutex = .init,

conn_map: std.StringHashMap(*Connection),
user_map: std.StringHashMap(*User),
allocator: std.mem.Allocator,
io: std.Io,

const UserIterator = struct {
    iterator: std.StringHashMap(*User).Iterator,

    pub fn init(user_map: *std.StringHashMap(*User)) UserIterator {
        return UserIterator{
            .iterator = user_map.iterator(),
        };
    }

    pub fn next(self: *UserIterator) ?[]const u8 {
        const n = self.iterator.next();
        if (n) |entry| {
            return entry.key_ptr.*;
        }
        return null;
    }
};

pub fn init(io: Io, alloc: Allocator) Self {
    return Self{
        .conn_map = .init(alloc),
        .user_map = .init(alloc),
        .io = io,
        .allocator = alloc,
    };
}

pub fn deinit(self: *Self) void {
    // free the keys
    var conn_it = self.conn_map.iterator();
    while (conn_it.next()) |entry| {
        self.allocator.free(entry.key_ptr.*);
    }
    var user_it = self.user_map.iterator();
    while (user_it.next()) |entry| {
        self.allocator.free(entry.key_ptr.*);
    }

    self.conn_map.deinit();
    self.user_map.deinit();
}

pub fn lock(self: *Self) !void {
    try self.state_mutex.lock(self.io);
}

pub fn unlock(self: *Self) void {
    self.state_mutex.unlock(self.io);
}

pub fn userIterator(self: *Self) UserIterator {
    return UserIterator.init(&self.user_map);
}

pub fn putUser(
    self: *Self,
    name: []const u8,
    user: *User,
    conn: *Connection,
) !void {
    try self.state_mutex.lock(self.io);
    defer self.state_mutex.unlock(self.io);

    const name1 = try self.allocator.dupe(u8, name);
    try self.user_map.put(name1, user);
    const name2 = try self.allocator.dupe(u8, name);
    try self.conn_map.put(name2, conn);
}

pub fn removeUser(self: *Self, name: []const u8) !void {
    try self.state_mutex.lock(self.io);
    defer self.state_mutex.unlock(self.io);

    // free the keys
    if (self.user_map.getKey(name)) |k| {
        _ = self.user_map.remove(name);
        self.allocator.free(k);
    }
    if (self.conn_map.getKey(name)) |k| {
        _ = self.conn_map.remove(name);
        self.allocator.free(k);
    }
}

pub fn getConnection(self: *Self, name: []const u8) ?*Connection {
    return self.conn_map.get(name);
}

pub fn containsUser(
    self: *Self,
    name: []const u8,
) !bool {
    try self.state_mutex.lock(self.io);
    defer self.state_mutex.unlock(self.io);

    return self.user_map.contains(name);
}
