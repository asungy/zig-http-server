const std = @import("std");
const http = @import("http.zig");
const Allocator = std.mem.Allocator;

pub const Response = struct {
    arena: std.heap.ArenaAllocator,
    version: http.Version,
    status: http.Status,
    headers: std.StringHashMap([]const u8),
    body: ?[]const u8,

    pub fn init(allocator: std.mem.Allocator) !Response {
        const arena = std.heap.ArenaAllocator.init(allocator);
        return Response {
            .arena = arena,
            .version = http.Version.Http_1_1,
            .status  = http.Status.OK,
            .headers = std.StringHashMap([]const u8).init(allocator),
            .body = null,
        };
    }

    pub fn deinit(self: *Response) void {
        _ = self.arena.reset(.free_all);
        self.headers.deinit();
    }

    pub fn setStatus(self: *Response, status: http.Status) void {
        self.status = status;
    }

    pub fn addHeader(self: *Response, key: []const u8, value: []const u8) !void {
        const allocator = self.arena.allocator();
        const buffer = try allocator.alloc(u8, value.len);
        std.mem.copyForwards(u8, buffer, value);
        try self.headers.put(key, buffer);
    }

    pub fn setContentType(self: *Response, content_type: http.ContentType) !void {
        try self.addHeader("Content-Type", content_type.toString());
    }

    pub fn setContentLength(self: *Response, size: usize) !void {
        const allocator = self.arena.allocator();
        var length: usize = 0;
        var _size = size;
        while (_size > 0) {
            _size /= 10;
            length += 1;
        }
        const buffer = try allocator.alloc(u8, length);
        _ = std.fmt.formatIntBuf(buffer, size, 10, .lower, .{});
        try self.addHeader("Content-Length", buffer);
    }

    pub fn setBody(self: *Response, body: []const u8) !void {
        const allocator = self.arena.allocator();
        const buffer = try allocator.alloc(u8, body.len);
        std.mem.copyForwards(u8, buffer, body);
        self.body = buffer;
        try self.setContentLength(@intCast(body.len));
    }

    pub fn toBytes(self: *Response, allocator: std.mem.Allocator) ![]const u8 {
        const statusLine = try self.statusLineBytes(allocator);
        defer allocator.free(statusLine);

        const buffer = try allocator.alloc(u8, statusLine.len);
        std.mem.copyForwards(u8, buffer, statusLine);

        return buffer;
    }

    fn statusLineBytes(self: *Response, allocator: std.mem.Allocator) ![]const u8 {
        // Calculating size of status line.
        const space = " ";
        const crlf = "\r\n";
        const version = self.version.toString();
        var statusCode: [3]u8 = undefined;
        _ = std.fmt.formatIntBuf(&statusCode, self.status.code(), 10, .lower, .{});
        const status = self.status.toString();
        const size = version.len + space.len
            + statusCode.len + space.len
            + status.len + crlf.len;

        var counter: usize = 0;
        const buffer = try allocator.alloc(u8, size);

        // Copying HTTP version.
        std.mem.copyForwards(u8, buffer[counter..], version);
        counter += version.len;
        std.mem.copyForwards(u8, buffer[counter..], space);
        counter += space.len;

        // Copying status code.
        std.mem.copyForwards(u8, buffer[counter..], &statusCode);
        counter += statusCode.len;
        std.mem.copyForwards(u8, buffer[counter..], space);
        counter += space.len;

        // Copying status.
        std.mem.copyForwards(u8, buffer[counter..], status);
        counter += status.len;
        std.mem.copyForwards(u8, buffer[counter..], crlf);

        return buffer;
    }
    //
    // fn headersBytes(self: *Response, allocator: std.mem.Allocator) ![]const u8 {
    //
    // }
};

test "Response struct to bytes" {
    var response = try Response.init(std.testing.allocator);
    defer response.deinit();

    try response.setContentType(http.ContentType.TextPlain);
    const contentType = response.headers.get("Content-Type").?;
    try std.testing.expect(std.mem.eql(u8, contentType, http.ContentType.TextPlain.toString()));

    try response.setBody("Hello World");
    try std.testing.expect(std.mem.eql(u8, response.body.?, "Hello World"));

    const contentLength = response.headers.get("Content-Length").?;
    try std.testing.expect(std.mem.eql(u8, contentLength, "11"));

    const bytes = try response.toBytes(std.testing.allocator);
    defer std.testing.allocator.free(bytes);

    std.log.warn("{s}", .{bytes});
    // try std.testing.expect(std.mem.eql(u8, bytes, "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 11\r\n\r\nHello World"));
    try std.testing.expect(std.mem.eql(u8, bytes, "HTTP/1.1 200 OK\r\n"));
}

test "setting content length" {
    var response = try Response.init(std.testing.allocator);
    defer response.deinit();

    try response.setContentLength(65535);
    const contentLength = response.headers.get("Content-Length").?;
    try std.testing.expect(std.mem.eql(u8, contentLength, "65535"));
}
