const std = @import("std");

const Scanner = @This();

line:usize = 1,
mem:std.ArrayList(u8) = .empty,
reader:*std.Io.Reader,

pub fn init(reader:*std.Io.Reader) !Scanner {
    return .{ .reader = reader };
}
