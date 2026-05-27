const Self = @This();
const std = @import("std");
const User = @import("User.zig");
const Connection = @import("Connection.zig");
const ServerState = @import("ServerState.zig");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const net = std.Io.net;
const log = std.log;

allocator: Allocator,
server_state: ServerState,

fn isAllAlphanumeric(s: []const u8) bool {
    for (s) |c| {
        if (!std.ascii.isAlphanumeric(c)) return false;
    }
    return true;
}

pub fn init(io: std.Io, alloc: Allocator) Self {
    return Self{
        .server_state = ServerState.init(io, alloc),
        .allocator = alloc,
    };
}

pub fn deinit(self: *Self) void {
    self.server_state.deinit();
}

fn announcePresence(self: *Self, name: []const u8) !void {
    try self.server_state.lock();
    defer self.server_state.unlock();

    var it = self.server_state.userIterator();
    while (it.next()) |cur_name| {
        if (std.mem.eql(u8, cur_name, name)) continue;
        if (self.server_state.getConnection(cur_name)) |cur_conn| {
            var tmpbuf: [4096]u8 = undefined;
            const tmpslice = try std.fmt.bufPrint(&tmpbuf, "* {s} has entered the room", .{name});
            try cur_conn.writeMessage(tmpslice);
        }
    }
}

fn getCurrentUsers(self: *Self, buf: []u8, exclusion: []const u8) ![]const u8 {
    try self.server_state.lock();
    defer self.server_state.unlock();

    var name_list: std.ArrayList([]const u8) = .empty;
    defer name_list.deinit(self.allocator);

    var it = self.server_state.userIterator();
    while (it.next()) |cur_name| {
        if (std.mem.eql(u8, cur_name, exclusion)) continue;
        try name_list.append(self.allocator, cur_name);
    }

    const name_list_str = try std.mem.join(self.allocator, ", ", name_list.items);
    defer self.allocator.free(name_list_str);

    @memcpy(buf[0..name_list_str.len], name_list_str);

    return buf[0..name_list_str.len];
}

fn broadcastMessage(self: *Self, sender: []const u8, msg: []const u8) !void {
    try self.server_state.lock();
    defer self.server_state.unlock();

    var it = self.server_state.userIterator();
    while (it.next()) |cur_name| {
        if (std.mem.eql(u8, cur_name, sender)) continue;
        if (self.server_state.getConnection(cur_name)) |cur_conn| {
            var tmpbuf: [4096]u8 = undefined;
            const tmpslice = try std.fmt.bufPrint(&tmpbuf, "[{s}] {s}", .{ sender, msg });
            cur_conn.writeMessage(tmpslice) catch {
                std.debug.print("Couldn't send broadcast to to {s}.\n", .{cur_name});
            };
        }
    }
}

fn broadcastDisconnection(self: *Self, name: []const u8) !void {
    try self.server_state.lock();
    defer self.server_state.unlock();

    var it = self.server_state.userIterator();
    while (it.next()) |cur_name| {
        if (std.mem.eql(u8, cur_name, name)) continue;
        if (self.server_state.getConnection(cur_name)) |cur_conn| {
            var tmpbuf: [4096]u8 = undefined;
            const tmpslice = try std.fmt.bufPrint(&tmpbuf, "* {s} has left the room", .{name});
            cur_conn.writeMessage(tmpslice) catch {
                std.debug.print("Couldn't send disconnection to {s}.\n", .{cur_name});
            };
        }
    }
}

pub fn handleClient(
    self: *Self,
    alloc: Allocator,
    reader: *Io.Reader,
    writer: *Io.Writer,
) !void {
    // 1. Ask user for a name
    // 2. Create a new user object, add it to map
    // 3a. Everyone else - Announce presence: * bob has entered the room
    // 3b. New user      - List all present users
    // 3. while(true)
    // 3a. Broadcast any new messages received
    // 4. Upon disconnect, broadcast * dave has left the room

    var conn = Connection.init(reader, writer);

    const welcome_msg = "Welcome to budgetchat! What shall I call you?";
    try conn.writeMessage(welcome_msg);
    // Cases to handle:
    // 1. Name exceeds 32 len
    // 2. Name is 0 len
    // 3. Name contains non-alphanumeric chars
    // 4. Name already exists in session
    var namebuf: [User.max_name_len]u8 = undefined;
    const name = conn.readMessage(&namebuf) catch |err| {
        std.debug.print("Client disconnected before providing name: {}\n", .{err});
        try conn.writeMessage("Your name is invalid.");
        return;
    };
    std.debug.print("[Client->Server] {s}\n", .{name});
    if (name.len <= 0) {
        try conn.writeMessage("Name must contain at least 1 character.");
        return;
    }
    if (!isAllAlphanumeric(name)) {
        try conn.writeMessage("Name must only contain alphanumeric characters.");
        return;
    }
    if (try self.server_state.containsUser(name)) {
        try conn.writeMessage("Name already exists on the server.");
        return;
    }
    std.debug.print("[Server] New user joined: {s}\n", .{name});

    var user = try User.init(alloc, name);
    defer user.deinit();

    try self.server_state.putUser(name, &user, &conn);

    // 3a. Everyone else - Announce presence: * bob has entered the room
    try self.announcePresence(name);

    // 3b. New user      - List all present users
    var curusersbuf: [4096]u8 = undefined;
    const cur_users = try self.getCurrentUsers(&curusersbuf, name);
    var buf2: [4096]u8 = undefined;
    const cur_users_msg = try std.fmt.bufPrint(&buf2, "* The room contains: {s}", .{cur_users});
    try conn.writeMessage(cur_users_msg);

    while (true) {
        var inputbuf: [4096]u8 = undefined;
        const input = conn.readMessage(&inputbuf) catch |err| switch (err) {
            error.EndOfStream => {
                break;
            },
            else => {
                std.debug.print("{}\n", .{err});
                try conn.writeMessage("Your input is invalid.");
                break;
            },
        };
        std.debug.print("[{s}->Server] {s}\n", .{ name, input });
        try self.broadcastMessage(name, input);
    }

    // disconnection
    // broadcast * bob has left the room
    try self.broadcastDisconnection(name);
    try self.server_state.removeUser(name);
}

test "name is correct" {
    var session = Self.init(std.testing.io, std.testing.allocator);
    defer session.deinit();

    const inputbuf = "testname\nhi everyone\n";
    var reader = Io.Reader.fixed(inputbuf);

    var outputbuf: [4096]u8 = undefined;
    var writer = Io.Writer.fixed(&outputbuf);

    try session.handleClient(std.testing.allocator, &reader, &writer);

    std.debug.print("--> {s}\n", .{writer.buffered()});
    std.debug.print("================ test ends ================\n", .{});
}

test "existing name" {
    var session = Self.init(std.testing.io, std.testing.allocator);
    defer session.deinit();

    const inputbuf1 = "testname\nhi everyone\n";
    var reader1 = Io.Reader.fixed(inputbuf1);

    var outputbuf1: [4096]u8 = undefined;
    var writer1 = Io.Writer.fixed(&outputbuf1);

    try session.handleClient(std.testing.allocator, &reader1, &writer1);

    const inputbuf2 = "testname\nhi everyone\n";
    var reader2 = Io.Reader.fixed(inputbuf2);

    var outputbuf2: [4096]u8 = undefined;
    var writer2 = Io.Writer.fixed(&outputbuf2);

    try session.handleClient(std.testing.allocator, &reader2, &writer2);

    std.debug.print("[Client1] {s}\n", .{writer1.buffered()});
    std.debug.print("[Client2] {s}\n", .{writer2.buffered()});
    std.debug.print("================ test ends ================\n", .{});
}

test "3 x legit users" {
    var session = Self.init(std.testing.io, std.testing.allocator);
    defer session.deinit();

    const inputbuf1 = "Anna\nhi everyone\n";
    var reader1 = Io.Reader.fixed(inputbuf1);
    var outputbuf1: [4096]u8 = undefined;
    var writer1 = Io.Writer.fixed(&outputbuf1);

    try session.handleClient(std.testing.allocator, &reader1, &writer1);

    const inputbuf2 = "Bob\nhi everyone\n";
    var reader2 = Io.Reader.fixed(inputbuf2);
    var outputbuf2: [4096]u8 = undefined;
    var writer2 = Io.Writer.fixed(&outputbuf2);

    try session.handleClient(std.testing.allocator, &reader2, &writer2);

    const inputbuf3 = "Charlie\nhi everyone\n";
    var reader3 = Io.Reader.fixed(inputbuf3);
    var outputbuf3: [4096]u8 = undefined;
    var writer3 = Io.Writer.fixed(&outputbuf3);

    try session.handleClient(std.testing.allocator, &reader3, &writer3);

    std.debug.print("[Client1] {s}\n-------------------\n", .{writer1.buffered()});
    std.debug.print("[Client2] {s}\n-------------------\n", .{writer2.buffered()});
    std.debug.print("[Client3] {s}\n-------------------\n", .{writer3.buffered()});
    std.debug.print("================ test ends ================\n", .{});
}
