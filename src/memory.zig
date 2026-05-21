const std = @import("std");
const options = @import("options");
const common = @import("common.zig");

const Value = @import("value.zig").Value;

// TODO: this is REALLY inefficient, fix it
pub const VM_Allocator = struct {
    buf:[]u8,
    taken:[]bool,
    mode:common.Mode,
    leak_test:?bool = null,

    pub const Error = error {
        SegFault,
        InvalidFree,
        OutOfMemory,
    };

    const Self = @This();

    pub fn init(mem_size:u16, opts:common.CommonOpts) !Self {
        const buf = try std.heap.page_allocator.alloc(u8, mem_size);
        const taken:[]bool = try std.heap.page_allocator.alloc(bool, buf.len);
        for (taken) |*b| b.* = false;
        return .{
            .buf = buf,
            .taken = taken,
            .mode = opts.mode,
            .leak_test = opts.vm_leak_test,
        };
    }

    pub fn deinit(self:*Self) void {
        if (self.leak_test orelse (self.mode == .debug))
            for (self.taken, 0..) |slot, i| if (slot)
                std.debug.print("\nVM.Allocator (LEAK): offset|{d}|\n", .{i});
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

    pub fn free(self:*Self, pos:u16, amount:u16) !void {
        errdefer self.dump_window(pos, amount);
        for (0..amount) |i| {
            if (self.taken[pos+i])
                self.taken[pos+i] = false
            else
                return error.InvalidFree; //free of unallocated memory
        }
    }

    pub fn get(self:*Self, pos:u16, len:u16) ![*]u8 {
        errdefer self.dump_window(pos, len);
        for (self.taken[pos..pos+len]) |used|
            if (!used) return error.SegFault; //getting unallocated memory
        return self.buf[pos..pos+len].ptr;
    }

    pub fn put(self:*Self, pos:u16, what:u8) !void {
        if (!self.taken[pos]) return error.SegFault; //setting unallocated memory
        self.buf[pos] = what;
    }

    pub fn putN(self:*Self, pos:u16, what:[]u8) !void {
        errdefer self.dump_window(pos, @intCast(what.len));
        for (0..what.len) |i| try self.put(@intCast(pos+i), what[i]);
    }

    pub fn dump_window(self:*Self, start:u16, len:u16) void {
        if (self.mode != .debug or start+len < 1) return;
        var count:usize = 0;

        if (start > 0) for (if (start > 10) start-10 else 0 .. start-1) |i| {
            defer count += 1;
            std.debug.print("\x1b[33m{x:0>2}\x1b[0m ", .{self.buf[i]});
            if (@mod(count+1, 10) == 0) std.debug.print("\n", .{});
        };

        for (if (start > 0) start-1 else 0 .. start+len-1) |i| {
            defer count += 1;
            std.debug.print("\x1b[31m{x:0>2}\x1b[0m ", .{self.buf[i]});
            if (@mod(count+1, 10) == 0) std.debug.print("\n", .{});
        }

        for (start+len-1..@min(start+len+10, self.buf.len-1)) |i| {
            defer count += 1;
            std.debug.print("\x1b[33m{x:0>2}\x1b[0m ", .{self.buf[i]});
            if (@mod(count+1, 10) == 0) std.debug.print("\n", .{});
        }
    }

    // WARNING: everything following this does zero checks
    pub inline fn put_fast(self:*Self, pos:u16, what:u8) void {
        self.buf[pos] = what;
    }
    pub inline fn putN_fast(self:*Self, pos:u16, buf:[]u8) void {
        inline for (buf, 0..) |b, offset| self.put_fast(pos+offset, b);
    }
    pub inline fn get_fast(self:*Self, pos:u16) [*]u8 {
        return self.buf[pos..].ptr;
    }
};
