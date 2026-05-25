const std = @import("std");
const log = std.log;
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;

const listen_ip_addr = "0.0.0.0";
const listen_port: u16 = 59111;
const buf_size: usize = 4096;

const Request = struct {
    method: []const u8,
    number: i256,

    /// If json parsing fails, or any conforming rules fail, will return null
    pub fn parseFromJson(allocator: Allocator, s: []const u8) !?Request {
        // First, deserialize into std.json.Value so I can inspect the types
        var parsed = std.json.parseFromSlice(std.json.Value, allocator, s, .{}) catch return null;
        defer parsed.deinit();

        var method_actual: []const u8 = undefined;
        var number_actual: i256 = undefined;

        const root = parsed.value;

        const method = root.object.get("method") orelse return null;
        switch (method) {
            .string => |v| {
                if (!std.mem.eql(u8, v, "isPrime")) {
                    std.debug.print("Malformed. `method` is not 'isPrime'.\n", .{});
                    return null;
                }
                // CONFORMED:
                method_actual = try allocator.dupe(u8, v);
            },
            else => {
                std.debug.print("Malformed. `method` is not a string.\n", .{});
                return null;
            },
        }
        const number = root.object.get("number") orelse return null;
        switch (number) {
            .integer => |i| number_actual = i,
            .float => return error.NumberIsFloat,
            .number_string => |numstr| {
                number_actual = std.fmt.parseInt(i256, numstr, 10) catch return null;
                // _ = numstr;
            },
            else => {
                std.debug.print("Malformed. `number` is not an integer or float.\n", .{});
                return null;
            },
        }

        // All tests passed, conform to the Request struct
        var parsed_request = std.json.parseFromSlice(
            Request,
            allocator,
            s,
            .{
                .allocate = .alloc_always,
                .ignore_unknown_fields = true,
                .parse_numbers = false,
            },
        ) catch return null;
        defer parsed_request.deinit();

        const request = parsed_request.value;

        return request;
    }

    pub fn deinit(self: *Request, allocator: Allocator) void {
        allocator.free(self.method);
    }
};

const Response = struct {
    method: []const u8,
    prime: bool,
};

fn isPrime(n: i256) bool {
    if (n <= 1) return false;
    if (n == 2) return true;
    if (@mod(n, 2) == 0) return false;

    var d: i256 = 3;
    while (d <= @divTrunc(n, d)) : (d += 2) {
        if (@mod(n, d) == 0) return false;
    }
    return true;
}

fn handleClient(io: std.Io, alloc: Allocator, stream: std.Io.net.Stream) !void {
    defer stream.close(io);

    log.info("Client connected: {f}", .{stream.socket.address});

    var readbuf: [buf_size]u8 = undefined;
    var stream_reader = stream.reader(io, &readbuf);

    var writebuf: [buf_size]u8 = undefined;
    var stream_writer = stream.writer(io, &writebuf);

    while (true) {
        std.debug.print("Reading from stream_reader.\n", .{});
        var full_msg = std.Io.Writer.Allocating.init(alloc);
        defer full_msg.deinit();

        _ = stream_reader.interface.streamDelimiter(&full_msg.writer, '\n') catch |err| switch (err) {
            error.EndOfStream => break,
            else => break,
        };
        stream_reader.interface.toss(1); // to skip the \n

        std.debug.print("Received over the pipe:\n{s}\n", .{full_msg.writer.buffered()});

        const request = Request.parseFromJson(alloc, full_msg.writer.buffered()) catch |err| switch (err) {
            error.NumberIsFloat => {
                // send back false, since floats aren't prime
                try std.json.Stringify.value(
                    Response{ .method = "isPrime", .prime = false },
                    .{ .whitespace = .minified },
                    &stream_writer.interface,
                );
                try stream_writer.interface.writeByte('\n');
                try stream_writer.interface.flush();
                break;
            },
            else => {
                // send back a single malformed response and disconnect the client
                try stream_writer.interface.writeAll("{}\n");
                try stream_writer.interface.flush();
                break;
            },
        } orelse {

            // send back a single malformed response and disconnect the client
            try stream_writer.interface.writeAll("{}\n");
            try stream_writer.interface.flush();
            break;
        };

        const response = Response{
            .method = "isPrime",
            .prime = isPrime(request.number),
        };
        std.debug.print("Response constructed, prime = {}\n", .{response.prime});

        try std.json.Stringify.value(
            response,
            .{
                .whitespace = .minified,
            },
            &stream_writer.interface,
        );
        std.debug.print("Json serialized.\n", .{});
        try stream_writer.interface.writeByte('\n');

        try stream_writer.interface.flush();
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

test "Correctness of prime number test" {
    try expect(!isPrime(0));
    try expect(!isPrime(1));
    try expect(isPrime(2));
    try expect(isPrime(3));
    try expect(isPrime(5));
    try expect(isPrime(7));
    try expect(isPrime(1307));
    try expect(!isPrime(1308));
    try expect(!isPrime(1309));
}
