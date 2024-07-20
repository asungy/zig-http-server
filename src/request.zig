const std = @import("std");

const Method = enum {
    GET,

    fn fromString(str: []const u8) ?Method {
        return if (std.mem.eql(u8, str, "GET")) {
            return Method.GET;
        } else {
            return null;
        };
    }
};

const HttpVersion = enum {
    Http_1_1,

    fn fromString(str: []const u8) ?HttpVersion {
        return if (std.mem.eql(u8, str, "HTTP/1.1")) {
            return HttpVersion.Http_1_1;
        } else {
            return null;
        };
    }
};

const ParseError = error {
    NoMethod,
    NoTarget,
    NoHttpVersion,
};

const Request = struct {
    method: Method,
    target: []const u8,
    version: HttpVersion,

    pub fn parse(raw_request: []const u8) ParseError!Request {
        var lines = std.mem.split(u8, raw_request, "\r\n");
        const start_line = lines.next().?;
        var start_line_iter = std.mem.split(u8, start_line, " ");

        var method: ?Method = null;
        var target: ?[]const u8 = null;
        var version: ?HttpVersion = null;
        for (0..3) |i| {
            const s = start_line_iter.next() orelse break;
            switch (i) {
                0 => method = Method.fromString(s),
                1 => target = s,
                2 => version = HttpVersion.fromString(s),
                else => break,
            }
        }

        return Request {
            .method = method orelse return ParseError.NoMethod,
            .target = target orelse return ParseError.NoTarget,
            .version = version orelse return ParseError.NoHttpVersion,
        };
    }
};

test "http request parses into Request struct" {
    const request = try Request.parse("GET /echo/abc HTTP/1.1\r\nHost: localhost:4221\r\nUser-Agent: curl/7.64.1\r\nAccept: */*\r\n\r\n");
    try std.testing.expect(request.method == Method.GET);
    try std.testing.expect(std.mem.eql(u8, request.target, "/echo/abc"));
}
