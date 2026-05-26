const std = @import("std");
const ordered = @import("ordered");
const log = std.log;
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;

const listen_ip_addr = "0.0.0.0";
const listen_port: u16 = 59111;
const buf_size: usize = 4096;
const b_tree_branch_factor = 4;
const msg_bytes = 9;

fn intCompare(lhs: i32, rhs: i32) std.math.Order {
    return std.math.order(lhs, rhs);
}

fn handleClient(io: std.Io, alloc: Allocator, stream: std.Io.net.Stream) !void {
    defer stream.close(io);

    log.info("Client connected: {f}", .{stream.socket.address});

    var readbuf: [buf_size]u8 = undefined;
    var reader = stream.reader(io, &readbuf);

    var writebuf: [buf_size]u8 = undefined;
    var writer = stream.writer(io, &writebuf);

    var pricemap = ordered.BTreeMap(i32, i32, intCompare, b_tree_branch_factor).init(alloc);
    defer pricemap.deinit();

    while (true) {
        // 1. Read 9 bytes from the stream
        // 2. Parse the 9 bytes into 3 request fields
        // 3a. Insert - Insert into pricemap
        // 3b. Query - Retrieve the prices in the period, calc average, send response

        var msg_buf: [msg_bytes]u8 = undefined;
        reader.interface.readSliceAll(&msg_buf) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };

        switch (msg_buf[0]) {
            'I' => {
                const timestamp: i32 = std.mem.readInt(i32, msg_buf[1..5], .big);
                const price: i32 = std.mem.readInt(i32, msg_buf[5..9], .big);
                try pricemap.put(timestamp, price);
            },
            'Q' => {
                const mintime: i32 = std.mem.readInt(i32, msg_buf[1..5], .big);
                const maxtime: i32 = std.mem.readInt(i32, msg_buf[5..9], .big);
                var count: i64 = 0;
                var total: i64 = 0;
                var it = try pricemap.iterator();
                defer it.deinit();
                while (try it.next()) |entry| {
                    if (mintime <= entry.key and entry.key <= maxtime) {
                        count += 1;
                        total += entry.value;
                    }
                }
                const mean: i32 = if (count > 0) @intCast(@divTrunc(total, count)) else 0;

                // send the mean to the client
                var response_buf: [4]u8 = undefined;
                std.mem.writeInt(i32, &response_buf, mean, .big);
                try writer.interface.writeAll(&response_buf);
                try writer.interface.flush();
            },
            else => return error.InvalidMessage,
        }
    }
}

fn handleClientTask(
    io: std.Io,
    alloc: Allocator,
    stream: std.Io.net.Stream,
) std.Io.Cancelable!void {
    handleClient(io, alloc, stream) catch |err| switch (err) {
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

    while (true) {
        const stream = try server.accept(io);
        group.async(io, handleClientTask, .{ io, alloc, stream });
    }
}
