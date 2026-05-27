const std = @import("std");
const User = @import("User.zig");
const Server = @import("Server.zig");
const log = std.log;
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;

const listen_ip_addr = "0.0.0.0";
const listen_port: u16 = 59111;

fn handleClient(io: std.Io, alloc: Allocator, stream: std.Io.net.Stream, session: *Server) !void {
    defer stream.close(io);
    std.debug.print("A client has CONNECTED.\n", .{});
    var readbuf: [4096]u8 = undefined;
    var net_reader = stream.reader(io, &readbuf);
    const reader = &net_reader.interface;
    var writebuf: [4096]u8 = undefined;
    var net_writer = stream.writer(io, &writebuf);
    const writer = &net_writer.interface;
    try session.handleClient(alloc, reader, writer);
    std.debug.print("A client has DISCONNECTED.\n", .{});
}

fn handleClientTask(
    io: std.Io,
    alloc: Allocator,
    stream: std.Io.net.Stream,
    session: *Server,
) std.Io.Cancelable!void {
    handleClient(io, alloc, stream, session) catch |err| switch (err) {
        else => {
            log.warn("Client failure: {}", .{err});
            return;
        },
    };
}

pub fn main(init: std.process.Init) !void {
    const alloc = init.gpa;
    const io = init.io;

    const address = try std.Io.net.IpAddress.parse(listen_ip_addr, listen_port);

    log.info("Server listening at {s}:{}", .{ listen_ip_addr, listen_port });
    var server = try address.listen(io, .{});
    defer server.deinit(io);

    var group: std.Io.Group = .init;
    defer group.cancel(io);

    var session = Server.init(io, alloc);

    while (true) {
        const stream = try server.accept(io);
        group.async(io, handleClientTask, .{ io, alloc, stream, &session });
    }
}
