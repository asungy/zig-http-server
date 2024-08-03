const Request = @import("http/request.zig").Request;
const Response = @import("http/response.zig").Response;
const Router = @import("router.zig").Router;
const RouteHandler = @import("router.zig").RouteHandler;
const http = @import("http/http.zig");
const std = @import("std");

const Allocator = std.mem.Allocator;
const print = std.debug.print;

pub const Server = struct {
    allocator: Allocator,
    address: []const u8,
    port: u16,
    server: std.net.Server,
    router: Router,

    pub fn init(address_name: []const u8, port: u16, allocator: Allocator) !Server {
        const address = try std.net.Address.resolveIp(address_name, port);
        return Server {
            .allocator = allocator,
            .address = address_name,
            .port = port,
            .server = try address.listen(.{ .reuse_address = true }),
            .router = try Router.init(allocator),
        };
    }

    pub fn deinit(self: *Server) void {
        self.server.deinit();
        self.router.deinit();
    }

    pub fn addRoute(self: *Server, path: []const u8, handler: RouteHandler) Allocator.Error!void {
        try self.router.addRoute(path, handler);
    }

    pub fn run(self: *Server) !void {
        print("Listening on {s}:{d}\n", .{self.address, self.port});
        var conn = try self.server.accept();
        defer conn.stream.close();

        var buffer: [1024]u8 = undefined;
        _ = try conn.stream.reader().read(&buffer);

        const request = try Request.parse(&buffer);
        var response = try self.router.getResponse(request, self.allocator);
        try self.sendResponse(&response, &conn);
    }

    fn sendResponse(self: *Server, response: *Response, conn: *std.net.Server.Connection) !void {
        const bytes = try response.serialize(self.allocator);
        defer self.allocator.free(bytes);
        try conn.stream.writer().writeAll(bytes);
    }
};

