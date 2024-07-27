const std = @import("std");
const Request = @import("http/request.zig").Request;
const Response = @import("http/response.zig").Response;

const Allocator = std.mem.Allocator;

const RouteHandler = *const fn(request: Request) Response;
const Router = struct {
    routes: std.ArrayList(Route),

    const Route = struct {
        captureMap: std.StringHashMap([]u8),
        handler: RouteHandler,

        pub fn init(_: []const u8, handler: RouteHandler, allocator: Allocator) Route {
            const captureMap = std.StringHashMap([]u8).init(allocator);

            // TODO: Do parsing of url here.

            return Route {
                .captureMap = captureMap,
                .handler = handler,
            };
        }

        pub fn deinit(self: Route) void {
            self.captureMap.deinit();
        }
    };

    pub fn init(allocator: Allocator) Router {
        return Router {
            .routes = std.ArrayList(Route).init(allocator),
        };
    }

    pub fn deinit(self: *Router) void {
        self.routes.deinit();
    }

};

test "parsing route" {

}

test "adding route to router" {
    var router = Router.init(std.testing.allocator);
    defer router.deinit();
}
