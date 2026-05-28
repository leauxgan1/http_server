const std = @import("std");
const request = @import("request.zig");
const response = @import("response.zig");

static_routes: std.StaticStringMap(Handler),
dynamic_routes: std.StringHashMapUnmanaged(Handler),

const Router = @This();

pub const Ctx = struct {
    io: std.Io,
    req: *request.Request,
    resp: *response.Response,
};

/// HandlerFn is the structure of a middleware or an endpoint function which receives a context for the current request and response
/// The context is passed between middleware and may be modified by them until the response is written and the connection closed
pub const HandlerFn = *const fn (*Ctx) anyerror!void;

pub const Handler = []const HandlerFn;

pub const MimeType = enum {
    HTML,
    CSS,
    JAVASCRIPT,
    UNIDENTIFIED,

    pub fn fromFileStr(file_name: []const u8) MimeType {
        const filetype_idx = std.mem.indexOfScalar(u8, file_name, '.') orelse return .UNIDENTIFIED;
        const ending = file_name[filetype_idx..];
        if (std.mem.eql(u8, ending, "htm") or std.mem.eql(u8, ending, "html")) {
            return .HTML;
        } else if (std.mem.eql(u8, ending, "css")) {
            return .CSS;
        } else if (std.mem.eql(u8, ending, "js")) {
            return .JAVASCRIPT;
        }
        return .UNIDENTIFIED;
    }

    pub fn toStr(mime: MimeType) []const u8 {
        return switch (mime) {
            .HTML => "text/html; charset=utf-8",
            .CSS => "text/css",
            .JAVASCRIPT => "application/javascript",
            .UNIDENTIFIED => "",
        };
    }
};

// Eventually make listings more structured with below
// const RouteListing = struct {
//     uri: []const u8,
//     handler: Handler,
// };

pub fn init(listings: anytype) Router {
    // Receiving input like .{.{"/uri", .{list,of,handlers}}}
    // Want to transform into .{.{"/uri",[_]HandlerList{list,of,handlers}}}
    // So that we can pass it as one item into .initComptime for the StaticStringMap
    return .{
        .static_routes = .initComptime(listings),
        .dynamic_routes = std.StringHashMapUnmanaged(Handler){},
    };
}
pub fn deinit(
    self: *Router,
    allocator: std.mem.Allocator,
) void {
    self.dynamic_routes.deinit(allocator);
}
pub fn addDynRoute(self: *Router, allocator: std.mem.Allocator, url: []const u8, handler: Handler) !void {
    try self.dynamic_routes.put(allocator, url, handler);
}

// Pattern matches a given request's uri against all static and dynamic routes, pattern matching on the following patterns
// [X] Wildcard : /*
// [X] Named Groups: /users/:id
// [] Non-Capturing Groups: /users{/new}?
// [] Regexp Groups: /users/(\\d+)
// Any additional information from the URI is stored in the request via QueryParams
// DECISION:
// 1) Only check for matches in scan and dont mess with req until handler?
//    PRO - Dont store more necessarily allocated memory in each req
//    CON - Duplicates work of scanning URI against base URI (but only O(1) not O(n))
//    CON - Most of the time, needing to verify will also imply needing to parse
// 2) Or parse for all patterns and store in req?
//    PRO - Avoid duplicating work
//    CON - Have to figure out data stores for different kinds of request data (arraylist for wildcard, map for keyval)
//
// Going with 2
fn matchRequest(self: *const Router, req: *request.Request) ?Handler {
    const req_uri = req.uri;
    for (self.static_routes.keys()) |key| {
        var base_tokens = std.mem.splitBackwardsScalar(u8, key, '/');
        var req_tokens = std.mem.splitBackwardsScalar(u8, req_uri, '/');
        while (true) {
            const curr_base = base_tokens.next();
            const curr_req = req_tokens.next();
            if (curr_base == null and curr_req == null) {
                // Reached end of both without issue, this is a match
                std.log.info("Setting base_uri to {s}", .{key});
                req.base_uri = key; // Store base uri for parsing later
                return self.static_routes.get(key);
            } else if (curr_base == null or curr_req == null) {
                return null; // Reached end of either base or req with more tokens remaining on counterpart
            } else { // neither null
                const t_base = curr_base.?;
                const t_req = curr_req.?;
                if (std.mem.eql(u8, t_base, "*") or t_base.len > 0 and t_base[0] == ':') {
                    continue; // Ignore checking for equality with wildcards or capturing groups
                }
                if (!std.mem.eql(u8, t_base, t_req)) {
                    return null;
                }
            }
        }
    }
    var dyn_key_iter = self.dynamic_routes.keyIterator();
    while (dyn_key_iter.next()) |key| {
        var base_tokens = std.mem.splitBackwardsScalar(u8, key.*, '/');
        var req_tokens = std.mem.splitBackwardsScalar(u8, req_uri, '/');
        while (true) {
            const curr_base = base_tokens.next();
            const curr_req = req_tokens.next();
            if (curr_base == null and curr_req == null) {
                // Reached end of both without issue, this is a match
                std.log.info("Setting base_uri to {s}", .{key.*});
                req.base_uri = key.*;
                return self.static_routes.get(key.*);
            } else if (curr_base == null or curr_req == null) {
                return null; // Reached end of either base or req with more tokens remaining on counterpart
            } else { // neither null
                const t_base = curr_base.?;
                const t_req = curr_req.?;
                if (std.mem.eql(u8, t_base, "*") or t_base.len > 0 and t_base[0] == ':') {
                    continue; // Ignore checking for equality with wildcards or capturing groups
                }
                if (!std.mem.eql(u8, t_base, t_req)) {
                    return null;
                }
            }
        }
    }
    return null;
}

pub fn route(self: *const Router, io: std.Io, req: *request.Request, resp: *response.Response) !void {
    // Prioritize exact matches
    if (self.static_routes.has(req.uri)) {
        const handler: Handler = self.static_routes.get(req.uri).?;
        var ctx: Ctx = .{
            .io = io,
            .req = req,
            .resp = resp,
        };

        for (handler) |h| {
            h(&ctx) catch |err| {
                std.log.err("err: {s}", .{@typeName(@TypeOf(err))});
                return;
            };
        }
        // } else if (self.dynamic_routes.contains(req.uri)) {
        //     // Defer to dynamic routes if not found in static
        //     const handler = self.dynamic_routes.get(req.uri).?;
        //     try handler(.{ .req = req, .resp = resp });
    } else {
        // Attempt pattern matching
        const matched_handler: ?Handler = self.matchRequest(req);
        if (matched_handler) |handler| {
            var ctx: Ctx = .{
                .io = io,
                .req = req,
                .resp = resp,
            };
            for (handler) |h| {
                h(&ctx) catch |err| {
                    std.log.err("err: {s}", .{@typeName(@TypeOf(err))});
                    return;
                };
            }
        } else {
            // All else fails,
            try resp.write_response(.NOTFOUND, "<html><body>Route not found</body></html>");
        }
    }
}
test "Init Router with Varying Lengths of Handlers" {
    const ta = std.testing.allocator;
    const Endpoints = struct {
        pub fn home(ctx: *Ctx) anyerror!void {
            try ctx.resp.write_body(try std.fmt.allocPrint(ta, "Current method is: {d}...\n", .{@intFromEnum(ctx.req.method)}));
            std.debug.assert(ctx.req.method == .DELETE);
            try ctx.resp.write_response(.OK, "You have reached the home page!");
        }
    };

    const Middleware = struct {
        pub fn changeURI(ctx: *Ctx) anyerror!void {
            ctx.req.method = .DELETE;
        }
    };

    const routes = Router.init(.{
        .{ "/home", &[_]HandlerFn{&Endpoints.home} },
        .{ "/hometwo", &[_]HandlerFn{ &Middleware.changeURI, &Endpoints.home } },
    });
    _ = routes;
}
