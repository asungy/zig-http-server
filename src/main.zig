const std = @import("std");
const net = std.net;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    const addr = "127.0.0.1";
    const port = 4221;
    const address = try net.Address.resolveIp(addr, port);
    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();
    try stdout.print("Listening on {s}:{d}", .{addr, port});

    const bytes = "HTTP/1.1 200 OK\r\n\r\n";
    var conn = try listener.accept();
    try conn.stream.writer().writeAll(bytes);
}
