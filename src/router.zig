const std = @import("std");
const Request = @import("http/request.zig").Request;
const Response = @import("http/response.zig").Response;

const Allocator = std.mem.Allocator;

const RouteHandler = *const fn(request: Request) Response;
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

        fn findNextMatchingNode(self: *Node, target: []const u8) *Node {
            std.debug.assert(std.mem.eql(u8, self.key, Node.delim));
            std.debug.assert(target.len > 0);

            var paths = std.mem.split(u8, target, Node.delim);
            var prev_node = self;
            var current_node = self;
            var current_path = paths.next();

            while (paths.next()) |next_path| {
                if (current_node.children.get(next_path)) |next_node| {
                    prev_node = current_node;
                    current_node = next_node;
                    current_path = next_path;
                } else {
                    return prev_node;
                }
            }


            return current_node;
        }
    };
};



test "find next matching (static) node" {
    const Node = RouteTrie.Node;
    var rootNode = Node.init(Node.delim, Node.Kind.Static, null, std.testing.allocator); defer rootNode.deinit();
    var node1    = Node.init("abc", Node.Kind.Static, null, std.testing.allocator); defer node1.deinit();
    var node2    = Node.init("def", Node.Kind.Static, null, std.testing.allocator); defer node2.deinit();
    var node3    = Node.init("ghi", Node.Kind.Static, null, std.testing.allocator); defer node3.deinit();

    try rootNode.children.put(node1.key, &node1);
    try node1.children.put(node2.key, &node2);
    try node2.children.put(node3.key, &node3);

    try std.testing.expectEqual(&rootNode, rootNode.findNextMatchingNode("/"));
    try std.testing.expectEqual(&node1,    rootNode.findNextMatchingNode("/abc"));
    try std.testing.expectEqual(&node2,    rootNode.findNextMatchingNode("/abc/def"));
    try std.testing.expectEqual(&node3,    rootNode.findNextMatchingNode("/abc/def/ghi"));
}
