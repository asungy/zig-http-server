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

    pub fn toString(self: Version) []const u8 {
        return switch (self) {
            Version.Http_1_1 => "HTTP/1.1",
        };
    }
};

pub const Status = enum {
    OK,
    NotFound,
    InternalServerError,

    pub fn code(self: Status) u16 {
        return switch (self) {
            Status.OK                  => 200,
            Status.NotFound            => 404,
            Status.InternalServerError => 500,
        };
    }

    pub fn toString(self: Status) []const u8 {
        return switch (self) {
            Status.OK       => "OK",
            Status.NotFound => "Not Found",
            Status.InternalServerError => "Internal Server Error",
        };
    }
};

pub const ContentType = enum {
    TextPlain,
    OctetStream,

    pub fn toString(self: ContentType) []const u8 {
        return switch (self) {
            ContentType.TextPlain => "text/plain",
            ContentType.OctetStream => "application/octet-stream",
        };
    }
};
