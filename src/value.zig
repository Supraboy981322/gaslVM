const std = @import("std");
const VM = @import("vm.zig");
const common = @import("common.zig");

const Chunk = @import("chunk.zig").Chunk;
const OpCode = @import("chunk.zig").OpCode;
const CodeByte = common.CodeByte;

pub const Ptr = struct {
    ident:u16,
    val:?u16, //null for uninitialized
};

pub const ProcessValue = enum(u3) {
    argv,
    argc,
    envp, // TODO:
};

pub const Value = union(enum) {
    int:i256,
    uint:u256,
    byte:u8,

    f32:f32,
    f64:f64,

    s8:i8,
    s16:i16,
    s32:i32,
    s64:i64,

    u16:u16,
    u32:u32,
    u64:u64,

    null, //stupid Zig compiler, why is null runtime?
    bool:bool, // NOTE: there is a dedicated OpCode for this, this is just for the stack
    void,

    pos:union(enum(u1)) {
        ident:u16,
        pos:usize,
    },
    ptr:Ptr,

    word:u16,

    usize:usize,
    isize:isize,

    pub fn cast_Z(self:Value, comptime T:type) !T {
        return switch (self) {
            inline .int, .byte, .uint,
            .s8, .s16, .s32, .s64,
            .u16, .u32, .u64,
            .usize, .isize
                => |i| @intCast(i),
            .ptr => |ptr| @intCast(ptr.val orelse return error.BadPtr),
            else => return error.NotANumber,
        };
    }

    pub fn is_signed(self:Value) bool {
        return switch (self) {
            inline .int, .s8, .s16, .s32, .s64, .f32, .f64 => true,
            else => false,
        };
    }

    pub fn is_float(self:Value) bool {
        return self == .f32 or self == .f64;
    }

    pub fn mk_int(t:std.meta.Tag(Value), comptime T:type, n:T) Value {
        return switch (t) {
            .int =>  .{ .int  = @intCast(n) },
            .uint => .{ .uint = @intCast(n) },
            .byte => .{ .byte = @intCast(n) },

            .s8 =>  .{ .s8  = @intCast(n) },
            .s16 => .{ .s16 = @intCast(n) },
            .s32 => .{ .s32 = @intCast(n) },
            .s64 => .{ .s64 = @intCast(n) },

            .u16 => .{ .u16 = @intCast(n) },
            .u32 => .{ .u32 = @intCast(n) },
            .u64 => .{ .u64 = @intCast(n) },

            .isize => .{ .isize = @intCast(n) },
            .usize => .{ .usize = @intCast(n) },

            else => unreachable, //invalid int type
        };
    }

    pub fn is_int(self:Value) bool {
        return switch (self) {
            inline .int, .byte, .uint,
                .s8, .s16, .s32, .s64,
                .u16, .u32, .u64,
                .usize, .isize => true,
            else => false,
        };
    }
    
    pub fn is_num(self:Value) bool {
        return self.is_int() or self.is_float();
    }

    pub fn dupe(self:*Value, _:std.mem.Allocator, vm:*VM) !Value {
        return switch (self.*) {

            .int  => |i| .{ .int  = i },
            .uint => |u| .{ .uint = u },
            .byte => |b| .{ .byte = b },

            .f32 => |f| .{ .f32 = f },
            .f64 => |f| .{ .f64 = f },

            .s8  => |i| .{ .s8  = i },
            .s16 => |i| .{ .s16 = i },
            .s32 => |i| .{ .s32 = i },
            .s64 => |i| .{ .s64 = i },

            .u16 => |u| .{ .u16 = u },
            .u32 => |u| .{ .u32 = u },
            .u64 => |u| .{ .u64 = u },

            .null => .null,
            .bool => |b| .{ .bool = b },
            .void => .void,

            // TODO: dupe ptr
            .ptr => |ptr| .{
                .byte = 
                    if (ptr.val) |v|
                        (try vm.vm_alloc.get(v, 1))[0]
                    else
                        return .{ .ptr = ptr }
            },
            .pos  => @panic("TODO: Value.(ptr|pos).dupe(...)"),

            .word => |name| .{ .word = name },

            .usize => |us| .{ .usize = us },
            .isize => |is| .{ .isize = is },
        };
    }

    // HACK: this is type erased, be extremely careful
    pub fn get(self:Value) *anyopaque {
        return switch (self) {
            inline else => |*v| @ptrCast(@constCast(v)),
        };
    }

    // HACK: this does very little type checking, and values
    //   are type erased then casted to possibly another value (if types differ)
    //     be careful, and TRY TO ONLY USE VALUES OF SAME TYPE
    pub fn math(comptime op:OpCode, num1:Value, num2:Value) Value {
        const t = std.meta.activeTag(num1);
        if (num1.is_float()) return float_math(op, num1, num2);

        return switch (op) {
            .mult => switch (num1) {
                inline .int, .uint, .byte,
                .s8, .s16, .s32, .s64,
                .u16, .u32, .u64,
                .usize, .isize => |v| .mk_int(t,
                    @TypeOf(v),
                    v * @as(*@TypeOf(v), @ptrCast(@alignCast(num2.get()))).*
                ),
                .ptr => @panic("TODO: pointer arithmetic"),
                else => unreachable, //cannot do math on non-num
            },
            .add => switch (num1) {
                inline .int, .uint, .byte,
                .s8, .s16, .s32, .s64,
                .u16, .u32, .u64,
                .usize, .isize => |v| .mk_int(t,
                    @TypeOf(v),
                    v + @as(*@TypeOf(v), @ptrCast(@alignCast(num2.get()))).*
                ),
                .ptr => @panic("TODO: pointer arithmetic"),
                else => unreachable, //cannot do math on non-num
            },
            .sub => switch (num1) {
                inline .int, .uint, .byte,
                .s8, .s16, .s32, .s64,
                .u16, .u32, .u64,
                .usize, .isize => |v| .mk_int(t,
                    @TypeOf(v),
                    v - @as(*@TypeOf(v), @ptrCast(@alignCast(num2.get()))).*
                ),
                .ptr => @panic("TODO: pointer arithmetic"),
                else => unreachable, //cannot do math on non-num
            },
            .div => switch (num1) {
                inline .int, .uint, .byte,
                .s8, .s16, .s32, .s64,
                .u16, .u32, .u64,
                .usize, .isize => |v| .mk_int(t,
                    @TypeOf(v),
                    @divTrunc(v, @as(*@TypeOf(v), @ptrCast(@alignCast(num2.get()))).*)
                ),
                .ptr => @panic("TODO: pointer arithmetic"),
                else => unreachable, //cannot do math on non-num
            },
            else => unreachable, //not math operation
        };
    }

    pub fn mk_float(t:std.meta.Tag(Value), comptime T:type, v:T) Value {
        return switch (t) {
            .f32 => .{ .f32 = @floatCast(v) },
            .f64 => .{ .f64 = @floatCast(v) },
            else => unreachable, //invalid float type
        };
    }

    // HACK: see 'Value.math'
    pub fn float_math(comptime op:OpCode, num1:Value, num2:Value) Value {
        const t = std.meta.activeTag(num1);
        return switch (op) {
            .mult => switch (num1) {
                inline .f64, .f32 => |v| .mk_float(t,
                    @TypeOf(v),
                    v * @as(*@TypeOf(v), @ptrCast(@alignCast(num2.get()))).*
                ),
                else => unreachable, //cannot do math on non-num
            },
            .add => switch (num1) {
                inline .f64, .f32 => |v| .mk_float(t,
                    @TypeOf(v),
                    v + @as(*@TypeOf(v), @ptrCast(@alignCast(num2.get()))).*
                ),
                else => unreachable, //cannot do math on non-num
            },
            .sub => switch (num1) {
                inline .f64, .f32 => |v| .mk_float(t,
                    @TypeOf(v),
                    v - @as(*@TypeOf(v), @ptrCast(@alignCast(num2.get()))).*
                ),
                else => unreachable, //cannot do math on non-num
            },
            .div => switch (num1) {
                inline .f64, .f32 => |v| .mk_float(t,
                    @TypeOf(v),
                    @divTrunc(v,
                        @as(*@TypeOf(v),
                        @ptrCast(@alignCast(num2.get()))).*
                    )
                ),
                else => unreachable, //cannot do math on non-num
            },
            else => unreachable, //not math operation
        };
    }

    pub fn equals(self:Value, other:Value) bool {
        return switch (self) {
            .void, .null =>
                std.meta.activeTag(other) == std.meta.activeTag(self),
            .ptr =>
                @panic("TODO: pointer arithmetic"),
            .pos => |p|
                if (other == .pos) p.ident == self.pos.ident else false,
            inline else => |v|
                v == @as(*@TypeOf(v), @ptrCast(@alignCast(other.get()))).*,
        };
    }

    pub fn less_than(self:Value, other:Value) bool {
        return switch (self) {
            .bool, .void, .pos =>
                unreachable, //less_than must be number
            .null =>
                false,
            .ptr =>
                @panic("TODO: pointer arithmetic"),
            inline else => |v|
                v < @as(*@TypeOf(v), @ptrCast(@alignCast(other.get()))).*,
        };
    }
    pub fn greater_than(self:Value, other:Value) bool {
        return switch (self) {
            .bool, .void, .pos =>
                unreachable, //greater_than must be number
            .null =>
                false,
            .ptr =>
                @panic("TODO: pointer arithmetic"),
            inline else => |v|
                v > @as(*@TypeOf(v), @ptrCast(@alignCast(other.get()))).*,
        };
    }

    // WARNING: only provide basic numbers (no 'ptr' or 'pos')
    pub fn serialize_fast(self:Value) []u8 {
        switch (self) {
            inline .void, .null, .pos, .ptr => unreachable,
            inline else => |n| return @constCast(std.mem.toBytes(n)[0..]),
        }
        unreachable;
    }

    pub fn serialize(self:Value, alloc:std.mem.Allocator) ![]u8 {
        var res:[]u8 = undefined;

        switch (self) {
            .void, .null => res = try alloc.alloc(u8, 1),
            .pos => |v| {
                if (v == .ident) @panic("TODO: serialize(Value.pos.ident)");
                res = try alloc.alloc(u8, @sizeOf(@TypeOf(v.pos))+1);
                for (std.mem.toBytes(v.pos), res[1..]) |c, *b| b.* = c;
            },
            .ptr => return error.NotImplemented, //unreachable, // TODO:

            inline else => |v| {
                const size = @sizeOf(@TypeOf(v));
                res = try alloc.alloc(u8, size+1);
                for (std.mem.toBytes(v), 0..) |b, i| res[i+1] = b;
            },
        }

        res[0] = @intFromEnum(std.meta.activeTag(self));
        return res;
    }

    pub fn deserialize(bytes:[]u8) Value {
        const t:std.meta.Tag(Value) = @enumFromInt(bytes[0]);
        const bytesAsValue = std.mem.bytesAsValue;
        return switch (t) {
            .int => .{ .int = bytesAsValue(i256, bytes[1..]).* },
            .uint => .{ .uint = bytesAsValue(u256, bytes[1..]).* },
            .byte => .{ .byte = bytes[1] },

            .f32 => .{ .f32 = bytesAsValue(f32, bytes[1..]).* },
            .f64 => .{ .f64 = bytesAsValue(f64, bytes[1..]).* },

            .s8 => .{ .s8 = bytesAsValue(i8, bytes[1..]).* },
            .s16 => .{ .s16 = bytesAsValue(i16, bytes[1..]).* },
            .s32 => .{ .s32 = bytesAsValue(i32, bytes[1..]).* },
            .s64 => .{ .s64 = bytesAsValue(i64, bytes[1..]).* },

            .u16 => .{ .u16 = bytesAsValue(u16, bytes[1..]).* },
            .u32 => .{ .u32 = bytesAsValue(u32, bytes[1..]).* },
            .u64 => .{ .u64 = bytesAsValue(u64, bytes[1..]).* },

            .usize => .{ .usize = bytesAsValue(usize, bytes[1..]).* },
            .isize => .{ .isize = bytesAsValue(isize, bytes[1..]).* },

            .bool => .{ .bool = bytes[1] == 1 },

            .word => .{ .word = bytesAsValue(u16, bytes[1..]).* },

            else => unreachable,
        };
    }

    pub fn get_size(self:Value) usize {
        return Value.sizeOf(std.meta.activeTag(self));
    }

    pub fn sizeOf(what:std.meta.Tag(Value)) usize {
        switch (what) {
            inline else => |t| {
                // I know how this looks, but deal with it
                @setEvalBranchQuota(10000);
                return @sizeOf(std.meta.fieldInfo(Value, t).type);
            },
        }
    }
};
