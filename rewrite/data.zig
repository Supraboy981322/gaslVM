const std = @import("std");

const Self = @This();

alloc:std.mem.Allocator,

pub fn init(alloc:std.mem.Allocator) !Self {
    return .{ .alloc = alloc };
}

pub fn deinit(self:*Self) void {
    _ = self;
}
