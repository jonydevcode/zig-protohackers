//! Threadsafe implementation of the database.
//! Effectively, a StringHashMap with a mutex lock.
const Self = @This();
const std = @import("std");
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

mutex: std.Io.Mutex = .init,
map: std.StringHashMap([]const u8),
allocator: Allocator,
io: std.Io,

pub fn init(allocator: Allocator, io: std.Io) Self {
    return Self{
        .map = .init(allocator),
        .allocator = allocator,
        .io = io,
    };
}

pub fn deinit(self: *Self) void {
    var it = self.map.iterator();
    while (it.next()) |entry| {
        self.allocator.free(entry.key_ptr.*);
        self.allocator.free(entry.value_ptr.*);
    }
    self.map.deinit();
}

pub fn put(self: *Self, key: []const u8, val: []const u8) !void {
    try self.mutex.lock(self.io);
    defer self.mutex.unlock(self.io);

    // if the entry exists, remove it and free the memory
    if (self.map.getEntry(key)) |entry| {
        const k = entry.key_ptr.*;
        const v = entry.value_ptr.*;
        _ = self.map.remove(key);
        self.allocator.free(k);
        self.allocator.free(v);
    }

    const key_dupe = try self.allocator.dupe(u8, key);
    const val_dupe = try self.allocator.dupe(u8, val);

    try self.map.put(key_dupe, val_dupe);
}

pub fn get(self: *Self, key: []const u8) !?[]const u8 {
    try self.mutex.lock(self.io);
    defer self.mutex.unlock(self.io);

    return self.map.get(key);
}

test "Basic database read and write" {
    var db = Self.init(std.testing.allocator, std.testing.io);
    defer db.deinit();

    try db.put("hello", "world");
    try db.put("123", "456");

    try expect(std.mem.eql(u8, (try db.get("hello")).?, "world"));
    try expect(std.mem.eql(u8, (try db.get("123")).?, "456"));
    try expectEqual(try db.get("notfound"), null);
}

test "Overwrite existing" {
    var db = Self.init(std.testing.allocator, std.testing.io);
    defer db.deinit();

    try db.put("hello", "world");
    try expect(std.mem.eql(u8, (try db.get("hello")).?, "world"));
    try db.put("hello", "123");
    try expect(std.mem.eql(u8, (try db.get("hello")).?, "123"));
}

test "Empty string as key" {
    var db = Self.init(std.testing.allocator, std.testing.io);
    defer db.deinit();

    try db.put("", "world");
    try expect(std.mem.eql(u8, (try db.get("")).?, "world"));
}
