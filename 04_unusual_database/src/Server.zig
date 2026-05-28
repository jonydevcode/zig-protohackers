const Self = @This();
const std = @import("std");
const Database = @import("Database.zig");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const net = std.Io.net;

io: Io,
allocator: Allocator,
host: []const u8,
port: u16,

db: Database,

pub fn init(
    io: Io,
    allocator: Allocator,
    host: []const u8,
    port: u16,
) Self {
    return Self{
        .io = io,
        .allocator = allocator,
        .host = host,
        .port = port,
        .db = Database.init(allocator, io),
    };
}

pub fn run(self: *Self) !void {
    const addr = try net.IpAddress.parse(self.host, self.port);
    const sock = try addr.bind(self.io, .{
        .mode = .dgram,
        .protocol = .udp,
    });
    defer sock.close(self.io);

    std.debug.print("Server listening on {f}\n", .{addr});

    var buf: [4096]u8 = undefined;
    var outbuf: [4096]u8 = undefined;

    while (true) {
        const message = try sock.receive(self.io, &buf);
        const data = message.data;

        if (std.mem.indexOfScalar(data, data, '=')) |i| {
            const key = data[0..i];
            const val = data[i + 1 ..];
            self.db.put(key, val);
        } else {
            const key = data;
            const val = try self.db.get(key) orelse "";
            const response = std.fmt.bufPrint(&outbuf, "{key}={val}", .{ key, val });
            try sock.send(self.io, &message.from, response);
        }
    }
}
