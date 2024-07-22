const std = @import("std");
const http = @import("http.zig");
const Allocator = std.mem.Allocator;

pub const Response = struct {
    arena: std.heap.ArenaAllocator,
    version: http.Version,
    status: http.Status,
    headers: std.StringHashMap([]const u8),
    body: ?[]const u8,

    pub fn init() !Response {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        return Response {
            .arena = arena,
            .version = http.Version.Http_1_1,
            .status  = http.Status.OK,
            .headers = std.StringHashMap([]const u8).init(arena.allocator()),
            .body = null,
        };
    }

    pub fn deinit(self: *Response) void {
        self.arena.deinit();
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
        var buffer: [5]u8 = [_]u8{0} ** 5;
        _ = std.fmt.formatIntBuf(&buffer, size, 10, .lower, .{});
        try self.addHeader("Content-Length", &buffer);
    }

    pub fn setBody(self: *Response, body: []const u8) !void {
        self.body = body;
    }
};

test "successfully constructing Response struct" {
    var response = try Response.init();
    defer response.deinit();

    try response.setContentLength(42);
    const contentLength = response.headers.get("Content-Length").?;
    try std.testing.expect(std.mem.eql(u8, contentLength, "42"));
}
