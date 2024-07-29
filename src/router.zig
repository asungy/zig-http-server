const std = @import("std");
const Request = @import("http/request.zig").Request;
const Response = @import("http/response.zig").Response;

const Allocator = std.mem.Allocator;

const RouteHandler = *const fn(request: Request) Response;
const RouteTrie = struct {
    root: *Node,
    allocator: Allocator,

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
            Root,
            Static,
            Capture,
        };

        fn init(self: *Node, key: []const u8, kind: Node.Kind, handler: ?RouteHandler, allocator: Allocator) void {
            self.key = key;
            self.kind = kind;
            self.handler = handler;
            self.children = std.StringHashMap(*Node).init(allocator);
        }

        fn deinit(self: *Node) void {
            self.children.deinit();
        }

        fn findMatchingNode(self: *Node, target: []const u8) ?*Node {
            if (target.len == 0 or target[0] != Node.delim or
                !std.mem.eql(u8, self.key, Node.delimString())) return null;

            if (std.mem.eql(u8, target, Node.delimString())) return self;

            var paths = std.mem.split(u8, target, Node.delimString());
            var current_node = self;
            var current_path = paths.next();

            while (paths.next()) |next_path| {
                if (current_node.children.get(next_path)) |next_node| {
                    current_node = next_node;
                    current_path = next_path;
                } else {
                    return null;
                }
            }

            return current_node;
        }
    };

    fn init(allocator: Allocator) !RouteTrie {
        const new_node = try allocator.create(Node);
        new_node.init(undefined, Node.Kind.Root, null, allocator);
        return RouteTrie {
            .root = new_node,
            .allocator = allocator,
        };
    }

    const AddRouteError = error {
        RouteAlreadyExists,
        AllocationError,
    };
    fn addRoute(self: *RouteTrie, path: []const u8, handler: RouteHandler) AddRouteError!void {
        std.debug.assert(path.len > 0);
        std.debug.assert(path[0] == Node.delim);

        var current: *Node = self.root;
        var paths = std.mem.split(u8, path[1..], Node.delimString());
        while (paths.peek()) |current_path| {
            if (current.children.get(current_path)) |next| {
                current = next;
                _ = paths.next();
            } else {
                break;
            }
        }

        const key = paths.next().?;
        var new_node: *Node = self.allocator.create(Node) catch return AddRouteError.AllocationError;
        new_node.init(key, Node.Kind.Static, handler, self.allocator);
        current.children.put(key, new_node) catch return AddRouteError.AllocationError;
    }

    // fn deinit(self: RouteTrie) void {
    // }


};

test "add to RouteTrie" {
    const Node = RouteTrie.Node;
    var trie = try RouteTrie.init(std.testing.allocator);
    const handler = struct {fn f (_: Request) Response {
        return try Response.init(std.testing.allocator);
    }}.f;
    try trie.addRoute("/abc", handler);

    const new_node = trie.root.children.get("abc").?;
    try std.testing.expectEqualStrings("abc", new_node.*.key);
    try std.testing.expectEqual(Node.Kind.Static, new_node.*.kind);
}

test "find matching capture node" {
    if (true) return error.SkipZigTest;

    const Node = RouteTrie.Node;
    var rootNode = Node.init(Node.delimString(), Node.Kind.Static, null, std.testing.allocator); defer rootNode.deinit();
    var node1    = Node.init("abc",   Node.Kind.Static, null, std.testing.allocator); defer node1.deinit();
    var node2    = Node.init("{def}", Node.Kind.Static, null, std.testing.allocator); defer node2.deinit();
    var node3    = Node.init("ghi",   Node.Kind.Static, null, std.testing.allocator); defer node3.deinit();

    try rootNode.children.put(node1.key, &node1);
    try node1.children.put(node2.key, &node2);
    try node2.children.put(node3.key, &node3);

    try std.testing.expectEqual(&node2, rootNode.findMatchingNode("/abc/hello").?);
    try std.testing.expectEqual(&node3, rootNode.findMatchingNode("/abc/whatsup/ghi").?);
}

test "find matching static node" {
    if (true) return error.SkipZigTest;

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
