const std = @import("std");
const log = std.log;
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;

const server_ip_addr = "127.0.0.1";
const server_port: u16 = 59111;
const buf_size: usize = 4096;
const msg_bytes = 9;

fn receive_loop(allocator: Allocator, io: std.Io, stream: std.Io.net.Stream) !void {
    var stdout = std.Io.File.stdout().writer(io, &.{});
    var reader_buf: [buf_size]u8 = undefined;
    var net_reader = stream.reader(io, &reader_buf);

    while (true) {
        var buf: std.Io.Writer.Allocating = .init(allocator);
        defer buf.deinit();
        _ = net_reader.interface.streamDelimiter(&buf.writer, '\n') catch |err| switch (err) {
            error.EndOfStream => {
                try stdout.interface.print("You are disconnected.\n", .{});
                return;
            },
            else => return err,
        };
        net_reader.interface.toss(1); // skip the \n
        try stdout.interface.writeAll(buf.writer.buffered());
        try stdout.interface.writeByte('\n');
        try stdout.flush();
    }
}

fn receive_loop_task(allocator: Allocator, io: std.Io, stream: std.Io.net.Stream) std.Io.Cancelable!void {
    receive_loop(allocator, io, stream) catch |err| {
        log.err("Error in loop: {any}", .{err});
    };
}

pub fn main(init: std.process.Init) !void {
    var stdout = std.Io.File.stdout().writer(init.io, &.{});
    const allocator = init.gpa;

    const address = try std.Io.net.IpAddress.parse(server_ip_addr, server_port);

    try stdout.interface.print("Connecting to server at {s}:{}\n", .{ server_ip_addr, server_port });

    var client = address.connect(init.io, .{
        .mode = .stream,
        .protocol = .tcp,
    }) catch |err| switch (err) {
        error.ConnectionRefused => {
            try stdout.interface.print("Connection was refused.\n", .{});
            return;
        },
        else => return err,
    };
    defer client.close(init.io);

    try stdout.interface.print("Connected.\n", .{});

    var group: std.Io.Group = .init;
    defer group.cancel(init.io);
    group.async(init.io, receive_loop_task, .{ allocator, init.io, client });

    var writer_buf: [buf_size]u8 = undefined;
    var writer = client.writer(init.io, &writer_buf);

    while (true) {
        var stdin_buffer: [buf_size]u8 = undefined;
        var stdin = std.Io.File.stdin().readerStreaming(init.io, &stdin_buffer);
        if (try stdin.interface.takeDelimiter('\n')) |input| {
            if (input.len <= 0) continue;
            try writer.interface.writeAll(input);
            try writer.interface.writeByte('\n');
            try writer.interface.flush();
        }
    }
}
