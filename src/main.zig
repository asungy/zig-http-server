const Request = @import("http/request.zig").Request;
const Response = @import("http/response.zig").Response;
const Http = @import("http/http.zig");
const Server = @import("server.zig").Server;
const Context = @import("router.zig").Context;
const std = @import("std");

const ArgError = error {
    NoValueProvided,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var address: []const u8 = "127.0.0.1";
    var port: u16 = 4221;
    var directory: []const u8 = "/tmp";

    var args = std.process.args();
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--address")) {
            address = args.next() orelse address;
            break;
        }
        if (std.mem.eql(u8, arg, "--port")) {
            port = try std.fmt.parseInt(u16, args.next() orelse return ArgError.NoValueProvided, 10);
            break;
        }
        if (std.mem.eql(u8, arg, "--directory")) {
            directory = args.next() orelse directory;
            break;
        }
    }

    var server = try Server.init(.{
        .address = address,
        .port = port,
        .allocator = allocator,
        .directory = directory,
    });
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
