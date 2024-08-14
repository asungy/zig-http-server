const Request = @import("http/request.zig").Request;
const Response = @import("http/response.zig").Response;
const Router = @import("router.zig").Router;
const RouteHandler = @import("router.zig").RouteHandler;
const http = @import("http/http.zig");
const std = @import("std");

pub const Server = @This();
const Allocator = std.mem.Allocator;

allocator: Allocator,
address: []const u8,
port: u16,
server: std.net.Server,
router: Router,
pool: *std.Thread.Pool,

pub const Option = struct {
    address: []const u8,
    port: u16,
    directory: []const u8,
    allocator: Allocator,
};

pub fn init(option: Option) !Server {
    var pool = try option.allocator.create(std.Thread.Pool);
    try pool.init(.{ .allocator = option.allocator, .n_jobs = 8 } );
    const address = try std.net.Address.resolveIp(option.address, option.port);
    return Server {
        .allocator = option.allocator,
        .address = option.address,
        .port = option.port,
        .server = try address.listen(.{ .reuse_address = true }),
        .router = try Router.init(option.allocator),
        .pool = pool,
    };
}

pub fn deinit(self: *Server) void {
    self.server.deinit();
    self.router.deinit();
    self.pool.deinit();
    self.allocator.destroy(self.pool);
    self.* = undefined;
}

pub fn addRoute(self: *Server, path: []const u8, handler: RouteHandler) Allocator.Error!void {
    try self.router.addRoute(path, handler);
}

pub fn run(self: *Server) !void {
    std.debug.print("Listening on {s}:{d}\n", .{self.address, self.port});

    while (true) {
        const conn = try self.allocator.create(std.net.Server.Connection);
        conn.* = try self.server.accept();
        try self.pool.spawn(connectionHandler, .{conn, self.router, self.allocator});
    }
}

fn sendResponse(response: *Response, conn: *std.net.Server.Connection, allocator: Allocator) !void {
    const bytes = try response.serialize(allocator);
    defer allocator.free(bytes);
    try conn.stream.writer().writeAll(bytes);
}

fn connectionHandler(conn: *std.net.Server.Connection, router: Router, allocator: Allocator) void {
    var buffer: [1024]u8 = undefined;
    _ = conn.stream.reader().read(&buffer) catch {
        std.debug.print("Could not read from connect stream.", .{});
        return;
    };

    var request = Request.parse(&buffer, allocator) catch {
        std.debug.print("Could not read from connect stream.", .{});
        return;
    };
    defer request.deinit();

    var response = router.createResponse(request, allocator) catch {
        std.debug.print("Error creating response.", .{});
        return;
    };
    defer response.deinit();

    sendResponse(&response, conn, allocator) catch {
        std.debug.print("Error sending response.", .{});
        return;
    };

    conn.stream.close();
    allocator.destroy(conn);
}
