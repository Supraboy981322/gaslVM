const std = @import("std");
const Chunk = @import("chunk.zig").Chunk;
const OpCode = @import("chunk.zig").OpCode;
const CodeByte = @import("chunk.zig").CodeByte;
const value = @import("value.zig");

pub fn dissassemble_chunk(chunk:*Chunk) void {
    var i:usize = 0;
    while (i < chunk.code.items.len) : (i += 1)
        disassemble_instruction(chunk, &i);
}

pub fn disassemble_instruction(chunk:*Chunk, i:*usize) void {
    const op:OpCode = @enumFromInt(chunk.code.items[i.*].code);
    defer std.debug.print("\n", .{});
    std.debug.print("[line {d}] ({d}) {s} ", .{chunk.line_nums[i.*], op, @tagName(op)});
    switch (op) {
        .@"return" => {},
        .constant => {
            const v = const_instruction(chunk, i);
            i.* += 1;
            std.debug.print("{any}", .{v});
        },
        else => unreachable, //unknown OpCode
    }
}

pub fn simple_instruction(chunk:*Chunk, i:*usize) ?CodeByte {
    if (i.* + 1 >= chunk.code.items.len) return null;
    return chunk.code.items[i.*+1];
}

pub fn const_instruction(chunk:*Chunk, i:*usize) value.Value {
    return chunk.get_const(i.*+1);
}

pub fn print_token(token:@import("token.zig").Token) void {
    std.debug.print("({d}) ", .{token.line});
    switch (token.value) {
        .opcode => |i| std.debug.print("{s}\n", .{@tagName(i)}),
        .ptr => |p| std.debug.print("{any}\n", .{p}),
        .literal => |l| std.debug.print("{any}\n", .{l}),
    }
}

pub fn print_code_byte(codebyte:CodeByte) void {
    switch (codebyte) {
        .code => |op|
            std.debug.print(
                "\x1b[35m(op):\x1b[0m {{{d}}} {s}\n", .{op, @tagName(@as(OpCode, @enumFromInt(op)))}
            ),
        inline .long_const, .short_const => |c|
            std.debug.print(
                "\x1b[36m({s}):\x1b[0m {d}\n", .{@tagName(codebyte), c}
            ),
    }
}

pub fn print_chunk(chunk:Chunk) void {
    for (chunk.code.items) |byte| switch (byte) {
        .code => print_code_byte(byte),
        inline .long_const, .short_const => |i|
            std.debug.print(
                "({s}: {d}): {any}\n", .{@tagName(byte), i, chunk.constants.items[i]}
            ),
    };
}
