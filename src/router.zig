const std = @import("std");
const Request = @import("http/request.zig").Request;
const Response = @import("http/response.zig").Response;

const Allocator = std.mem.Allocator;

const RouteHandler = *const fn(request: Request) RouteTrie.Error!Response;
const RouteTrie = struct {
    root: Node,

    const Error = error {
        // All URLs must begin with a forward slash.
        DoesNotStartWithSlash,
    };

    const Node = struct {
        key: []const u8,
        kind: Node.Kind,
        children: std.hash_map.AutoHashMap(u8, *Node),
        handler: ?RouteHandler,

        const delim = "/";

        const Kind = enum {
            Delimiter,   // Example: `/`
            Static,      // Example: `def` in `/abc/def/ghi`
            StaticTerm,  // Example: `ghi` in `/abc/def/ghi`
            Capture,     // Example: `/abc/{id}/name`
            CaptureTerm, // Example: `/abc/{id}`
        };

        fn init(key: []const u8, kind: Node.Kind, handler: ?RouteHandler, allocator: Allocator) Node {
            return Node {
                .key = key,
                .kind = kind,
                .children = std.hash_map.AutoHashMap(u8, *Node).init(allocator),
                .handler = handler,
            };
        }

        fn deinit(self: *Node) void {
            self.children.deinit();
        }

        fn findNextMatchingNode(self: *Node, target: []const u8) ?*Node {
            if (target.len == 0) return null;

            var prev: ?*Node = null;
            var current: ?*Node = self;
            var c = target[0];
            for (target[1..]) |next| {
                const child = current.?.children.get(next);
                if (child == null or current.?.key != c) return prev;

                prev = current;
                current = child;
                c = next;
            }

            return current;
        }
    };

    fn init(rootHandler: ?RouteHandler, allocator: Allocator) RouteTrie {
        const kind = if (rootHandler == null) Node.Kind.CharTerm else Node.Kind.Char;
        return RouteTrie {
            .root = Node.init(kind, rootHandler, allocator),
        };
    }

    fn deinit(_: RouteTrie) void {
        // TODO: Implement me
    }

    fn addRoute(self: RouteTrie, key: []const u8, _: RouteHandler) Error!void {
        if (key.len == 0 or key[0] != self.rootKey) {
            return Error.DoesNotStartWithSlash;
        }
        // TODO: Implement me
    }
};

test "route trie node" {
    const Node = RouteTrie.Node;
    var nodeRoot = Node.init('/', Node.Kind.Char, null, std.testing.allocator); defer nodeRoot.deinit();
    var nodeE    = Node.init('e', Node.Kind.Char, null, std.testing.allocator); defer nodeE.deinit();
    var nodeC    = Node.init('c', Node.Kind.Char, null, std.testing.allocator); defer nodeC.deinit();
    var nodeH    = Node.init('h', Node.Kind.Char, null, std.testing.allocator); defer nodeH.deinit();
    var nodeO    = Node.init('o', Node.Kind.Char, null, std.testing.allocator); defer nodeO.deinit();

    try nodeRoot.children.put('e', &nodeE);
    try nodeE.children.put('c', &nodeC);
    try nodeC.children.put('h', &nodeH);
    try nodeH.children.put('o', &nodeO);

    try std.testing.expectEqual(null, nodeRoot.findNextMatchingNode("aoeustnh"));

    var target: []const u8 = "/e";
    var expected = &nodeE;
    var actual   = nodeRoot.findNextMatchingNode(target).?;
    try std.testing.expectEqual(expected, actual);

    target   = "/echo";
    expected = &nodeO;
    actual   = nodeRoot.findNextMatchingNode(target).?;
    try std.testing.expectEqual(expected, actual);

    target   = "/echolonger";
    expected = &nodeO;
    actual   = nodeRoot.findNextMatchingNode(target).?;
    try std.testing.expectEqual(expected, actual);
}
