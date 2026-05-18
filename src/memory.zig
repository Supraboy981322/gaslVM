const std = @import("std");
const options = @import("options");
const common = @import("common.zig");

const Value = @import("value.zig").Value;

// TODO: this is REALLY inefficient, fix it
pub const VM_Allocator = struct {
    buf:[]u8,
    taken:[]bool,
    mode:common.Mode,

    pub const Error = error {
        SegFault,
        InvalidFree,
        OutOfMemory,
    };

    const Self = @This();

    pub fn init(mem_size:u16, mode:common.Mode) !Self {
        const buf = try std.heap.page_allocator.alloc(u8, mem_size);
        const taken:[]bool = try std.heap.page_allocator.alloc(bool, buf.len);
        for (taken) |*b| b.* = false;
        return .{
            .buf = buf,
            .taken = taken,
            .mode = mode,
        };
    }

    pub fn deinit(self:*Self) void {
        if (self.mode == .debug) for (self.taken, 0..) |slot, i| if (slot) {
            std.debug.print("\nVM.Allocator (LEAK): offset|{d}|\n", .{i});
        };
        std.heap.page_allocator.free(self.taken);
        std.heap.page_allocator.free(self.buf);
    }

    pub fn alloc(self:*Self, amount:u16) !u16 {
        var found:u16 = 0;
        var start:u16 = 0;
        for (0..self.taken.len) |i| {
            if (found == amount) {
                for (start..i) |j| self.taken[j] = true;
                return start;
            }
            if (self.taken[i])
                found = 0
            else {
                if (found == 0) start = @intCast(i);
                found += 1;
            }
        }
        return error.OutOfMemory;
    }

    pub fn free(self:*Self, pos:u16, amount:u16) void {
        for (0..amount) |i| {
            if (self.taken[pos+i])
                self.taken[pos+i] = false
            else
                unreachable; //free of unallocated memory
                //return error.SegFault; //free of unallocated memory
        }
    }

    pub fn get(self:*Self, pos:u16, len:u16) [*]u8 {
        //for (self.taken[pos..len]) |used| if (!used) return error.SegFault; //getting unallocated memory
        return self.buf[pos..pos+len].ptr;
    }

    pub fn put(self:*Self, pos:u16, what:u8) void {
        //if (!self.taken[pos]) return error.SegFault; //setting unallocated memory
        self.buf[pos] = what;
    }
};
