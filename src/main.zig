const std = @import("std");
const config = @import("config");
// const Server = @import("http_l"); // Reimport this when releasing project
const Server = @import("Server.zig");
const Router = Server.Router;
const Ctx = Router.Ctx;

const Handler = Router.Handler;
const HandlerFn = Router.HandlerFn;

const log = std.log;
const Io = std.Io;
const Error = Io.Writer.Error;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    const arena = init.arena;

    // var allocator: std.heap.DebugAllocator(.{ .thread_safe = true, .verbose_log = true }) = .init;
    // defer _ = allocator.deinit();
    // const gpa = allocator.allocator();

    // var threaded: std.Io.Threaded = .init(gpa, .{ .environ = init.environ });
    // defer threaded.deinit();
    // const io: std.Io = threaded.io();
    // // Evented Io for testing (NOT CURRENTLY WORKING)
    // var evented: std.Io.Evented = undefined;
    // try evented.init(gpa, .{
    //     .argv0 = .init(init.args),
    //     .environ = init.environ,
    //     .backing_allocator_needs_mutex = false,
    // });
    // defer evented.deinit();
    // const io = evented.io();

    var router = Router.init(.{
        .{ "/*", &[_]HandlerFn{ &Middlewares.loggingMiddleware, &Endpoints.serveStatic } },
        // .{ "/home.html", &[_]HandlerFn{ &Middlewares.loggingMiddleware, &Endpoints.home } },
        // .{ "/about.html", &[_]HandlerFn{ &Middlewares.loggingMiddleware, &Endpoints.about } },
        // .{ "/contact.html", &[_]HandlerFn{ &Middlewares.loggingMiddleware, &Endpoints.contact } },
    });
    defer router.deinit(gpa);

    const server: Server = try .init(gpa, arena, config.host, config.port, io, router);

    log.info("Server listening on port {d}...", .{config.port});

    try server.listenAndServe();
}

const Endpoints = struct {
    // pub fn home(ctx: *Ctx) !void {
    //     switch (ctx.req.method) {
    //         .GET => {
    //             // Read static dir for file called home.html
    //             const io = ctx.io;
    //             const cwd = std.Io.Dir.cwd();
    //             const file_dir = try std.Io.Dir.openDir(cwd, io, config.static_dir, .{ .iterate = true });
    //             const index_file = try file_dir.openFile(io, "home.html", .{});
    //             try ctx.resp.write_file(io, index_file, .HTML);
    //         },
    //         else => {},
    //     }
    // }
    // pub fn about(ctx: *Ctx) !void {
    //     switch (ctx.req.method) {
    //         .GET => {
    //             const io = ctx.io;
    //             const cwd = std.Io.Dir.cwd();
    //             const file_dir = try std.Io.Dir.openDir(cwd, io, config.static_dir, .{ .iterate = true });
    //             const index_file = try file_dir.openFile(io, "about.html", .{});
    //             try ctx.resp.write_file(io, index_file, .HTML);
    //         },
    //         else => {},
    //     }
    // }
    // pub fn contact(ctx: *Ctx) !void {
    //     switch (ctx.req.method) {
    //         .GET => {
    //             const io = ctx.io;
    //             const cwd = std.Io.Dir.cwd();
    //             const file_dir = try std.Io.Dir.openDir(cwd, io, config.static_dir, .{ .iterate = true });
    //             const index_file = try file_dir.openFile(io, "contact.html", .{});
    //             try ctx.resp.write_file(io, index_file, .HTML);
    //         },
    //         else => {},
    //     }
    // }
    pub fn serveStatic(ctx: *Ctx) !void {
        switch (ctx.req.method) {
            .GET => {
                const parsed = ctx.req.parseQueryParams().?;
                const file_name = if (std.mem.eql(u8, parsed, "")) "index.html" else parsed;

                const io = ctx.io;
                const cwd = std.Io.Dir.cwd();
                const file_dir = try std.Io.Dir.openDir(cwd, io, config.static_dir, .{ .iterate = true });
                const index_file = file_dir.openFile(io, file_name, .{}) catch |err| switch (err) {
                    error.FileNotFound => {
                        log.warn("Attempted to reach unknown file: {s}", .{ctx.req.uri});
                        try ctx.resp.write_response(.NOTFOUND, "File not found");
                        return;
                    },
                    else => {
                        log.err("{any}\n", .{err});
                        return err;
                    },
                };

                var mime_type = Router.MimeType.UNIDENTIFIED;
                if (std.mem.eql(u8, file_name[file_name.len - 4 ..], "html")) {
                    mime_type = .HTML;
                } else if (std.mem.eql(u8, file_name[file_name.len - 3 ..], "css")) {
                    mime_type = .CSS;
                } else if (std.mem.eql(u8, file_name[file_name.len - 2 ..], "js")) {
                    mime_type = .JAVASCRIPT;
                }
                ctx.resp.write_file(
                    io,
                    index_file,
                    mime_type,
                ) catch |err| {
                    std.log.err("{s}", .{@errorName(err)});
                };
            },
            else => {
                // Add errors for using serveStatic incorrectly
                unreachable;
            },
        }
    }
};

const Middlewares = struct {
    fn loggingMiddleware(ctx: *Ctx) !void {
        // std.log.info("From Logging Middleware: {s}", .{ctx.req.uri});
        _ = ctx;
    }
};
