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

    pub fn serialize(self: *Response, allocator: std.mem.Allocator) ![]const u8 {
        const statusLine = try self.statusLineBytes(allocator);
        defer allocator.free(statusLine);

        const headers = try self.headersBytes(allocator);
        defer allocator.free(headers);

        const bodyLength = if (self.body) |body| body.len else 0;
        const buffer = try allocator.alloc(u8, statusLine.len + headers.len + bodyLength);
        var counter: usize = 0;
        std.mem.copyForwards(u8, buffer, statusLine);
        counter += statusLine.len;
        std.mem.copyForwards(u8, buffer[counter..], headers);
        counter += headers.len;
        if (bodyLength > 0) {
            std.mem.copyForwards(u8, buffer[counter..], self.body.?);
        }

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

    fn headersBytes(self: *Response, allocator: std.mem.Allocator) ![]const u8 {
        var it = self.headers.iterator();
        var size: usize = 0;
        const delim = ": ";
        const crlf = "\r\n";
        // Calculating buffer size.
        while (it.next()) |kv| {
             size += kv.key_ptr.len + delim.len + kv.value_ptr.len + crlf.len;
        }
        size += crlf.len;
        const buffer = try allocator.alloc(u8, size);

        // Copying headers to buffer.
        it = self.headers.iterator();
        var counter: usize = 0;
        while (it.next()) |kv| {
            std.mem.copyForwards(u8, buffer[counter..], kv.key_ptr.*);
            counter += kv.key_ptr.len;

            std.mem.copyForwards(u8, buffer[counter..], delim);
            counter += delim.len;

            std.mem.copyForwards(u8, buffer[counter..], kv.value_ptr.*);
            counter += kv.value_ptr.len;

            std.mem.copyForwards(u8, buffer[counter..], crlf);
            counter += crlf.len;
        }
        std.mem.copyForwards(u8, buffer[counter..], crlf);
        counter += crlf.len;

        return buffer;
    }
};

test "Response struct serialization" {
    var response = try Response.init(std.testing.allocator);
    defer response.deinit();

    try response.setContentType(http.ContentType.TextPlain);
    const contentType = response.headers.get("Content-Type").?;
    try std.testing.expect(std.mem.eql(u8, contentType, http.ContentType.TextPlain.toString()));

    try response.setBody("Hello World");
    try std.testing.expect(std.mem.eql(u8, response.body.?, "Hello World"));

    const contentLength = response.headers.get("Content-Length").?;
    try std.testing.expect(std.mem.eql(u8, contentLength, "11"));

    const bytes = try response.serialize(std.testing.allocator);
    defer std.testing.allocator.free(bytes);

    try std.testing.expect(std.mem.eql(u8, bytes, "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 11\r\n\r\nHello World"));
}

test "Response serialization without body" {
    var response = try Response.init(std.testing.allocator);
    defer response.deinit();

    response.setStatus(http.Status.NotFound);
    try std.testing.expect(response.status == http.Status.NotFound);

    try response.setContentType(http.ContentType.TextPlain);
    const contentType = response.headers.get("Content-Type").?;
    try std.testing.expect(std.mem.eql(u8, contentType, http.ContentType.TextPlain.toString()));

    const bytes = try response.serialize(std.testing.allocator);
    defer std.testing.allocator.free(bytes);

    try std.testing.expect(std.mem.eql(u8, bytes, "HTTP/1.1 404 Not Found\r\nContent-Type: text/plain\r\n\r\n"));
}

test "setting content length" {
    var response = try Response.init(std.testing.allocator);
    defer response.deinit();

    try response.setContentLength(65535);
    const contentLength = response.headers.get("Content-Length").?;
    try std.testing.expect(std.mem.eql(u8, contentLength, "65535"));
}
