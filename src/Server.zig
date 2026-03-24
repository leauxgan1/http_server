// All state and associated methods of the server go here

const std = @import("std");
const request = @import("request.zig");
const response = @import("response.zig");
pub const Router = @import("Router.zig");

const log = std.log;
const net = std.net;
const Io = std.Io;
const Socket = std.Io.net.Socket;
const Protocol = std.Io.net.Protocol;

const Server = @This();

host: []const u8,
port: u16,
addr: Io.net.IpAddress,
io: Io,
allocator: std.mem.Allocator,
arena: ?std.heap.ArenaAllocator,
router: ?Router,

pub fn init(allocator: std.mem.Allocator, host: []const u8, port: u16, io: Io, router: ?Router) !Server {
    const address: Io.net.IpAddress = try .parseIp4(host, port);
    return .{
        .allocator = allocator,
        .host = host,
        .port = port,
        .addr = address,
        .io = io,
        .arena = null,
        .router = router,
    };
}

pub fn listen(self: Server) !std.Io.net.Server {
    return try self.addr.listen(self.io, .{ .mode = Socket.Mode.stream, .protocol = Protocol.tcp, .reuse_address = true });
}
pub fn listenAndServe(self: Server) !void {
    var listening = try self.addr.listen(self.io, .{ .mode = Socket.Mode.stream, .protocol = Protocol.tcp, .reuse_address = true });
    defer listening.deinit(self.io);

    while (true) { // Continue listening for new requests until program is terminated
        const conn = try listening.accept(self.io);
        defer conn.close(self.io);

        var req_buffer: [1024]u8 = undefined;
        @memset(req_buffer[0..], 0);

        var resp_buffer: [1024]u8 = undefined;
        @memset(resp_buffer[0..], 0);

        var req = try request.Request.from_conn(self.allocator, self.io, conn, req_buffer[0..]);
        defer req.deinit(self.allocator);

        var writer_interface = conn.writer(self.io, resp_buffer[0..]);
        const writer = &writer_interface.interface;

        var resp = response.Response.init(
            writer,
        );
        log.info("{s}", .{req.uri});

        try self.router.?.route(&req, &resp);
    }
}

const FileServerOptions = struct {
    recursive: bool = false,
};
