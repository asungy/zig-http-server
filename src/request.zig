const std = @import("std");

const Method = enum {
    GET,

    fn matchString(str: []const u8) ?Method {
        return if (std.mem.eql(u8, str, "GET")) {
            return Method.GET;
        } else {
            return null;
        };
    }
};

const ParseError = error {
    UnknownMethod,
};

const Request = struct {
    method: Method,

    pub fn parse(raw_request: []const u8) ParseError!Request {
        var lines = std.mem.split(u8, raw_request, "\r\n");
        const start_line = lines.next().?;
        var start_line_iter = std.mem.split(u8, start_line, " ");

        var method: ?Method = null;
        for (0..3) |i| {
            const s = start_line_iter.next() orelse break;
            switch (i) {
                0 => method = Method.matchString(s),
                else => break,
            }
        }

        return Request {
            .method = method orelse return ParseError.UnknownMethod,
        };
    }
};

test "http request parses into Request struct" {
    const request = try Request.parse("GET /echo/abc HTTP/1.1\r\nHost: localhost:4221\r\nUser-Agent: curl/7.64.1\r\nAccept: */*\r\n\r\n");
    try std.testing.expect(request.method == Method.GET);
}
