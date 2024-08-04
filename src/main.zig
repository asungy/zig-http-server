const Request = @import("http/request.zig").Request;
const Response = @import("http/response.zig").Response;
const Http = @import("http/http.zig");
const Server = @import("server.zig").Server;
const Context = @import("router.zig").Context;
const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var server = try Server.init("127.0.0.1", 4221, allocator);
    defer server.deinit();
    try server.addRoute("/", struct {
        fn f(_: Context, _: Request, _allocator: std.mem.Allocator) Response {
            var response = Response.init(_allocator);
            response.setStatus(Http.Status.OK);
            response.setContentType(Http.ContentType.TextPlain) catch return response;
            return response;
        }
    }.f);

    try server.addRoute("/echo/{echo}", struct {
        fn f(_context: Context, _: Request, _allocator: std.mem.Allocator) Response {
            var response = Response.init(_allocator);
            response.setStatus(Http.Status.NotFound);
            response.setContentType(Http.ContentType.TextPlain) catch return response;

            if (_context.capture_map.get("echo")) |echo| {
                response.setBody(echo) catch return response;
                response.setStatus(Http.Status.OK);
            }

            return response;
        }
    }.f);

    try server.addRoute("/user-agent", struct {
        fn f(_: Context, request: Request, _allocator: std.mem.Allocator) Response {
            var response = Response.init(_allocator);
            response.setStatus(Http.Status.NotFound);
            response.setContentType(Http.ContentType.TextPlain) catch return response;

            const user_agent = if (request.headers.get("User-Agent")) |v| v else return response;
            response.setBody(user_agent) catch return response;

            response.setStatus(Http.Status.OK);
            return response;
        }
    }.f);


    return server.run();
}
