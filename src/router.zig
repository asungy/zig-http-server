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

        const delim = '/';
        inline fn delimString() []const u8 {
            return comptime &[1]u8{delim};
        }

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

        fn findMatchingNode(self: *Node, target: []const u8) ?*Node {
            if (target.len == 0 or target[0] != Node.delim or
                !std.mem.eql(u8, self.key, Node.delimString())) return null;

            if (std.mem.eql(u8, target, Node.delimString())) return self;

            var paths = std.mem.split(u8, target, Node.delimString());
            var prev_node = self;
            var current_node = self;
            var current_path = paths.next();

            while (paths.next()) |next_path| {
                if (current_node.children.get(next_path)) |next_node| {
                    prev_node = current_node;
                    current_node = next_node;
                    current_path = next_path;
                } else {
                    return null;
                }
            }

            return current_node;
        }
    };
};

test "find matching static node" {
    const Node = RouteTrie.Node;
    var rootNode = Node.init(Node.delimString(), Node.Kind.Static, null, std.testing.allocator); defer rootNode.deinit();
    var node1    = Node.init("abc", Node.Kind.Static, null, std.testing.allocator); defer node1.deinit();
    var node2    = Node.init("def", Node.Kind.Static, null, std.testing.allocator); defer node2.deinit();
    var node3    = Node.init("ghi", Node.Kind.Static, null, std.testing.allocator); defer node3.deinit();

    try rootNode.children.put(node1.key, &node1);
    try node1.children.put(node2.key, &node2);
    try node2.children.put(node3.key, &node3);

    // Error checking.
    try std.testing.expectEqual(null, rootNode.findMatchingNode(""));
    try std.testing.expectEqual(null, rootNode.findMatchingNode("abc"));
    try std.testing.expectEqual(null, node1.findMatchingNode("abc"));

    // Positive case.
    try std.testing.expectEqual(&rootNode, rootNode.findMatchingNode("/").?);
    try std.testing.expectEqual(&node1,    rootNode.findMatchingNode("/abc").?);
    try std.testing.expectEqual(&node2,    rootNode.findMatchingNode("/abc/def").?);
    try std.testing.expectEqual(&node3,    rootNode.findMatchingNode("/abc/def/ghi").?);

    // Negative case.
    try std.testing.expectEqual(null, rootNode.findMatchingNode("/xyz"));
    try std.testing.expectEqual(null, rootNode.findMatchingNode("/abc/def/ghi/jkl"));
}
