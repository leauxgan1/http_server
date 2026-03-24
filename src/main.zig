const std = @import("std");
const config = @import("config");
// const Server = @import("http_l"); // Reimport this when releasing project
const Server = @import("Server.zig");
const Router = Server.Router;
const Ctx = Router.Ctx;

const Handler = Router.Handler;

const log = std.log;
const Io = std.Io;
const Error = Io.Writer.Error;

pub fn main(init: std.process.Init.Minimal) !void {
    var alloc: std.heap.DebugAllocator(.{ .thread_safe = true, .verbose_log = true }) = .init;
    defer _ = alloc.deinit();
    const dba = alloc.allocator();

    var threaded: std.Io.Threaded = .init(dba, .{ .environ = init.environ });
    defer threaded.deinit();
    const io: std.Io = threaded.io();

    var router = Router.init(.{
        .{
            "/*", Handler{
                .handle = &Endpoints.serveStatic,
            },
        },
        .{ "/home", Handler{ .handle = &Middlewares.loggingMiddleware, .next = &Handler{ .handle = &Endpoints.home } } },
        .{ "/about", Handler{ .handle = &Endpoints.about } },
        .{ "/contact", Handler{ .handle = &Endpoints.contact } },
    });
    defer router.deinit(dba);

    const server: Server = try .init(dba, config.host, config.port, io, router);

    log.info("Server listening on port {d}...", .{config.port});

    try server.listenAndServe();
}

const Endpoints = struct {
    pub fn home(ctx: *Ctx) !void {
        switch (ctx.req.method) {
            .GET => {
                try ctx.resp.write_response(.OK, "<html><body><h1>You have reached the home page!!!</h1></body></html>");
            },
            .POST => {},
            .PUT => {},
            .PATCH => {},
            .DELETE => {},
        }
    }
    pub fn about(ctx: *Ctx) !void {
        switch (ctx.req.method) {
            .GET => {
                try ctx.resp.write_response(.OK, "<html><body><h1>I am an about</h1><a href='/contact'> contact </a></body></html>");
            },
            .POST => {},
            .PUT => {},
            .PATCH => {},
            .DELETE => {},
        }
    }
    pub fn contact(ctx: *Ctx) !void {
        switch (ctx.req.method) {
            .GET => {
                try ctx.resp.write_response(.OK, "<html><body><h1>I am a contact</h1> <a href='/about'> about </a></body></html>");
            },
            .POST => {},
            .PUT => {},
            .PATCH => {},
            .DELETE => {},
        }
    }
    pub fn serveStatic(ctx: *Ctx) !void {
        switch (ctx.req.method) {
            .GET => {
                const parsed = ctx.req.parseQueryParams().?;
                const file_name = if (std.mem.eql(u8, parsed, "")) "index.html" else parsed;

                std.log.warn("{s}", .{parsed});

                const cwd = std.Io.Dir.cwd();
                const file_dir = try std.Io.Dir.openDir(cwd, ctx.req.io, config.static_dir, .{ .iterate = true });
                const index_file = file_dir.openFile(ctx.req.io, file_name, .{}) catch |err| switch (err) {
                    error.FileNotFound => {
                        log.warn("Attempted to reach unknown file: {s}", .{ctx.req.uri});
                        try ctx.resp.write_response(.NOTFOUND, "File not found");
                        return;
                    },
                    else => {
                        return err;
                    },
                };

                try ctx.resp.write_status(.OK);
                try ctx.resp.write_header("Access-Control-Allow-Origin", "*");
                try ctx.resp.write_header("Content-Type", Router.MimeType.fromFileStr(parsed).toStr());

                try ctx.resp.end_header();

                // Read out contents of file
                var file_buf: [1024]u8 = undefined;
                var file_reader = index_file.reader(ctx.req.io, &file_buf);
                var reader = &file_reader.interface;

                while (try reader.takeDelimiter('\n')) |l| {
                    try ctx.resp.write_body(l);
                }
                try ctx.resp.writer.flush();
            },
            else => {},
        }
    }
};

const Middlewares = struct {
    fn loggingMiddleware(ctx: *Ctx) !void {
        std.log.info("{s}", .{ctx.req.uri});
    }
};
