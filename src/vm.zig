// TODO: 
//  I fear I have gone the wrong direction here,
//    a large refactor may be nice

const std = @import("std");
const debug = @import("debug.zig");
const memory = @import("memory.zig");
const value = @import("value.zig");
const common = @import("common.zig");
const options = @import("options");
const Tokenizer = @import("tokenizer.zig");
const Chunk = @import("chunk.zig").Chunk;
const OpCode = @import("chunk.zig").OpCode;
const Value = value.Value;
const Error = common.Error;
const CodeByte = common.CodeByte;

pub const Alloc = memory.VM_Allocator;

const active_tag = std.meta.activeTag;

pub const RuntimeError = error {
    NotInstruction,
    UnexpectedInstruction,
    NotConstant,
    SignError,
    TypeMissmatch,
    IllegalInstruction,
    UseOfUninitializedMemory,
    NotImplemented,
    InvalidSyscallParam,
    InvalidSyscall,
    NotANumber,
    BadPtr,
    OutOfBounds,
} || std.mem.Allocator.Error || Alloc.Error;

const VM = @This();

chunk:?*Chunk,
alloc:std.mem.Allocator,

ip:[*]CodeByte,
saved_pos:?[*]CodeByte = null,

stack:[options.stack_size]Value,
stack_top:[*]Value,
vm_alloc:Alloc = undefined,

held:struct{
    stack:[options.hold_size]Value,
    top:u16,
    pub fn pop(self:*@This()) Value {
        self.top -= 1;
        return self.stack[self.top];
    }
    pub fn push(self:*@This(), v:Value) void {
        defer self.top += 1;
        self.stack[self.top] = v;
    }
},

opts:VMOpts,

pub const VMOpts = struct {
    args:[]const []const u8,
    mode:common.Mode,
};

pub fn init(mem:std.mem.Allocator, opts:VMOpts) VM {
    var stack = [_]Value{undefined} ** options.stack_size;
    var held = [_]Value{undefined} ** options.hold_size;
    _ = &held;
    return .{
        .chunk = null,
        .alloc = mem,
        .ip = undefined,
        .stack = stack,
        .stack_top = (&stack).ptr,
        .opts = opts,
        .held = .{
            .stack = held,
            .top = 0,
        },
    };
}

// NOTE: does not free chunk
pub fn deinit(self:*VM) void {
    self.chunk = null;
}

pub const InterpResult = union(enum) {
    ok:Value,
    tokenize_err:Error(Tokenizer.TokenizerError, Tokenizer.TokenizeResult.ErrInfo),
    compile_err:Error(anyerror, []u8),
    runtime_err:Error(RuntimeError, []u8),

    pub fn okay(v:Value) InterpResult {
        return .{ .ok = v };
    }

    pub fn runtime(e:RuntimeError, info:?[]const u8) InterpResult {
        return .{ .runtime_err = .{
            .info = @constCast(info) orelse @constCast(""), // TODO: error info
            .err = e,
        } };
    }

    pub fn compile(e:anyerror, info:?[]const u8) InterpResult {
        return .{ .compile_err = .{
            .info = @constCast(info) orelse @constCast(""),
            .err = e,
        } };
    }

    pub fn is_val(self:InterpResult,v:Value) bool {
        if (self != .ok) return false;
        for ([_]bool{
            std.meta.activeTag(self.ok) == std.meta.activeTag(v),
            self.ok.equals(v),
        }) |check|
            if (!check) return false;
        return true;
    }
};

pub fn interpret(self:*VM, chunk:*Chunk) InterpResult {
    self.chunk = chunk;
    self.vm_alloc = chunk.vm_alloc;
    self.ip = chunk.code.items.ptr;
    return self.run();
}

pub fn push(self:*VM, v:Value) void {
    self.stack_top[0] = v;
    self.stack_top += 1;
}

pub fn pop(self:*VM) Value {
    self.stack_top -= 1;
    return self.stack_top[0];
}

pub fn next_instruction(self:*VM) CodeByte {
    const instruction:CodeByte = self.ip[0];
    self.ip += 1;
    return instruction;
}

fn debug_trace(self:*VM) void {
    debug.disassemble_instruction(
        &self.chunk.?,
        @constCast(&@as(usize,
            @intCast(self.ip - self.chunk.?.code.items.ptr)
        ))
    );
    // TODO: actually trace stack
}

pub fn get_line_no(self:*VM) ?usize {
    const pos = @intFromPtr(self.ip);
    const start = @intFromPtr(self.chunk.?.code.items.ptr);
    if (start > pos) return null; //VM code chunk shifted in memory
    const idx = pos - start;
    if (idx > self.chunk.?.code.items.len) return null; //something stranged happened
    return self.chunk.?.line_nums[pos - start];
}

fn run(self:*VM) InterpResult {
    while (true) {
        const instruction = self.next_instruction();
        //if (comptime options.use_debug_trace) {
        //    debug.print_code_byte(instruction);
        //}
        //if (comptime options.use_debug_trace) self.debug_trace();
        if (!instruction.is_op()) {
            if (self.opts.mode == .debug) std.debug.print(
                "ERROR HERE (offset: {d}): {any}",
                .{self.ip - self.chunk.?.code.items.ptr,instruction}
            );
            return .runtime(error.NotInstruction, instruction.name());
        }

        const code = @as(OpCode, @enumFromInt(instruction.code));
        if (options.use_debug_trace)
            std.debug.print("\x1b[34mOPCODE:\x1b[0m {s}\n", .{@tagName(code)});
        switch (code) {

            //general OpCodes
            .no_op => {},
            .syscall => {
                const param_count = self.pop().cast_Z(usize) catch |e| {
                    return .runtime(e, "syscall");
                };
                if (param_count > std.math.maxInt(u3)) {
                    return .runtime(error.InvalidSyscallParam, null);
                }
                const ret = self.syscall(
                    @enumFromInt(self.pop().word),
                    @intCast(param_count)
                ) catch |e| {
                    return .runtime(e, null);
                };
                self.push(ret);
            },
            .@"unreachable" =>
                if (comptime options.use_debug_trace)
                    unreachable //'unreachable' instruction triggered
                else if (self.opts.mode == .debug)
                    return self.panic("unreachable position")
                else
                    @breakpoint(), //unreachable position in code
            .proc => {
                const what = self.pop().word;
                const val = self.proc(@enumFromInt(what)) catch |e| {
                    return .runtime(e, @tagName(code));
                };
                self.push(val);
            },


            //stack manipulation
            .discard => _ = self.pop(),
            .push => {
                const v:*Value = self.read_const() catch |e| {
                    return .runtime(e, "push");
                };
                self.push(v.*);
                if (options.use_debug_trace)
                    std.debug.print("\x1b[33mCONSTANT:\x1b[0m {any}\n", .{v.*});
            },
            .dupe => self.push((self.stack_top - 1)[0]),
            .hold => self.held.push(self.pop()),
            .hold_off => {
                const pos = self.pop().cast_Z(usize) catch |e| {
                    return .runtime(e, @tagName(code));
                };
                self.held.stack[self.held.top-pos-1] = self.pop();
            },
            inline .take, .take_copy => |which| {
                var thing:Value = undefined;
                if (comptime which == .take_copy)
                    thing = self.held.stack[self.held.top-1]
                else
                    thing = self.held.pop();
                self.push(thing);
            },
            .take_off => {
                const foo = self.pop();
                const offset = foo.cast_Z(usize) catch |e| {
                    return .runtime(e, @tagName(code));
                };
                const bar = self.held.stack[self.held.top-offset-1];
                self.push(bar);
            },



            //control flow
            .save_pos => self.saved_pos = self.ip,
            inline .@"return", .stop => |which| {
                const end = (comptime which == .stop) or self.saved_pos == null;
                if (end) return .okay(self.pop());
                self.ip = self.saved_pos.?;
                self.saved_pos = null;
            },
            inline .jmp, .jmpif, .jmp_sav => |which| {
                const pos = self.pop().pos.pos;
                switch (comptime which) {
                    .jmp => {},
                    .jmpif => if (!self.pop().bool) continue,
                    .jmp_sav => self.saved_pos = self.ip,
                    else => unreachable,
                }
                self.ip = self.chunk.?.code.items.ptr + pos;
            },



            //math OpCodes
            .negate => {
                var v = self.pop();
                if (!v.is_signed())
                    return .runtime(error.SignError, "negate");
                const new:Value = switch (v) {
                    inline .int, .s8, .s16, .s32, .s64,
                        => |i| .mk_int(std.meta.activeTag(v), @TypeOf(i), -i),
                    inline .f64, .f32
                        => |f| .mk_float(std.meta.activeTag(v), @TypeOf(f), -f),
                    else => unreachable,
                };
                self.push(new);
            },
            inline .mult, .div, .add, .sub => |op| {
                var two = self.pop();
                var one = self.pop();
                const both_num = active_tag(one) == active_tag(two);
                const either_ptr = two == .ptr or one == .ptr;
                if ((!both_num or !one.is_num() or !two.is_num()) and !either_ptr)
                    return .runtime(error.TypeMissmatch, @tagName(op));
                self.push(.math(op, one, two));
            },



            //instructions for common values
            inline .true, .false => |o| self.push(.{ .bool = o == .true }),
            .null => self.push(.null),



            //boolean stuff
            .not => self.push(.{ .bool = !self.pop().bool }),
            inline .eql, .greater, .less => |o| {
                const two = self.pop();
                const one = self.pop();
                const res:Value = switch (o) {
                    .eql => .{ .bool = one.equals(two) },
                    .greater => .{ .bool = one.greater_than(two) },
                    .less => .{ .bool = one.less_than(two) },
                    else => unreachable,
                };
                self.push(res);
            },



            // WARNING: only valid in Zig debug builds
            .print => {
                if (@import("builtin").mode == .Debug)
                    std.debug.print("{any}\n", .{(self.stack_top - 1)[0]})
                else
                    return .runtime(error.IllegalInstruction, "print");
            },



            //pointers and allocation
            .save => {
                const val = self.pop();
                const ptr = self.pop();
                const bytes = val.serialize(self.alloc) catch |e| {
                    return .runtime(e, @tagName(code));
                };
                defer self.alloc.free(bytes);
                self.vm_alloc.putN(ptr.ptr.val.?, bytes) catch |e| {
                    return .runtime(e, @tagName(code));
                };
            },
            inline .get, .getH => |which| {
                const ptr = blk: {
                    var foo = self.pop();
                    if (foo.ptr.val != null) break :blk foo.ptr;
                    foo = self.chunk.?.constants.items[foo.ptr.ident];
                    break :blk foo.ptr;
                };
                if (ptr.val == null) return .runtime(
                    error.UseOfUninitializedMemory, @tagName(which)
                );
                const start = self.vm_alloc.get(ptr.val.?, 1) catch |e| {
                    return .runtime(e, @tagName(which));
                };
                if (which == .getH) {
                    self.push(.{ .usize = @intFromPtr(start+1) });
                    continue;
                }
                const len = Value.sizeOf(@enumFromInt(start[0]));
                self.push(.deserialize(start[0..len+1]));
            },
            .overwrite => {
                var ptr = self.pop().ptr;
                if (ptr.val == null)
                    ptr = self.chunk.?.constants.items[ptr.ident].ptr;
                const val = self.pop();
                const bytes = val.serialize(self.alloc) catch |e| {
                    return .runtime(e, @tagName(code));
                };
                defer self.alloc.free(bytes);
                self.vm_alloc.putN(ptr.val.?, bytes) catch |e| {
                    return .runtime(e, @tagName(code));
                };
            },
            // TODO: maybe replace this
            .alloc => {
                const len = self.pop();
                const size = len.get_size();
                var ptr = self.pop();
                const alloc_size = (len.cast_Z(usize) catch |e| {
                    return .runtime(e, @tagName(code));
                }) + size;
                ptr.ptr.val = self.vm_alloc.alloc(@intCast(alloc_size)) catch |e| {
                    return .runtime(e, "alloc");
                };
                self.chunk.?.constants.items[ptr.ptr.ident] = ptr;
                self.push(ptr);
            },
            .free => {
                const len = self.pop();
                const size = len.get_size();
                const allocated_size = (len.cast_Z(usize) catch |e| {
                    return .runtime(e, @tagName(code));
                }) + size;
                const ident = self.pop().ptr.ident;
                const ptr:*value.Ptr = &self.chunk.?.constants.items[ident].ptr;
                if (ptr.val == null) return .runtime(
                    error.UseOfUninitializedMemory, @tagName(code)
                );
                self.vm_alloc.free(ptr.val.?, @intCast(allocated_size)) catch |e| {
                    return .runtime(e, "free");
                };
                ptr.val = null;
            },
            .string => {
                const len = self.pop();
                const l = len.cast_Z(usize) catch |e| {
                    return .runtime(e, @tagName(code));
                };
                const size = len.get_size() + l + 1;
                const ptr = self.vm_alloc.alloc(@intCast(size)) catch |e| {
                    return .runtime(e, @tagName(code));
                };
                const raw = self.vm_alloc.get_fast(ptr);
                raw[0] = @intFromEnum(std.meta.activeTag(len));
                var off:usize = 0;
                for (0..l) |i| {
                    defer off += len.get_size()-1;
                    const s = self.pop().serialize_fast();
                    for (s) |b| raw[off+(l-i)] = b;
                }
                self.push(.{ .ptr = .{
                    .val = ptr,
                    .ident = 0,
                } });
            },
            inline .ptr_add, .ptr_sub => |op| {
                var ptr = self.chunk.?.constants.items[self.pop().ptr.ident].ptr;
                const pre = self.pop();
                const other = pre.cast_Z(u16) catch |e| {
                    return .runtime(
                        if (e == error.BadPtr)
                            error.UseOfUninitializedMemory
                        else
                            e,
                        @tagName(op)
                    );
                };
                if (ptr.val == null)
                    return .runtime(error.UseOfUninitializedMemory, @tagName(op));
                switch (comptime op) {
                    .ptr_add => ptr.val.? += other,
                    .ptr_sub => ptr.val.? -= other,
                    else => unreachable,
                }
                self.push(.{ .ptr = ptr });
            },


            else => return .runtime(
                error.UnexpectedInstruction,
                OpCode.from_byte(instruction.code).to_string()
            ),
        }
    }
}

pub fn read_const(self:*VM) !*Value {
    const next = self.next_instruction();
    const idx:usize =
        if (next == .short_const)
            @intCast(next.short_const)
        else if (next == .long_const)
            @intCast(next.long_const)
        else {
            if (self.opts.mode == .debug) std.debug.print(
                "ERROR HERE: {t}\n",
                .{@as(OpCode, @enumFromInt(next.code))}
            );
            return error.NotConstant;
        };
    return @constCast(&self.chunk.?.constants.items[idx]);
}

fn pop_usize(self:*VM) usize {
    return @as(*usize, @ptrCast(@alignCast(self.pop().get()))).*;
}

// TODO:
//  probably need a wrapper for std.posix.system.SYS
//    it has a different underlying int on different systems
pub fn syscall(
    self:*VM,
    syscall_name:std.posix.system.SYS,
    param_count:u3
) !Value {
    const res = switch (param_count) {
        0 => std.os.linux.syscall0(syscall_name),
        1 => std.os.linux.syscall1(syscall_name,
            try self.pop().cast_Z(usize),
        ),
        2 => std.os.linux.syscall2(syscall_name,
            try self.pop().cast_Z(usize),
            try self.pop().cast_Z(usize),
        ),
        3 => std.os.linux.syscall3(syscall_name,
            try self.pop().cast_Z(usize),
            try self.pop().cast_Z(usize),
            try self.pop().cast_Z(usize),
        ),
        4 => std.os.linux.syscall4(syscall_name,
            try self.pop().cast_Z(usize),
            try self.pop().cast_Z(usize),
            try self.pop().cast_Z(usize),
            try self.pop().cast_Z(usize),
        ),
        5 => std.os.linux.syscall5(syscall_name,
            try self.pop().cast_Z(usize),
            try self.pop().cast_Z(usize),
            try self.pop().cast_Z(usize),
            try self.pop().cast_Z(usize),
            try self.pop().cast_Z(usize),
        ),
        6 => std.os.linux.syscall6(syscall_name,
            try self.pop().cast_Z(usize),
            try self.pop().cast_Z(usize),
            try self.pop().cast_Z(usize),
            try self.pop().cast_Z(usize),
            try self.pop().cast_Z(usize),
            try self.pop().cast_Z(usize),
        ),
        else => return error.InvalidSyscallParam,
    };
    // TODO: std.posix will probably get removed (which is stupid)
    const errno = std.posix.errno(res);
    return .mk_int(.u16, u16, @intFromEnum(errno));
}

pub fn panic(_:*VM, msg:[]const u8) noreturn {
    std.debug.panic(
        \\{s}
        \\ TODO: custom panic
    , .{ msg });
}

pub fn proc(self:*VM, what:value.ProcessValue) !Value {
    switch (what) {
        .argv => {
            const idx = try self.pop().cast_Z(usize);
            if (idx >= self.opts.args.len) return error.OutOfBounds;
            const arg = self.opts.args[idx];
            self.push(.{ .usize = arg.len });
            return .{ .usize = @intFromPtr(arg.ptr) };
        },
        .argc => return .{ .usize = self.opts.args.len },
        .envp => return error.NotImplemented,
    }
}
