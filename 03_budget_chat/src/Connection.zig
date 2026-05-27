const Self = @This();

const std = @import("std");
const User = @import("User.zig");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const net = std.Io.net;

reader: *Io.Reader,
writer: *Io.Writer,

pub fn init(reader: *Io.Reader, writer: *Io.Writer) Self {
    return Self{
        .reader = reader,
        .writer = writer,
    };
}

pub fn readMessage(self: *Self, buf: []u8) ![]const u8 {
    var w = std.Io.Writer.fixed(buf);
    const len = try self.reader.streamDelimiter(&w, '\n');
    self.reader.toss(1); // to skip the \n
    return buf[0..len];
}

pub fn writeMessage(self: *Self, s: []const u8) !void {
    try self.writer.writeAll(s);
    try self.writer.print("\n", .{});
    try self.writer.flush();
}
