const std = @import("std");
const request = @import("request.zig");
const response = @import("response.zig");

static_routes: std.StaticStringMap(Handler),
dynamic_routes: std.StringHashMapUnmanaged(Handler),

const Router = @This();
const Handler = *const fn (*request.Request, *response.Response) anyerror!void;
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

pub fn init(comptime kvs: anytype) Router {
    return .{
        .static_routes = .initComptime(kvs),
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
fn matchRequest(self: *Router, req: *request.Request) !?Handler {
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

pub fn route(self: *Router, req: *request.Request, res: *response.Response) !void {
    // Prioritize exact matches
    if (self.static_routes.has(req.uri)) {
        const handler = self.static_routes.get(req.uri).?;
        try handler(req, res);
    } else if (self.dynamic_routes.contains(req.uri)) {
        // Defer to dynamic routes if not found in static
        const handler = self.dynamic_routes.get(req.uri).?;
        try handler(req, res);
    } else {
        // Attempt pattern matching
        const matched_handler = try self.matchRequest(req);
        if (matched_handler) |handler| {
            try handler(req, res);
        } else {
            // All else fails,
            try res.write_response(.NOTFOUND, "<html><body>Route not found</body></html>");
        }
    }
}
