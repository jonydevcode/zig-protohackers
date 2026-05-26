const std = @import("std");
const ordered = @import("ordered");

// Define a comparison function for the keys.
// The function must return a `std.math.Order` value based on the comparison of the two keys
fn strCompare(lhs: []const u8, rhs: []const u8) std.math.Order {
    return std.mem.order(u8, lhs, rhs);
}

fn intCompare(lhs: i32, rhs: i32) std.math.Order {
    return std.math.order(lhs, rhs);
}

const b_tree_branch_factor: u16 = 4;

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    var map = ordered.BTreeMap(i32, i32, intCompare, b_tree_branch_factor).init(allocator);
    defer map.deinit();

    try map.put(100, 10);
    try map.put(90, 9);
    try map.put(110, 11);
    try map.put(50, 5);
    try map.put(10, 1);
    try map.put(95, 9);
    try map.put(-100, 5);

    var it = try map.iterator();
    defer it.deinit();
    while (try it.next()) |entry| {
        std.debug.print("{d} ", .{entry.key});
    }
    std.debug.print("\n", .{});
}
