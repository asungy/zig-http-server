const std = @import("std");
const http = @import("http.zig");
pub const Request = @This();

method: http.Method,
target: []const u8,
version: http.Version,

pub const ParseError = error {
    NoMethod,
    NoTarget,
    NoHttpVersion,
};

pub fn parse(raw_request: []const u8) ParseError!Request {
    var lines = std.mem.split(u8, raw_request, "\r\n");
    const start_line = lines.next().?;
    var start_line_iter = std.mem.split(u8, start_line, " ");

    var method: ?http.Method = null;
    var target: ?[]const u8 = null;
    var version: ?http.Version = null;
    for (0..3) |i| {
        const s = start_line_iter.next() orelse break;
        switch (i) {
            0 => method = http.Method.fromString(s),
            1 => target = s,
            2 => version = http.Version.fromString(s),
            else => break,
        }
    }

    return Request {
        .method = method orelse return ParseError.NoMethod,
        .target = target orelse return ParseError.NoTarget,
        .version = version orelse return ParseError.NoHttpVersion,
    };
}

test "http request parses into Request struct" {
    const request = try Request.parse("GET /echo/abc HTTP/1.1\r\nHost: localhost:4221\r\nUser-Agent: curl/7.64.1\r\nAccept: */*\r\n\r\n");
    try std.testing.expectEqual(http.Method.GET, request.method);
    try std.testing.expectEqualStrings("/echo/abc", request.target);
}
