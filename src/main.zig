const Request = @import("http/request.zig").Request;
const Response = @import("http/response.zig").Response;
const Http = @import("http/http.zig");
const Server = @import("server.zig").Server;
const Context = @import("router.zig").Context;
const std = @import("std");

const ArgError = error {
    NoValueProvided,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var address: []const u8 = "127.0.0.1";
    var port: u16 = 4221;
    var directory: []const u8 = "/tmp";

    var args = std.process.args();
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--address")) {
            address = args.next() orelse address;
            break;
        }
        if (std.mem.eql(u8, arg, "--port")) {
            port = try std.fmt.parseInt(u16, args.next() orelse return ArgError.NoValueProvided, 10);
            break;
        }
        if (std.mem.eql(u8, arg, "--directory")) {
            directory = args.next() orelse directory;
            break;
        }
    }

    var server = try Server.init(.{
        .address = address,
        .port = port,
        .allocator = allocator,
        .directory = directory,
    });
    defer server.deinit();

    try server.addRoute("/exit", struct {
        fn f(_context: Context, _: Request, _allocator: std.mem.Allocator) Response {
            @atomicStore(bool, _context.exit_flag, true, std.builtin.AtomicOrder.unordered);
            var response = Response.init(_allocator);
            response.setStatus(Http.Status.OK);
            response.setContentType(Http.ContentType.TextPlain) catch return response;
            return response;
        }
    }.f);

    try server.addRoute("/", struct {
        fn f(_: Context, _: Request, _allocator: std.mem.Allocator) Response {
            var response = Response.init(_allocator);
            response.setStatus(Http.Status.OK);
            response.setContentType(Http.ContentType.TextPlain) catch return response;
            return response;
        }
    }.f);

    try server.addRoute("/echo/{echo}", struct {
        fn f(_context: Context, _: Request, _allocator: std.mem.Allocator) Response {
            var response = Response.init(_allocator);
            response.setStatus(Http.Status.InternalServerError);
            response.setContentType(Http.ContentType.TextPlain) catch return response;

            if (_context.capture_map.get("echo")) |echo| {
                response.setBody(echo) catch return response;
                response.setStatus(Http.Status.OK);
            }

            return response;
        }
    }.f);

    try server.addRoute("/user-agent", struct {
        fn f(_: Context, _request: Request, _allocator: std.mem.Allocator) Response {
            var response = Response.init(_allocator);
            response.setStatus(Http.Status.InternalServerError);
            response.setContentType(Http.ContentType.TextPlain) catch return response;

            const user_agent = if (_request.headers.get("User-Agent")) |v| v else return response;
            response.setBody(user_agent) catch return response;

            response.setStatus(Http.Status.OK);
            return response;
        }
    }.f);

    try server.addRoute("/files/{file}", struct {
        fn f(_context: Context, _request: Request, _allocator: std.mem.Allocator) Response {
            var response = Response.init(_allocator);
            response.setContentType(Http.ContentType.TextPlain) catch {
                response.setStatus(Http.Status.InternalServerError);
                return response;
            };

            if (_context.capture_map.get("file")) |filename| {
                if (_request.method == Http.Method.GET) {
                    const buf = _allocator.alloc(u8, _context.file_directory.len + filename.len + 1) catch {
                        response.setStatus(Http.Status.InternalServerError);
                        response.setBody("Buffer allocation error") catch {};
                        return response;
                    };
                    defer _allocator.free(buf);
                    const path = std.fmt.bufPrint(buf, "{s}/{s}", .{_context.file_directory, filename}) catch {
                        response.setStatus(Http.Status.InternalServerError);
                        response.setBody("Error formatting file path") catch {};
                        return response;
                    };

                    const options = std.fs.File.OpenFlags {
                        .mode = .read_only,
                        .lock = .none,
                        .lock_nonblocking = false,
                        .allow_ctty = false,
                    };
                    var file = std.fs.openFileAbsolute(path, options) catch {
                        response.setStatus(Http.Status.NotFound);
                        return response;
                    };
                    defer file.close();

                    const stat = file.stat() catch {
                        response.setStatus(Http.Status.InternalServerError);
                        response.setBody("Error getting file stat") catch {};
                        return response;
                    };
                    const contents = _allocator.alloc(u8, stat.size) catch {
                        response.setStatus(Http.Status.InternalServerError);
                        response.setBody("Buffer allocation error") catch {};
                        return response;
                    };
                    defer _allocator.free(contents);
                    _ = file.readAll(contents) catch {
                        response.setStatus(Http.Status.InternalServerError);
                        response.setBody("Error reading file contents") catch {};
                        return response;
                    };

                    response.setBody(contents) catch {
                        response.setStatus(Http.Status.InternalServerError);
                        response.setBody("Error writing body contents") catch {};
                        return response;
                    };

                    response.setContentType(Http.ContentType.OctetStream) catch {
                        response.setStatus(Http.Status.InternalServerError);
                        response.setBody("Error setting content type") catch {};
                        return response;
                    };
                    response.setStatus(Http.Status.OK);
                    return response;
                } else if (_request.method == Http.Method.POST) {

                }
            }

            response.setStatus(Http.Status.NotFound);
            return response;
        }
    }.f);

    return server.run();
}
