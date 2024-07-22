const std = @import("std");
const Server = @import("server.zig").Server;
const Response = @import("http/response.zig").Response;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var response = try Response.init(allocator);
    defer response.deinit();

    try response.setContentLength(42);
    const contentLength = response.headers.get("Content-Length").?;
    std.debug.print("{s}", .{contentLength});
    if (std.mem.eql(u8, contentLength, "42")) {
        std.debug.print("Matched", .{});
    } else {
        std.debug.print("Not matched", .{});
    }
    // try std.testing.expect(std.mem.eql(u8, contentLength, "42"));

}
