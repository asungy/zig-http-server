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

    fn init(key: []const u8, handler: ?RouteHandler, allocator: Allocator) !*Node {
        var node = try allocator.create(Node);
        node.key = key;
        node.kind = if (is_capture_key(key)) Kind.Capture else Kind.Static;
        node.handler = handler;
        node.children = std.StringHashMap(*Node).init(allocator);

        if (std.mem.eql(u8, key, delimString())) {
            node.kind = Kind.Root;
        } else if (is_capture_key(key)) {
            node.kind = Kind.Capture;
        } else {
            node.kind = Kind.Static;
        }

        return node;
    }

    fn deinit(self: *Node) void {
        self.children.deinit();
    }

    fn findMatchingNode(self: *Node, target: []const u8, allocator: Allocator) !?*Node {
        if (target.len == 0 or target[0] != Node.delim) return null;

        var paths = std.mem.split(u8, target, Node.delimString());
        var current_node = self;
        var current_path = paths.next();

        while (paths.next()) |next_path| {
            if (std.mem.eql(u8, next_path, "")) break;

            if (current_node.children.get(next_path)) |next_node| {
                current_node = next_node;
                current_path = next_path;
            } else {

                var capture_nodes = try current_node.getCaptureChildren(allocator);
                defer capture_nodes.deinit();

                // NOTE: This just returns the last capture group.
                if (capture_nodes.items.len > 0) {
                    current_node = capture_nodes.pop();
                } else {
                    return null;
                }
            }
        }

        return current_node;
    }

    fn getCaptureChildren(self: Node, allocator: Allocator) !std.ArrayList(*Node) {
        var list = std.ArrayList(*Node).init(allocator);
        var it = self.children.valueIterator();
        while (it.next()) |node| {
            if (node.*.kind == Kind.Capture) {
                try list.append(node.*);
            }
        }
        return list;
    }

    fn is_capture_key(key: []const u8) bool {
        std.debug.assert(key.len > 0);
        return key[0] == '{' and key[key.len - 1] == '}';
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

    fn append(self: *Self, node: *Node) void {
        node.prev = self.tail.prev;
        node.next = self.tail;
        self.tail.prev.?.next = node;
        self.tail.prev = node;
    }

    fn pop_front(self: *Self) ?*Node {
        if (self.head.next == self.tail) return null;

        var result = self.head.next.?;

        self.head.next = result.next;
        result.next.?.prev = self.head;

        result.prev = null;
        result.next = null;

        return result;
    }

    fn pop_back(self: *Self) ?*Node {
        if (self.tail.prev == self.head) return null;

        var result = self.tail.prev.?;
        self.tail.prev = result.prev;
        result.prev.?.next = self.tail;

        result.prev = null;
        result.next = null;

        return result;
    }

    fn is_empty(self: Self) bool {
        const result = self.head.next == self.tail;
        if (result) { std.debug.assert(self.tail.prev == self.head); }
        return result;
    }
};

const RouteHandler = *const fn(request: Request) Response;
const RouteTrie = struct {
    root: *Node,
    allocator: Allocator,
    dll: DoublyLinkedList,

    fn init(allocator: Allocator) !RouteTrie {
        const new_node = try Node.init("/", null, allocator);
        const dll = try DoublyLinkedList.init(allocator);
        return RouteTrie {
            .root = new_node,
            .allocator = allocator,
            .dll = dll,
        };
    }

    fn deinit(self: *RouteTrie) void {
        self.dll.append(self.root);
        while (!self.dll.is_empty()) {
            var current = self.dll.pop_front().?;
            var it = current.children.valueIterator();
            while (it.next()) |child|{
                self.dll.append(child.*);
            }

            current.deinit();
            self.allocator.destroy(current);
        }
        self.dll.deinit();
    }

    fn addRoute(self: *RouteTrie, path: []const u8, handler: RouteHandler) !void {
        std.debug.assert(path.len > 0);
        std.debug.assert(path[0] == Node.delim);

        var prev_path: ?[]const u8 = null;
        var current: *Node = self.root;
        var paths = std.mem.split(u8, path[1..], Node.delimString());
        while (paths.next()) |current_path| {
            if (current.children.get(current_path)) |next| {
                current = next;
            } else {
                prev_path = current_path;
                break;
            }
        }

        if (paths.peek() == null) {
            if (prev_path) |p| {
                const new_node = try Node.init(p, null, self.allocator);
                try current.children.put(p, new_node);
            } else {
                current.handler = handler;
            }
        } else {
            var new_node = try Node.init(prev_path.?, null, self.allocator);
            try current.children.put(prev_path.?, new_node);
            current = new_node;
            while (paths.next()) |current_path| {
                new_node = try Node.init(current_path, null, self.allocator);
                try current.children.put(current_path, new_node);
                current = new_node;
            }
            current.handler = handler;
        }
    }

    fn matchUrl(self: RouteTrie, url: []const u8) !?*Node {
        return try self.root.findMatchingNode(url, self.allocator);
    }
};

test "add to RouteTrie" {
    var trie = try RouteTrie.init(std.testing.allocator);
    defer trie.deinit();

    const handler = struct {fn f (_: Request) Response {
        return try Response.init(std.testing.allocator);
    }}.f;

    try std.testing.expectEqualStrings(Node.delimString(), trie.root.*.key);
    try std.testing.expectEqual(Node.Kind.Root, trie.root.*.kind);

    try trie.addRoute("/def/aaa/bbb/ccc", handler);
    {
        const def = trie.root.children.get("def").?;
        try std.testing.expectEqualStrings("def", def.*.key);
        try std.testing.expectEqual(Node.Kind.Static, def.*.kind);

        const aaa = def.children.get("aaa").?;
        try std.testing.expectEqualStrings("aaa", aaa.*.key);
        try std.testing.expectEqual(Node.Kind.Static, aaa.*.kind);

        const bbb = aaa.children.get("bbb").?;
        try std.testing.expectEqualStrings("bbb", bbb.*.key);
        try std.testing.expectEqual(Node.Kind.Static, bbb.*.kind);

        const ccc = bbb.children.get("ccc").?;
        try std.testing.expectEqualStrings("ccc", ccc.*.key);
        try std.testing.expectEqual(Node.Kind.Static, ccc.*.kind);
    }

    try trie.addRoute("/ghi/{abc}", handler);
    {
        const ghi = trie.root.children.get("ghi").?;
        try std.testing.expectEqualStrings("ghi", ghi.*.key);
        try std.testing.expectEqual(Node.Kind.Static, ghi.*.kind);

        const capture_abc = ghi.children.get("{abc}").?;
        try std.testing.expectEqualStrings("{abc}", capture_abc.*.key);
        try std.testing.expectEqual(Node.Kind.Capture, capture_abc.*.kind);
    }

    try std.testing.expectEqual(null, trie.matchUrl("/does/not/exist"));
    try std.testing.expectEqualStrings("aaa", (try trie.matchUrl("/def/aaa")).?.key);
    try std.testing.expectEqualStrings("{abc}", (try trie.matchUrl("/ghi/hello")).?.key);
}

test "find matching static node" {
    const allocator = std.testing.allocator;
    const destroy = struct {fn destroy(node: *Node, a: Allocator) void {
        node.deinit();
        a.destroy(node);
    }}.destroy;

    var rootNode = try Node.init(Node.delimString(), null, allocator); defer destroy(rootNode, allocator);
    var node1    = try Node.init("abc", null, allocator); defer destroy(node1, allocator);
    var node2    = try Node.init("def", null, allocator); defer destroy(node2, allocator);
    const node3  = try Node.init("ghi", null, allocator); defer destroy(node3, allocator);

    try rootNode.children.put(node1.key, node1);
    try node1.children.put(node2.key, node2);
    try node2.children.put(node3.key, node3);

    // Error checking.
    try std.testing.expectEqual(null, rootNode.findMatchingNode("", allocator));
    try std.testing.expectEqual(null, rootNode.findMatchingNode("abc", allocator));
    try std.testing.expectEqual(null, node1.findMatchingNode("abc", allocator));

    // Positive case.
    try std.testing.expectEqual(rootNode, (try rootNode.findMatchingNode("/", allocator)).?);
    try std.testing.expectEqual(node1,    (try rootNode.findMatchingNode("/abc", allocator)).?);
    try std.testing.expectEqual(node2,    (try rootNode.findMatchingNode("/abc/def", allocator)).?);
    try std.testing.expectEqual(node3,    (try rootNode.findMatchingNode("/abc/def/ghi", allocator)).?);

    // Negative case.
    try std.testing.expectEqual(null, rootNode.findMatchingNode("/xyz", allocator));
    try std.testing.expectEqual(null, rootNode.findMatchingNode("/abc/def/ghi/jkl", allocator));
}

test "Doubly Linked List" {
    const allocator = std.testing.allocator;
    const destroy = struct {fn destroy(n: *Node, a: Allocator) void {
        n.deinit();
        a.destroy(n);
    }}.destroy;

    var dll = try DoublyLinkedList.init(std.testing.allocator); defer dll.deinit();
    const node1 = try Node.init(Node.delimString(), null, allocator); defer destroy(node1, allocator);
    const node2 = try Node.init(Node.delimString(), null, allocator); defer destroy(node2, allocator);
    const node3 = try Node.init(Node.delimString(), null, allocator); defer destroy(node3, allocator);
    const node4 = try Node.init(Node.delimString(), null, allocator); defer destroy(node4, allocator);

    try std.testing.expectEqual(null, dll.pop_front());
    try std.testing.expectEqual(null, dll.pop_back());
    try std.testing.expect(dll.is_empty());

    // [ head ] <--> (1) <--> [ tail ]
    dll.prepend(node1);
    try std.testing.expect(!dll.is_empty());
    try std.testing.expectEqual(node1, dll.head.next);
    try std.testing.expectEqual(node1, dll.tail.prev);
    try std.testing.expectEqual(dll.head, node1.prev);
    try std.testing.expectEqual(dll.tail, node1.next);

    // [ head ] <--> (1) <--> (2) <--> [ tail ]
    dll.append(node2);
    try std.testing.expectEqual(node2, node1.next);
    try std.testing.expectEqual(node2, dll.tail.prev);
    try std.testing.expectEqual(node1, node2.prev);
    try std.testing.expectEqual(dll.tail, node2.next);

    // [ head ] <--> (3) <--> (1) <--> (2) <--> [ tail ]
    dll.prepend(node3);
    try std.testing.expectEqual(node3, dll.head.next);
    try std.testing.expectEqual(node3, node1.prev);
    try std.testing.expectEqual(dll.head, node3.prev);
    try std.testing.expectEqual(node1, node3.next);

    // [ head ] <--> (3) <--> (1) <--> (2) <--> (4) <--> [ tail ]
    dll.append(node4);
    try std.testing.expectEqual(node4, node2.next);
    try std.testing.expectEqual(node4, dll.tail.prev);
    try std.testing.expectEqual(node2, node4.prev);
    try std.testing.expectEqual(dll.tail, node4.next);


    // [ head ] <--> (1) <--> (2) <--> (4) <--> [ tail ]
    try std.testing.expectEqual(node3, dll.pop_front());
    try std.testing.expectEqual(node1, dll.head.next);
    try std.testing.expectEqual(dll.head, node1.prev);

    // [ head ] <--> (1) <--> (2) <--> [ tail ]
    try std.testing.expectEqual(node4, dll.pop_back());
    try std.testing.expectEqual(node2, dll.tail.prev);
    try std.testing.expectEqual(dll.tail, node2.next);
}

