const std = @import("std");
const value = @import("value.zig");
const common = @import("common.zig");

const VM_Allocator = @import("memory.zig").VM_Allocator;
pub const CodeByte = common.CodeByte;
const Value = value.Value;
pub const OpCode = @import("opcode.zig").OpCode;

pub const Chunk = struct {
    code:std.ArrayList(CodeByte) = .empty,
    constants:std.ArrayList(Value) = .empty,
    alloc:std.mem.Allocator,
    vm_alloc:VM_Allocator,
    line_nums:[]usize = @constCast(&[_]usize{}), // TODO: this is really inefficient for memory
    running:bool = false,

    pub fn init(alloc:std.mem.Allocator, vm_alloc:VM_Allocator) Chunk {
        return .{
            .alloc = alloc,
            .vm_alloc = vm_alloc,
        };
    }

    pub fn deinit(self:*Chunk) void {
        self.code.deinit(self.alloc);
        self.constants.deinit(self.alloc);
        self.alloc.free(self.line_nums);
        self.vm_alloc.deinit();
    }

    pub fn add_line_no(self:*Chunk, num:usize) !void {
        var new = try self.alloc.alloc(usize, self.line_nums.len+1);
        for (self.line_nums, 0..) |n, i| new[i] = n;
        self.alloc.free(self.line_nums);
        new[new.len-1] = num;
        self.line_nums = new;
    }

    pub fn add_op(self:*Chunk, c:OpCode, line_num:?usize) !void {
        if (line_num) |n| try self.add_line_no(n);
        try self.code.append(self.alloc, .{ .code = @intFromEnum(c) });
    }

    pub fn add_const(self:*Chunk, v:Value, line_num:usize) !u16 {
        if (self.running) unreachable;
        try self.add_line_no(line_num);
        try self.constants.append(self.alloc, v);
        const constant:CodeByte =
            if (self.constants.items.len > std.math.maxInt(u8))
                .{ .long_const = @intCast(self.constants.items.len-1) }
            else
                .{ .short_const = @intCast(self.constants.items.len-1) };
        try self.code.append(self.alloc, constant);
        return @intCast(self.constants.items.len);
    }

    pub fn get_const(self:*Chunk, i:usize) *Value {
        if (self.code.items.len < i) unreachable; //index into const pool out of range
        const thing = self.code.items[i];
        const idx:usize =
            if (thing == .short_const)
                @intCast(thing.short_const)
            else if (thing == .long_const)
                thing.long_const
            else
                unreachable; //get_const() index into non-constant byte
        return @constCast(&self.constants.items[idx]);
    }

    pub fn get_pos_ptr(self:*Chunk, pos:?usize) [*]CodeByte {
        const p = if (pos) |p| p else self.code.items.len-1;
        return self.code.items.ptr + p;
    }
};
