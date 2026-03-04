const std = @import("std");

const Params = @This();

// Temp structure for param storage, will optimize for space based on a maximum number of params * maximum length per param name and value
paramMap: std.StringArrayHashMapUnmanaged([]const u8),

pub fn init() !Params {
    return .{
        .paramMap = .empty,
    };
}
pub fn deinit(self: *Params, allocator: std.mem.Allocator) void {
    self.paramMap.deinit(allocator);
}
pub fn putParam(self: *Params, allocator: std.mem.Allocator, key: []const u8, val: []const u8) void {
    try self.paramMap.put(allocator, key, val);
}
pub fn readParam(self: *Params, key: []const u8) ?[]const u8 {
    return self.paramMap.get(key) orelse null;
}
