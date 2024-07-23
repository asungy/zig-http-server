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

    pub fn setContentLength(self: *Response, size: u16) !void {
        if (size < 10) {
            var buffer: [1]u8 = [_]u8{0};
            _ = std.fmt.formatIntBuf(&buffer, size, 10, .lower, .{});
            try self.addHeader("Content-Length", &buffer);
        } else if (size < 100) {
            var buffer: [2]u8 = [_]u8{0} ** 2;
            _ = std.fmt.formatIntBuf(&buffer, size, 10, .lower, .{});
            try self.addHeader("Content-Length", &buffer);
        } else if (size < 1000) {
            var buffer: [3]u8 = [_]u8{0} ** 3;
            _ = std.fmt.formatIntBuf(&buffer, size, 10, .lower, .{});
            try self.addHeader("Content-Length", &buffer);
        } else if (size < 10000) {
            var buffer: [4]u8 = [_]u8{0} ** 4;
            _ = std.fmt.formatIntBuf(&buffer, size, 10, .lower, .{});
            try self.addHeader("Content-Length", &buffer);
        } else {
            var buffer: [5]u8 = [_]u8{0} ** 5;
            _ = std.fmt.formatIntBuf(&buffer, size, 10, .lower, .{});
            try self.addHeader("Content-Length", &buffer);
        }
    }

    pub fn setBody(self: *Response, body: []const u8) !void {
        const allocator = self.arena.allocator();
        const buffer = try allocator.alloc(u8, body.len);
        std.mem.copyForwards(u8, buffer, body);
        self.body = buffer;
        try self.setContentLength(@intCast(body.len));
    }
};

test "successfully constructing Response struct" {
    var response = try Response.init(std.testing.allocator);
    defer response.deinit();

    try response.setContentType(http.ContentType.TextPlain);
    const contentType = response.headers.get("Content-Type").?;
    try std.testing.expect(std.mem.eql(u8, contentType, http.ContentType.TextPlain.toString()));

    try response.setBody("Hello World");
    try std.testing.expect(std.mem.eql(u8, response.body.?, "Hello World"));

    const contentLength = response.headers.get("Content-Length").?;
    try std.testing.expect(std.mem.eql(u8, contentLength, "11"));
}

test "one-digit content length" {
    var response = try Response.init(std.testing.allocator);
    defer response.deinit();

    try response.setContentLength(2);
    const contentLength = response.headers.get("Content-Length").?;
    try std.testing.expect(std.mem.eql(u8, contentLength, "2"));
}

test "two-digit content length" {
    var response = try Response.init(std.testing.allocator);
    defer response.deinit();

    try response.setContentLength(42);
    const contentLength = response.headers.get("Content-Length").?;
    try std.testing.expect(std.mem.eql(u8, contentLength, "42"));
}

test "three-digit content length" {
    var response = try Response.init(std.testing.allocator);
    defer response.deinit();

    try response.setContentLength(163);
    const contentLength = response.headers.get("Content-Length").?;
    try std.testing.expect(std.mem.eql(u8, contentLength, "163"));
}

test "four-digit content length" {
    var response = try Response.init(std.testing.allocator);
    defer response.deinit();

    try response.setContentLength(9876);
    const contentLength = response.headers.get("Content-Length").?;
    try std.testing.expect(std.mem.eql(u8, contentLength, "9876"));
}

test "five-digit content length" {
    var response = try Response.init(std.testing.allocator);
    defer response.deinit();

    try response.setContentLength(65535);
    const contentLength = response.headers.get("Content-Length").?;
    try std.testing.expect(std.mem.eql(u8, contentLength, "65535"));
}
