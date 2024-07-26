const Request = @import("http/request.zig").Request;
const Response = @import("http/response.zig").Response;
const Server = @import("server.zig").Server;
const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var server = try Server.init("127.0.0.1", 4221, allocator);
    defer server.deinit();

    // server.addRoute("/echo/{str}", struct { fn cb(request: Request) Response {
    //
    // }}.cb);

    return server.run();
}
