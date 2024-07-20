const std = @import("std");

pub const Method = enum {
    GET,
    pub fn fromString(str: []const u8) ?Method {
        return if (std.mem.eql(u8, str, "GET")) {
            return Method.GET;
        } else {
            return null;
        };
    }
};

pub const Version = enum {
    Http_1_1,
    pub fn fromString(str: []const u8) ?Version {
        return if (std.mem.eql(u8, str, "HTTP/1.1")) {
            return Version.Http_1_1;
        } else {
            return null;
        };
    }
};

