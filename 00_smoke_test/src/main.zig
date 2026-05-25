const std = @import("std");
const log = std.log;

const listen_ip_addr = "0.0.0.0";
const listen_port: u16 = 59111;
const buf_size: usize = 4096;

pub fn main(init: std.process.Init) !void {
    // const allocator = init.gpa;
    const io = init.io;

    const address = try std.Io.net.IpAddress.parse(listen_ip_addr, listen_port);

    log.info("Server listening at {s}:{}", .{ listen_ip_addr, listen_port });
    var server = try address.listen(io, .{});
    defer server.deinit(io);

    while (true) {
        var stream = try server.accept(io);
        defer stream.close(io);

        log.info("Client connected: {f}", .{stream.socket.address});

        var readbuf: [buf_size]u8 = undefined;
        var stream_reader = stream.reader(io, &readbuf);

        var writebuf: [buf_size]u8 = undefined;
        var stream_writer = stream.writer(io, &writebuf);

        _ = try stream_reader.interface.streamRemaining(&stream_writer.interface);

        try stream_writer.interface.flush();
    }
}
