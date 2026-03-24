const std = @import("std");
const Params = @import("Params.zig");
const Stream = std.Io.net.Stream;

pub const Method = enum {
    GET,
    POST,
    PUT,
    PATCH,
    DELETE,
    pub fn init(method_str: []const u8) !Method {
        return MethodMap.get(method_str).?;
    }
    pub fn is_supported(method_str: []const u8) !bool {
        const method = MethodMap.get(method_str);
        if (method) |_| {
            return true;
        }
        return false;
    }
};
pub const MethodMap = std.StaticStringMap(Method).initComptime(.{
    .{ "GET", Method.GET },
    .{ "POST", Method.POST },
    .{ "PUT", Method.PUT },
    .{ "PATCH", Method.PATCH },
    .{ "DELETE", Method.DELETE },
});

pub const Request = struct {
    io: std.Io,
    method: Method,
    uri: []const u8,
    version: []const u8,
    headers: std.StringHashMapUnmanaged([]const u8),
    base_uri: ?[]const u8 = null,
    params: ?Params,

    pub const InitError = error{ContentLengthUnspecified};

    // TODO: handle many wildcards and groups and return a list of them
    pub fn parseQueryParams(self: Request) ?[]const u8 {
        if (self.base_uri) |base| {
            var base_iter = std.mem.splitBackwardsScalar(u8, base, '/');
            var uri_iter = std.mem.splitBackwardsScalar(u8, self.uri, '/');
            while (true) {
                const base_next = base_iter.next();
                const uri_next = uri_iter.next();
                if (base_next != null and uri_next != null) {
                    const b_next = base_next.?;
                    const u_next = uri_next.?;
                    if (b_next.len >= 0 and b_next[0] == '*') {
                        return u_next; // Early return if value found
                    }
                } else {
                    break;
                }
            }
        }
        return null;
    }

    pub fn from_conn(allocator: std.mem.Allocator, io: std.Io, conn: Stream, req_buffer: []u8) !Request {
        var sink_buffer: [1024]u8 = undefined;
        var conn_reader = conn.reader(io, &sink_buffer);
        const reader = &conn_reader.interface;

        var req: Request = .{
            .io = io,
            .method = .GET,
            .uri = "/",
            .version = "1.1",
            .headers = .{},
            .params = null,
        };

        // Read until body reached
        const length = try readUntilBody(reader, req_buffer);

        // Parse status line first, as we may need to err out at header parsing step depending on method
        const status_line_idx = std.mem.indexOfScalar(u8, req_buffer, '\n') orelse req_buffer.len;
        try req.parseStatus(req_buffer[0..status_line_idx]);

        try req.headers.ensureTotalCapacity(allocator, 1024);
        // Parse headers
        try req.parseHeaders(allocator, req_buffer[status_line_idx + 1 .. length]);

        // Handle improper initialization
        if (req.method == .POST or req.method == .PUT or req.method == .PATCH or req.method == .DELETE and req.headers.get("Content-Length") == null) {
            return InitError.ContentLengthUnspecified;
        }

        // Read and parse body
        std.log.info("Created a new request", .{});
        return req;
    }
    pub fn deinit(self: *Request, allocator: std.mem.Allocator) void {
        self.headers.deinit(allocator);
    }
    fn readUntilBody(reader: *std.Io.Reader, req_buffer: []u8) !usize {
        var curr_idx: usize = 0;

        while (true) {
            const curr_line = try reader.takeDelimiterInclusive('\n'); // Batch writes by lines
            if (curr_line.len < 3) { // Found empty line, reached body
                break;
            }
            @memcpy(
                req_buffer[curr_idx..(curr_idx + curr_line.len)],
                curr_line[0..],
            );
            curr_idx += curr_line.len;
        }
        return curr_idx;
    }

    fn parseStatus(self: *Request, status_line: []u8) !void {
        var line_iter = std.mem.splitScalar(u8, status_line, ' ');

        const method = try Method.init(line_iter.next().?);
        const uri = line_iter.next().?;
        const version = line_iter.next().?;

        self.method = method;
        self.uri = uri;
        self.version = version;
    }
    fn parseHeaders(self: *Request, allocator: std.mem.Allocator, header_lines: []u8) !void {
        var iter = std.mem.splitScalar(u8, header_lines, '\n');
        while (iter.next()) |line| {
            std.log.info("{s}", .{line});
            var split = std.mem.splitSequence(u8, line, ": ");
            const header_name = split.next() orelse break;
            const header_val = split.next() orelse break;
            try self.headers.put(allocator, header_name, header_val);
        }
    }
    fn readBody() void {}
    fn parseBody() void {}
};
