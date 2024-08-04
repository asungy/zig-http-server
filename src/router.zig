const std = @import("std");
const Allocator = std.mem.Allocator;

const Http = @import("http/http.zig");
const Request = @import("http/request.zig").Request;
const Response = @import("http/response.zig").Response;

pub const Context = struct {
    capture_map: std.StringHashMap([]const u8),

    fn init(capture_map: std.StringHashMap([]const u8)) Context {
        return Context {
            .capture_map = capture_map,
        };
    }

    fn deinit(self: *Context) void {
        self.capture_map.deinit();
    }
};

pub const RouteHandler = *const fn(context: Context, request: Request, allocator: Allocator) Response;

pub const Match = struct {
    node: *Node,
    capture_map: std.StringHashMap([]const u8),

    pub fn deinit(self: *Match) void {
        self.capture_map.deinit();
    }
};

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

    fn init(key: []const u8, handler: ?RouteHandler, allocator: Allocator) Allocator.Error!*Node {
        var node = try allocator.create(Node);
        node.key = key;
        node.kind = if (isCaptureKey(key)) Kind.Capture else Kind.Static;
        node.handler = handler;
        node.children = std.StringHashMap(*Node).init(allocator);

        if (std.mem.eql(u8, key, delimString())) {
            node.kind = Kind.Root;
        } else if (isCaptureKey(key)) {
            node.kind = Kind.Capture;
        } else {
            node.kind = Kind.Static;
        }

        return node;
    }

    fn deinit(self: *Node) void {
        self.children.deinit();
    }

    fn findMatching(self: *Node, target: []const u8, allocator: Allocator) Allocator.Error!?Match {
        if (target.len == 0 or target[0] != Node.delim) return null;

        var paths = std.mem.split(u8, target, Node.delimString());
        var current_node = self;
        var current_path = paths.next();
        var capture_map = std.StringHashMap([]const u8).init(allocator);

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
                    try capture_map.put(stripCaptureKey(current_node.key), next_path);
                    current_path = next_path;
                } else {
                    return null;
                }
            }
        }

        const match = Match {
            .capture_map = capture_map,
            .node = current_node,
        };
        return match;
    }

    fn stripCaptureKey(key: []const u8) []const u8 {
        if (isCaptureKey(key) and key.len > 2) {
            return key[1..key.len-1];
        } else {
            return key;
        }
    }

    fn getCaptureChildren(self: Node, allocator: Allocator) Allocator.Error!std.ArrayList(*Node) {
        var list = std.ArrayList(*Node).init(allocator);
        var it = self.children.valueIterator();
        while (it.next()) |node| {
            if (node.*.kind == Kind.Capture) {
                try list.append(node.*);
            }
        }
        return list;
    }

    fn isCaptureKey(key: []const u8) bool {
        std.debug.assert(key.len > 0);
        return key[0] == '{' and key[key.len - 1] == '}';
    }
};

const DoublyLinkedList = struct {
    head: *Node,
    tail: *Node,
    allocator: Allocator,

    const Self = @This();

    fn init(allocator: Allocator) Allocator.Error!Self {
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

    fn addRoute(self: *RouteTrie, path: []const u8, handler: RouteHandler) Allocator.Error!void {
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

    fn matchUrl(self: RouteTrie, url: []const u8) Allocator.Error!?Match {
        return try self.root.findMatching(url, self.allocator);
    }
};

pub const Router = struct {
    trie: RouteTrie,
    default_response: Response,

    pub fn init(allocator: Allocator) !Router {
        var default_response = Response.init(allocator);
        try default_response.setContentType(Http.ContentType.TextPlain);
        default_response.setStatus(Http.Status.NotFound);
        return Router {
            .trie = try RouteTrie.init(allocator),
            .default_response = default_response,
        };
    }

    pub fn deinit(self: *Router) void {
        self.trie.deinit();
    }

    pub fn addRoute(self: *Router, path: []const u8, handler: RouteHandler) Allocator.Error!void {
        try self.trie.addRoute(path, handler);
    }

    pub fn getResponse(self: Router, request: Request, allocator: Allocator) Allocator.Error!Response {
        if (try self.trie.matchUrl(request.target)) |match| {
            var context = Context.init(match.capture_map);
            defer context.deinit();

            const response = match.node.handler.?(context, request, allocator);
            return response;
        } else {
            return self.default_response;
        }
    }
};

test "add to RouteTrie" {
    var trie = try RouteTrie.init(std.testing.allocator);
    defer trie.deinit();

    const handler = struct {fn f (_: Context, _: Request, allocator: Allocator) Response {
        return try Response.init(allocator);
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
    try std.testing.expectEqualStrings("aaa", (try trie.matchUrl("/def/aaa")).?.node.key);

    {
        var match = (try trie.matchUrl("/ghi/hello")).?;
        defer match.deinit();
        try std.testing.expectEqualStrings("{abc}", match.node.key);
        try std.testing.expectEqualStrings("hello", match.capture_map.get("abc").?);
    }
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
    try std.testing.expectEqual(null, rootNode.findMatching("", allocator));
    try std.testing.expectEqual(null, rootNode.findMatching("abc", allocator));
    try std.testing.expectEqual(null, node1.findMatching("abc", allocator));

    // Positive case.
    try std.testing.expectEqual(rootNode, (try rootNode.findMatching("/", allocator)).?.node);
    try std.testing.expectEqual(node1,    (try rootNode.findMatching("/abc", allocator)).?.node);
    try std.testing.expectEqual(node2,    (try rootNode.findMatching("/abc/def", allocator)).?.node);
    try std.testing.expectEqual(node3,    (try rootNode.findMatching("/abc/def/ghi", allocator)).?.node);

    // Negative case.
    try std.testing.expectEqual(null, rootNode.findMatching("/xyz", allocator));
    try std.testing.expectEqual(null, rootNode.findMatching("/abc/def/ghi/jkl", allocator));
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

