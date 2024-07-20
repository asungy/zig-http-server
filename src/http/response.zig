const std = @import("std");
const http = @import("http.zig");
const Allocator = std.mem.Allocator;

pub const Response = struct {
    version: http.Version,
    status: http.Status,
    headers: std.StringHashMap([]const u8),
    body: []const u8,

    pub fn init(allocator: Allocator) Response {
        return Response {
            .version = http.Version.Http_1_1,
            .headers = std.StringHashMap([]const u8).init(allocator),
        };
    }
};

test "successfully constructing Response struct" {
}
