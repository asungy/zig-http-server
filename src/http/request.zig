const std = @import("std");
const http = @import("http.zig");
pub const Request = @This();

method: http.Method,
target: []const u8,
version: http.Version,
headers: std.StringHashMap([]const u8),

pub const ParseError = error {
    NoMethod,
    NoTarget,
    NoHttpVersion,
    AllocationError,
    MalformedRequest,
};

pub fn parse(raw_request: []const u8, allocator: std.mem.Allocator) ParseError!Request {
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

    var headers = std.StringHashMap([]const u8).init(allocator);
    while (lines.next()) |header| {
        // Handles the double CRLF at the end of the headers section.
        if (std.mem.eql(u8, "", header)) break;

        var it = std.mem.split(u8, header, ": ");
        const key = if (it.next()) |v| v else return ParseError.MalformedRequest;
        const value = if (it.next()) |v| v else return ParseError.MalformedRequest;
        headers.put(key, value) catch return ParseError.AllocationError;
    }

    return Request {
        .method = method orelse return ParseError.NoMethod,
        .target = target orelse return ParseError.NoTarget,
        .version = version orelse return ParseError.NoHttpVersion,
        .headers = headers,
    };
}

pub fn deinit(self: *Request) void {
    self.headers.deinit();
}

test "http request parses into Request struct" {
    var request = try Request.parse(
        "GET /echo/abc HTTP/1.1\r\nHost: localhost:4221\r\nUser-Agent: curl/7.64.1\r\nAccept: */*\r\n\r\n",
        std.testing.allocator,
    );
    defer request.deinit();

    try std.testing.expectEqual(http.Method.GET, request.method);
    try std.testing.expectEqualStrings("/echo/abc", request.target);
    try std.testing.expectEqualStrings("localhost:4221", request.headers.get("Host").?);
    try std.testing.expectEqualStrings("curl/7.64.1", request.headers.get("User-Agent").?);
    try std.testing.expectEqualStrings("*/*", request.headers.get("Accept").?);
}
