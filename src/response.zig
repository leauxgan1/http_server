const std = @import("std");
const Router = @import("Router.zig");

const fmt = std.fmt;
const Io = std.Io;
const Stream = std.Io.net.Stream;

const responseTemplate =
    \\HTTP/1.1 {d} {s}
    \\Content-Length: {d}
    \\Content-Type: text/html
    \\Connection: Closed
    \\
    \\{s}
;
const statusTemplate =
    \\HTTP/1.1 {d} {s}
    \\
;
const headerTemplate =
    \\{s}: {s}
    \\
;
const htmlBodyTemplate =
    \\<!DOCTYPE html>
    \\<html>
    \\  <head>
    \\  </head>
    \\  <body>
    \\    {s}
    \\  </body>
    \\</html>
;

pub const Response = struct {
    writer: *Io.Writer,
    pub fn init(writer: *Io.Writer) Response {
        return .{
            .writer = writer,
        };
    }
    pub fn write_status(self: *Response, status: Status) Io.Writer.Error!void {
        _ = try self.writer.print(statusTemplate, .{ status, status.toStr() });
    }
    pub fn write_header(self: *Response, header_key: []const u8, header_value: []const u8) Io.Writer.Error!void {
        _ = try self.writer.print(headerTemplate, .{ header_key, header_value });
    }
    pub fn end_header(self: *Response) !void {
        _ = try self.writer.write("\n\n");
    }
    pub fn write_body(self: *Response, bytes: []const u8) Io.Writer.Error!void {
        _ = try self.writer.writeAll(bytes);
    }
    pub fn write_response(self: *Response, status: Status, message: []const u8) Io.Writer.Error!void {
        _ = try self.writer.print(responseTemplate, .{ status, status.toStr(), message.len, message });
        try self.writer.flush();
    }
    pub fn write_file(
        self: *Response,
        io: std.Io,
        file: std.Io.File,
        file_type: Router.MimeType,
    ) !void {
        try self.write_status(.OK);
        try self.write_header("Access-Control-Allow-Origin", "*");
        try self.write_header("Content-Type", file_type.toStr());
        // try self.write_header("Content-Security-Policy", "script-src 'self'");

        try self.end_header();

        // Read out contents of file
        var file_buf: [2048]u8 = undefined;
        var file_reader = file.reader(io, &file_buf);
        var reader = &file_reader.interface;

        // Read and write bytes to the buffer
        while (true) {
            const bytes = reader.take(100) catch |err| switch (err) {
                error.EndOfStream => {
                    const rest = reader.buffered();
                    if (rest.len > 0) {
                        try self.write_body(rest);
                    }
                    break;
                },
                error.ReadFailed => {
                    return err;
                },
            };
            try self.write_body(bytes);
        }

        try self.writer.flush();
    }
    // pub fn write_err(self: *Response, status: Status, message: []const u8) Io.Writer.Error!void {
    //     _ = try self.writer.print(responseTemplate, .{ status, status.toStr(), message.len, message });
    // }
};

pub const Status = enum(u32) {
    OK = 200,
    BADRESPONSE = 400,
    NOTFOUND = 404,
    inline fn toStr(self: Status) []const u8 {
        return switch (self) {
            .OK => "OK",
            .NOTFOUND => "NOT FOUND",
            .BADRESPONSE => "BAD RESPONSE",
        };
    }
};
