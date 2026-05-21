const std = @import("std");
const common = @import("common.zig");
const chunk = @import("chunk.zig");

const OpCode = chunk.OpCode;
pub const Value = @import("value.zig").Value;

const Token = @This();

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
        use:struct{
            name:?[]u8 = null,
            val:u16,
        }
    },
};

pub fn free(self:*Token, alloc:std.mem.Allocator) void {
    _ = alloc;
    if (self.value == .literal) switch (self.value.literal) {
        //.string => |str| alloc.free(str),
        else => {},
    };
}

pub const WordMap = struct {
    map:std.StringHashMap([]common.Data.TokenWord) = undefined,

    pub fn add_set(self:*WordMap, name:[]const u8, T:type) !void {
        var res:std.ArrayList(common.Data.TokenWord) = .empty;
        defer res.deinit(self.map.allocator);
        for (std.meta.tags(T)) |word| {
            const word_name = try self.map.allocator.dupe(u8,
                //effectively std.mem.absorbSentinel; but without relying on the
                //  standard library (since it will probably get removed at some point)
                //    and for a mutable slice of bytes
                @as([]u8, @ptrCast(@constCast(@tagName(word))))[0..@tagName(word).len]
            );

            try res.append(self.map.allocator, .{
                .name = word_name,
                .value = @intCast(@intFromEnum(word)),
            });
        }
        const list = try res.toOwnedSlice(self.map.allocator);
        const duped_name = try self.map.allocator.dupe(u8, name);
        try self.map.put(duped_name, list);
    }
};
