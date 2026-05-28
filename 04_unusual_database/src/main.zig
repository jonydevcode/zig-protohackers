const std = @import("std");
const Io = std.Io;
const Server = @import("Server.zig");

const server_ip = "0.0.0.0";
const server_port: u16 = 59111;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    var server = Server.init(io, allocator, server_ip, server_port);
    defer server.deinit();

    try server.run();
}
