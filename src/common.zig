const std = @import("std");
const OpCode = @import("chunk.zig").OpCode;

pub fn Error(err:type, info:type) type {
    return struct {
        err:err,
        info:info,
        pub fn mk(e:err, i:info) @This() {
            return .{
                .err = e,
                .info = i,
            };
        }
    };
}

// TODO: optimize? (maybe)
pub const Mode = enum(u4) {
    debug,
    release,
    silent, //silences all stdio output to avoid stupid Zig test assumptions
};

pub fn KV(comptime K:type, comptime V:type) type {
    return struct {
        k:K,
        v:V,
    };
}

pub const Define = KV([]const u8, ?[]const u8);
pub const DefineList = []const Define;
pub const empty_define_list:DefineList = @constCast(&[_]Define{});

pub const CodeByte = union(enum) {
    short_const:u8,
    long_const:u16,
    code:u8,

    pub fn is_op(self:CodeByte) bool {
        if (self != .code) return false;
        return switch (@as(OpCode, @enumFromInt(self.code))) {
            //.true, .false => false,
            else => true,
        };
    }

    pub fn name(self:CodeByte) []u8 {
        const n = @constCast(@tagName(std.meta.activeTag(self)));
        return @as([]u8, @ptrCast(n))[0..n.len];
    }
};

pub const Data = struct {
    words:std.AutoHashMap(u16, []u16),

    //only used during tokenization
    pub const TokenWord = struct {
        name:[]u8,
        value:u16,
    };

    pub const empty:Data = .{
        .words = @constCast(&[_]usize{}),
    };
};

pub const Keyword = enum {
    data,
    end,
};
