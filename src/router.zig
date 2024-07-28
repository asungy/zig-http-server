const std = @import("std");
const Request = @import("http/request.zig").Request;
const Response = @import("http/response.zig").Response;

const Allocator = std.mem.Allocator;

const RouteHandler = *const fn(request: Request) RouteTrie.Error!Response;
const RouteTrie = struct {
    root: Node,

    const Node = struct {
        key: []const u8,
        kind: Node.Kind,
        children: std.StringHashMap(*Node),
        handler: ?RouteHandler,

        const delim = "/";

        const Kind = enum {
            Static,
            Capture,
        };

        fn init(key: []const u8, kind: Node.Kind, handler: ?RouteHandler, allocator: Allocator) Node {
            return Node {
                .key = key,
                .kind = kind,
                .children = std.StringHashMap(*Node).init(allocator),
                .handler = handler,
            };
        }

        fn deinit(self: *Node) void {
            self.children.deinit();
        }

        fn findNextMatchingNode(self: *Node, target: []const u8) ?*Node {
            // TODO: Implement me!
        }
    };
};

test "route trie node" {
    const Node = RouteTrie.Node;
    var rootNode = Node.init(Node.delim, Node.Kind.Static, null, std.testing.allocator); defer rootNode.deinit();
}
