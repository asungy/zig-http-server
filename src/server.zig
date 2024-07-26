const Request = @import("http/request.zig").Request;
const Response = @import("http/response.zig").Response;
const http = @import("http/http.zig");
const std = @import("std");

const Allocator = std.mem.Allocator;
const print = std.debug.print;

const RouteHandler = *const fn(request: Request) Response;
pub const Server = struct {
    arena: std.heap.ArenaAllocator,
    address: []const u8,
    port: u16,
    server: std.net.Server,
    routes: std.StringHashMap(RouteHandler),

    pub fn init(address_name: []const u8, port: u16, allocator: Allocator) !Server {
        const arena = std.heap.ArenaAllocator.init(allocator);
        const address = try std.net.Address.resolveIp(address_name, port);
        return Server {
            .arena = arena,
            .address = address_name,
            .port = port,
            .server = try address.listen(.{ .reuse_address = true }),
            .routes = std.StringHashMap(RouteHandler).init(allocator),
        };
    }

    pub fn deinit(self: Server) void {
        _ = self.arena.reset(.free_all);
        self.server.deinit();
        self.routes.deinit();
    }

    pub fn addRoute(self: Server, route: []const u8, handler: RouteHandler) !void {
        try self.routes.put(route, handler);
    }

    pub fn run(self: *Server) !void {
        print("Listening on {s}:{d}\n", .{self.address, self.port});
        var conn = try self.server.accept();
        defer conn.stream.close();

        var buffer: [1024]u8 = undefined;
        _ = try conn.stream.reader().read(&buffer);

        const request = try Request.parse(&buffer);

        var it = self.routes.iterator();
        while (it.next()) |kv| {
            if (std.mem.eql(u8, kv.key_ptr.*, request.target)) {
                const response = kv.value_ptr.*(request);
                return self.sendResponse(&response, &conn);
            }
        }

        var notFound = try Response.init(self.arena.child_allocator);
        defer notFound.deinit();
        notFound.setStatus(http.Status.NotFound);
        try self.sendResponse(&notFound, &conn);
    }

    fn sendResponse(self: *Server, response: *Response, conn: *std.net.Server.Connection) !void {
        const bytes = try response.serialize(self.arena.child_allocator);
        defer self.arena.child_allocator.free(bytes);
        try conn.stream.writer().writeAll(bytes);
    }
};

