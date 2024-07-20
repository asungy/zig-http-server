const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;

fn get_url(request: []u8) ?[]const u8 {
    var it = std.mem.split(u8, request, " ");
    _ = it.next();
    return it.next();
}

const RouteHandler = *const fn(request: []const u8) void;
const Server = struct {
    address: []const u8,
    port: u16,
    server: std.net.Server,
    routes: std.StringHashMap(RouteHandler),

    pub fn init(address_name: []const u8, port: u16, allocator: Allocator) !Server {
        const address = try std.net.Address.resolveIp(address_name, port);
        return Server {
            .address = address_name,
            .port = port,
            .server = try address.listen(.{ .reuse_address = true }),
            .routes = std.StringHashMap(RouteHandler).init(allocator),
        };
    }

    pub fn deinit(self: Server) void {
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

        const url = get_url(&buffer).?;
        if (std.mem.eql(u8, url, "/")) {
            try conn.stream.writer().writeAll("HTTP/1.1 200 OK\r\n\r\n");
        } else {
            try conn.stream.writer().writeAll("HTTP/1.1 404 Not Found\r\n\r\n");
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var server = try Server.init("127.0.0.1", 4221, allocator);
    try server.run();
}
