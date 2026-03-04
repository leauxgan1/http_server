const std = @import("std");
const request = @import("request.zig");
const response = @import("response.zig");
const Server = @import("Server.zig");
const Router = @import("Router.zig");

const log = std.log;
const Io = std.Io;
const net = Io.net;
const Error = Io.Writer.Error;

const IP = "127.0.0.1";
const PORT = 8080;
const STATIC_DIR = "static";

pub fn main(init: std.process.Init.Minimal) !void {
    var alloc: std.heap.DebugAllocator(.{ .thread_safe = true, .verbose_log = true }) = .init;
    defer _ = alloc.deinit();
    const dba = alloc.allocator();

    var threaded: std.Io.Threaded = .init(dba, .{ .environ = init.environ });
    defer threaded.deinit();
    const io: std.Io = threaded.io();

    var router = Router.init(.{
        .{ "/*", &RouterImpl.serveStatic },
        // .{ "/about", &RouterImpl.about },
        // .{ "/contact", &RouterImpl.contact },
    });
    defer router.deinit(dba);

    // try router.addDynRoute(dba, "/index.html", RouterImpl.serveStatic);

    const server: Server = try .init(IP, PORT, io);

    var listening = try server.listen();
    defer listening.deinit(io);

    log.info("Server listening on port {d}...", .{PORT});

    while (true) { // Continue listening for new requests until program is terminated
        const conn = try listening.accept(io);
        defer conn.close(io);

        var req_buffer: [1024]u8 = undefined;
        @memset(req_buffer[0..], 0);

        var resp_buffer: [1024]u8 = undefined;
        @memset(resp_buffer[0..], 0);

        var req = try request.Request.from_conn(dba, io, conn, req_buffer[0..]);
        defer req.deinit(dba);

        var writer_interface = conn.writer(io, resp_buffer[0..]);
        const writer = &writer_interface.interface;

        var resp = response.Response.init(
            writer,
        );
        log.info("{s}", .{req.uri});

        try router.route(&req, &resp);
    }
}
const RouterImpl = struct {
    pub fn home(req: *request.Request, resp: *response.Response) Error!void {
        // Check Request Method
        switch (req.method) {
            .GET => {
                try resp.write_response(.OK, "<html><body><h1>You have reached the home page!!!</h1></body></html>");
            },
            .POST => {},
            .PUT => {},
            .PATCH => {},
            .DELETE => {},
        }
    }
    pub fn about(req: *request.Request, resp: *response.Response) !void {
        switch (req.method) {
            .GET => {
                try resp.write_response(.OK, "<html><body><h1>I am an about</h1></body></html>");
            },
            .POST => {},
            .PUT => {},
            .PATCH => {},
            .DELETE => {},
        }
    }
    pub fn contact(req: *request.Request, resp: *response.Response) !void {
        switch (req.method) {
            .GET => {
                try resp.write_response(.OK, "<html><body><h1>I am a contact</h1></body></html>");
            },
            .POST => {},
            .PUT => {},
            .PATCH => {},
            .DELETE => {},
        }
    }
    pub fn serveStatic(req: *request.Request, resp: *response.Response) !void {
        switch (req.method) {
            .GET => {
                const parsed = req.parseQueryParams().?;

                const cwd = std.Io.Dir.cwd();
                const file_dir = try std.Io.Dir.openDir(cwd, req.io, STATIC_DIR, .{ .iterate = true });
                const index_file = file_dir.openFile(req.io, parsed, .{}) catch |err| switch (err) {
                    error.FileNotFound => {
                        log.warn("Attempted to reach unknown file: {s}", .{req.uri});
                        try resp.write_response(.NOTFOUND, "File not found");
                        return;
                    },
                    else => {
                        return err;
                    },
                };

                try resp.write_status(.OK);
                try resp.write_header("Access-Control-Allow-Origin", "*");
                try resp.write_header("Content-Type", Router.MimeType.fromFileStr(parsed).toStr());

                try resp.end_header();

                // Read out contents of file
                var file_buf: [1024]u8 = undefined;
                var file_reader = index_file.reader(req.io, &file_buf);
                var reader = &file_reader.interface;

                while (try reader.takeDelimiter('\n')) |l| {
                    try resp.write_body(l);
                }
                try resp.writer.flush();
            },
            else => {},
        }
    }
};
