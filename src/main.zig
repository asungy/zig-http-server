const std = @import("std");
const net = std.net;

fn get_url(request: []u8) ?[]const u8 {
    var it = std.mem.split(u8, request, " ");
    _ = it.next();
    return it.next();
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    const addr = "127.0.0.1";
    const port = 4221;
    const address = try net.Address.resolveIp(addr, port);
    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();
    try stdout.print("Listening on {s}:{d}\n", .{addr, port});

    var conn = try listener.accept();
    var buffer: [1024]u8 = undefined;
    _ = try conn.stream.reader().readAll(&buffer);

    const url = get_url(&buffer).?;
    if (std.mem.eql(u8, url, "/")) {
        try stdout.print("OK", .{});
        try conn.stream.writer().writeAll("HTTP/1.1 200 OK\r\n\r\n");
    } else {
        try stdout.print("Not Found", .{});
        try conn.stream.writer().writeAll("HTTP/1.1 404 Not Found\r\n\r\n");
    }
}
