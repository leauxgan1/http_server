// All state and associated methods of the server go here

const std = @import("std");
const request = @import("request.zig");
const response = @import("response.zig");
const Router = @import("Router.zig");
const net = std.net;
const Io = std.Io;
const Socket = std.Io.net.Socket;
const Protocol = std.Io.net.Protocol;

const Server = @This();

host: []const u8,
port: u16,
addr: Io.net.IpAddress,
io: Io,

pub fn init(host: []const u8, port: u16, io: Io) !Server {
    const address: Io.net.IpAddress = try .parseIp4(host, port);
    return .{
        .host = host,
        .port = port,
        .addr = address,
        .io = io,
    };
}

pub fn listen(self: Server) !std.Io.net.Server {
    return try self.addr.listen(self.io, .{ .mode = Socket.Mode.stream, .protocol = Protocol.tcp, .reuse_address = true });
}

const FileServerOptions = struct {
    recursive: bool = false,
};

// Adds an additional route which serves files from a given url as a base and extends with each file name
pub fn addFileServer(self: *Server, allocator: std.mem.Allocator, url: []const u8, dir: Io.Dir) !void {
    // Iterate over files in dir
    // make new dynamic routes which correspond to files and return files upon being reached by router
    _ = url;
    _ = dir;

    try self.router.dynamic_routes.put(allocator, "", serveFile);
}

pub fn serveFile(req: *request.Request, res: *response.Response) std.Io.Writer.Error!void {
    _ = req;
    _ = res;
}
