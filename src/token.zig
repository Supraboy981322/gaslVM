const std = @import("std");
const chunk = @import("chunk.zig");

const OpCode = chunk.OpCode;

pub const Value = @import("value.zig").Value;
pub const Token = struct {
    value:Type,
    line:usize,

    pub const Type = union(enum) {
        literal:Value,
        opcode:OpCode,
        ptr:union(enum) {
            def:union(enum) {
                pos:usize,
                val:usize,
                pub fn get_ident(self:@This()) usize {
                    return switch (self) {
                        inline else => |t| t,
                    };
                }
            },
            use:u16,
        },
    };

    pub fn free(self:*Token, alloc:std.mem.Allocator) void {
        _ = alloc;
        if (self.value == .literal) switch (self.value.literal) {
            //.string => |str| alloc.free(str),
            else => {},
        };
    }
};
