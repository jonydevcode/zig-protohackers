//! User. Owns state about the user.

const Self = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const max_name_len = 32;

allocator: Allocator,
name: []const u8, // primary key

pub fn init(allocator: Allocator, name: []const u8) !Self {
    return Self{
        .allocator = allocator,
        .name = try allocator.dupe(u8, name),
    };
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.name);
    self.* = undefined;
}
