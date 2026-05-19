const std = @import("std");
const common = @import("common.zig");

const Token = @import("token.zig");
const Chunk = @import("chunk.zig").Chunk;
const CodeByte = common.CodeByte;
const OpCode = @import("chunk.zig").OpCode;
const Value = @import("value.zig").Value;
const Tokenizer = @import("tokenizer.zig");

const Tokenized = Tokenizer.TokenizeResult.Tokenized;

const Compiler = @This();

pub fn do(in:Tokenized, alloc:std.mem.Allocator, mode:common.Mode) !Chunk {
    var ptrs:std.AutoHashMap(usize, union(enum) {
        pos:?usize,
        val:u16,
    }) = .init(alloc);
    defer ptrs.deinit();
    var res:Chunk = .init(alloc, try .init(std.math.maxInt(u16), mode));
    if (in.tokens.len == 0) {
        try res.add_op(.push, 0);
        _ = try res.add_const(.void, 0);
        try res.add_op(.@"return", 0);
    } else
        try res.add_op(.no_op, 0);

    for (in.positions) |pos| {
        std.debug.print("{d}\n", .{pos});
        try ptrs.put(pos, .{ .pos = null });
    }

    for (in.tokens) |tok| {
        switch (tok.value) {
            .literal => |lit| _ = try res.add_const(lit, tok.line),
            .opcode => |op| try res.add_op(op, tok.line),
            .ptr => |ptr| {
                if (ptr == .def) {
                    if (ptrs.getPtr(ptr.def.get_ident())) |pos| {
                        pos.pos = res.code.items.len;
                    } else
                        try ptrs.put(ptr.def.get_ident(), switch (ptr.def) {
                            .pos => .{ .pos = res.code.items.len },
                            .val => |i| .{ .val = @intCast(i) },
                        });
                    continue;
                }
                const p:@import("value.zig").Value = switch (ptrs.get(ptr.use.val).?) {
                    .pos => |p|
                        .{ .pos =
                            if (p) |pos|
                                .{ .pos = pos }
                            else
                                .{ .ident = ptr.use.val }
                        },
                    .val => |v| .{
                        .ptr = .{
                            .ident = v,
                            .val = null,
                        },
                    }
                };
                _ = try res.add_const(p, tok.line);
            },
        }
    }

    for (res.constants.items) |*constant| switch (constant.*) {
        .pos => |*pos|
            if (pos.* == .ident) {
                const ident = pos.ident;
                pos.* = .{ .pos = ptrs.get(ident).?.pos orelse std.debug.panic("{d}", .{ident}) };
            },
        else => {},
    };

    return res;
}
