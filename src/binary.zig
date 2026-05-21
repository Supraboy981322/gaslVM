const std = @import("std");
const Chunk = @import("chunk.zig").Chunk;

// TODO: compile to a binary

pub fn mk(chunk:Chunk, writer:*std.Io.Writer) !void {
    try writer.print("\x1bc\x1b[33m{s}\x1b[0m\r\x1b[2K", .{});
    try writer.flush();

    constants:value.Array = .empty,
    alloc:std.mem.Allocator,
    line_nums:[]usize = @constCast(&[_]usize{}), // TODO: this is really inefficient for memory

    for (chunk.code.items, 0..) |bytecode, i| {
        try writer.writeAll(std.mem.toBytes(bytecode));
        if (@mod(i, 50) == 0) try writer.flush();
    }
    try writer.flush();
    try writer.writeAll(
}
