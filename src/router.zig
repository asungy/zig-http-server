const std = @import("std");
const Request = @import("http/request.zig").Request;
const Response = @import("http/response.zig").Response;
const Allocator = std.mem.Allocator;

const Node = struct {
    key: []const u8,
    kind: Node.Kind,
    children: std.StringHashMap(*Node),
    handler: ?RouteHandler,
    prev: ?*Node,
    next: ?*Node,

    const delim = '/';
    inline fn delimString() []const u8 {
        return comptime &[1]u8{delim};
    }

    const Kind = enum {
        Root,
        Static,
        Capture,
    };

    fn init(key: []const u8, kind: Node.Kind, handler: ?RouteHandler, allocator: Allocator) !*Node {
        var node = try allocator.create(Node);
        node.key = key;
        node.kind = kind;
        node.handler = handler;
        node.children = std.StringHashMap(*Node).init(allocator);
        return node;
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

const DoublyLinkedList = struct {
    head: *Node,
    tail: *Node,
    allocator: Allocator,

    const Self = @This();

    fn init(allocator: Allocator) !Self {
        var head = try allocator.create(Node);
        var tail = try allocator.create(Node);
        head.next = tail;
        tail.prev = head;
        return Self {
            .allocator = allocator,
            .head = head,
            .tail = tail,
        };
    }

    fn deinit(self: Self) void {
        self.allocator.destroy(self.head);
        self.allocator.destroy(self.tail);
    }

    fn prepend(self: *Self, node: *Node) void {
        node.prev = self.head;
        node.next = self.head.next;
        node.next.?.prev = node;
        self.head.next = node;
    }

    // fn append(self: *Self, node: *Node) void {
    // }
};

const RouteHandler = *const fn(request: Request) Response;
const RouteTrie = struct {
    root: *Node,
    allocator: Allocator,

    fn init(allocator: Allocator) !RouteTrie {
        const new_node = try allocator.create(Node);
        new_node.init(undefined, Node.Kind.Root, null, allocator);
        return RouteTrie {
            .root = new_node,
            .allocator = allocator,
        };
    }

    fn deinit(self: *RouteTrie) !void {
        const L = std.DoublyLinkedList(*Node);
        var queue = L{};

        // TODO: Convert Route nodes to doubly linked list nodes so that they can be queued and freed.
        const create_lnode = struct { fn f(node: *Node, allocator: Allocator) !*L.Node {
            var lnode = try allocator.create(L.Node);
            lnode.data = node;
            return lnode;
        }}.f;

        queue.append(try create_lnode(self.root, self.allocator));

        while (queue.popFirst()) |lnode| {
            const node = lnode.data;
            var it = node.children.valueIterator();
            while (it.next()) |child| {
                queue.append(try create_lnode(child.*, self.allocator));
            }
            node.deinit();
            self.allocator.destroy(node);
            self.allocator.destroy(lnode);
        }
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

};

test "Doubly Linked List" {
    const allocator = std.testing.allocator;
    const destroy = struct {fn destroy(n: *Node, a: Allocator) void {
        n.deinit();
        a.destroy(n);
    }}.destroy;

    var dll = try DoublyLinkedList.init(std.testing.allocator); defer dll.deinit();
    const node1 = try Node.init(Node.delimString(), Node.Kind.Static, null, allocator); defer destroy(node1, allocator);
    dll.prepend(node1);
    try std.testing.expectEqual(node1, dll.head.next);
    try std.testing.expectEqual(node1, dll.tail.prev);
    try std.testing.expectEqual(dll.head, node1.prev);
    try std.testing.expectEqual(dll.tail, node1.next);
}

test "add to RouteTrie" {
    if (true) return error.SkipZigTest;

    var trie = try RouteTrie.init(std.testing.allocator);
    defer trie.deinit() catch std.testing.expect(false);

    const handler = struct {fn f (_: Request) Response {
        return try Response.init(std.testing.allocator);
    }}.f;

    try trie.addRoute("/abc", handler);
    try trie.addRoute("/abc/xxx", handler);
    try trie.addRoute("/def", handler);
    try trie.addRoute("/ghi", handler);

    const new_node = trie.root.children.get("abc").?;
    try std.testing.expectEqualStrings("abc", new_node.*.key);
    try std.testing.expectEqual(Node.Kind.Static, new_node.*.kind);
}

test "find matching capture node" {
    if (true) return error.SkipZigTest;

    var rootNode = try Node.init(Node.delimString(), Node.Kind.Static, null, std.testing.allocator); defer rootNode.deinit();
    var node1    = try Node.init("abc",   Node.Kind.Static, null, std.testing.allocator); defer node1.deinit();
    var node2    = try Node.init("{def}", Node.Kind.Static, null, std.testing.allocator); defer node2.deinit();
    var node3    = try Node.init("ghi",   Node.Kind.Static, null, std.testing.allocator); defer node3.deinit();

    try rootNode.children.put(node1.key, node1);
    try node1.children.put(node2.key, node2);
    try node2.children.put(node3.key, node3);

    try std.testing.expectEqual(node2, rootNode.findMatchingNode("/abc/hello").?);
    try std.testing.expectEqual(node3, rootNode.findMatchingNode("/abc/whatsup/ghi").?);
}

test "find matching static node" {
    if (true) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const destroy = struct {fn destroy(node: *Node, a: Allocator) void {
        node.deinit();
        a.destroy(node);
    }}.destroy;

    var rootNode = try Node.init(Node.delimString(), Node.Kind.Static, null, allocator); defer destroy(rootNode, allocator);
    var node1    = try Node.init("abc", Node.Kind.Static, null, allocator); defer destroy(node1, allocator);
    var node2    = try Node.init("def", Node.Kind.Static, null, allocator); defer destroy(node2, allocator);
    const node3  = try Node.init("ghi", Node.Kind.Static, null, allocator); defer destroy(node3, allocator);

    try rootNode.children.put(node1.key, node1);
    try node1.children.put(node2.key, node2);
    try node2.children.put(node3.key, node3);

    // Error checking.
    try std.testing.expectEqual(null, rootNode.findMatchingNode(""));
    try std.testing.expectEqual(null, rootNode.findMatchingNode("abc"));
    try std.testing.expectEqual(null, node1.findMatchingNode("abc"));

    // Positive case.
    try std.testing.expectEqual(rootNode, rootNode.findMatchingNode("/").?);
    try std.testing.expectEqual(node1,    rootNode.findMatchingNode("/abc").?);
    try std.testing.expectEqual(node2,    rootNode.findMatchingNode("/abc/def").?);
    try std.testing.expectEqual(node3,    rootNode.findMatchingNode("/abc/def/ghi").?);

    // Negative case.
    try std.testing.expectEqual(null, rootNode.findMatchingNode("/xyz"));
    try std.testing.expectEqual(null, rootNode.findMatchingNode("/abc/def/ghi/jkl"));
}
