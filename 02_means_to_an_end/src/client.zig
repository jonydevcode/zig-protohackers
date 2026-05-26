const std = @import("std");
const log = std.log;
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;

const server_ip_addr = "127.0.0.1";
const server_port: u16 = 59111;
const buf_size: usize = 4096;
const msg_bytes = 9;

pub fn main(init: std.process.Init) !void {
    var stdout = std.Io.File.stdout().writer(init.io, &.{});

    const address = try std.Io.net.IpAddress.parse(server_ip_addr, server_port);

    log.info("Connecting to server at {s}:{}", .{ server_ip_addr, server_port });

    var client = try address.connect(init.io, .{
        .mode = .stream,
        .protocol = .tcp,
    });
    defer client.close(init.io);

    log.info("Connected.", .{});

    var reader_buf: [buf_size]u8 = undefined;
    var reader = client.reader(init.io, &reader_buf);
    var writer_buf: [buf_size]u8 = undefined;
    var writer = client.writer(init.io, &writer_buf);

    while (true) {
        var stdin_buffer: [buf_size]u8 = undefined;
        var stdin = std.Io.File.stdin().readerStreaming(init.io, &stdin_buffer);
        if (try stdin.interface.takeDelimiter('\n')) |input| {
            var it = std.mem.tokenizeScalar(u8, input, ' ');
            const msgtype = it.next() orelse {
                std.debug.print("Invalid input!\n", .{});
                continue;
            };
            const arg1 = it.next() orelse {
                std.debug.print("Invalid input!\n", .{});
                continue;
            };
            const arg2 = it.next() orelse {
                std.debug.print("Invalid input!\n", .{});
                continue;
            };
            switch (msgtype[0]) {
                'I' => {
                    var out_buf: [msg_bytes]u8 = undefined;
                    out_buf[0] = msgtype[0];
                    const timestamp = std.fmt.parseInt(i32, arg1, 10) catch {
                        std.debug.print("Invalid input!\n", .{});
                        continue;
                    };
                    const price = std.fmt.parseInt(i32, arg2, 10) catch {
                        std.debug.print("Invalid input!\n", .{});
                        continue;
                    };
                    std.mem.writeInt(i32, out_buf[1..5], timestamp, .big);
                    std.mem.writeInt(i32, out_buf[5..9], price, .big);
                    try writer.interface.writeAll(&out_buf);
                    try writer.interface.flush();
                },
                'Q' => {
                    var out_buf: [msg_bytes]u8 = undefined;
                    out_buf[0] = msgtype[0];
                    const mintime = std.fmt.parseInt(i32, arg1, 10) catch {
                        std.debug.print("Invalid input!\n", .{});
                        continue;
                    };
                    const maxtime = std.fmt.parseInt(i32, arg2, 10) catch {
                        std.debug.print("Invalid input!\n", .{});
                        continue;
                    };
                    std.mem.writeInt(i32, out_buf[1..5], mintime, .big);
                    std.mem.writeInt(i32, out_buf[5..9], maxtime, .big);
                    try writer.interface.writeAll(&out_buf);
                    try writer.interface.flush();

                    var in_buf: [4]u8 = undefined;
                    try reader.interface.readSliceAll(&in_buf);
                    const mean = std.mem.readInt(i32, &in_buf, .big);
                    try stdout.interface.print("{d}\n", .{mean});
                },
                else => {
                    std.debug.print("Invalid input!\n", .{});
                    continue;
                },
            }
        }
    }
}
