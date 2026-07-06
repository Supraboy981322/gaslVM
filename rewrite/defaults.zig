const VM = @import("vm.zig");
const std = @import("std");

const assert = std.debug.assert;
const isDigit = std.ascii.isDigit;

const InstructionSet = VM.InstructionSet;
const Word = VM.Word;

pub const stack_size:usize = 16;
pub const instruction_set = struct {
    pub const slice:InstructionSet = blk: {
        var set:[]const *const fn (*VM) anyerror!void = &.{};
        for (@typeInfo(funcs).@"struct".decls) |decl| {
            set = set ++ .{ @field(funcs, decl.name) };
        }
        break :blk set;
    };

    const NoError = error{};

    pub const funcs = struct {
        //0
        pub fn move(vm:*VM) NoError!void {
            vm.getRegister().* = vm.pop();
        }

        //1
        pub fn add(vm:*VM) NoError!void {
            vm.getRegister().* +%= vm.getRegister().*;
        }

        //2
        pub fn sub(vm:*VM) NoError!void {
            vm.getRegister().* -%= vm.getRegister().*;
        }

        //3
        pub fn div(vm:*VM) error{DivideByZero}!void {
            const left = vm.getRegister();
            const right = vm.getRegister();
            if (left.* == 0 or right.* == 0) return error.DivideByZero;
            left.* /= right.*;
        }

        //4
        pub fn mult(vm:*VM) NoError!void {
            vm.getRegister().* *%= vm.getRegister().*;
        }

        //5
        pub fn push(vm:*VM) NoError!void {
            vm.push(vm.next());
        }

        //6
        pub fn print(vm:*VM) NoError!void {
            const ptr:[*]u8 = @ptrFromInt(vm.getRegister().*);
            const len:Word = vm.getRegister().*;
            std.debug.print("{s}", .{ptr[0..len]});
        }

        //7
        pub fn jam(_:*VM) error{Jammed}!void {
            return error.Jammed;
        }

        //8
        pub fn alloc(vm:*VM) error{OutOfMemory}!void {
            const len = vm.pop();
            // TODO: probably a better way to do this
            const ptr:[*]u8 = (try vm.alloc.alloc(u8, len)).ptr;
            vm.push(@intFromPtr(ptr));
        }

        //9
        pub fn free(vm:*VM) NoError!void {
            const ptr = vm.getRegister().*;
            const len = vm.pop();
            const s:[*]u8 = @ptrFromInt(ptr);
            vm.alloc.free(s[0..len]);
        }

        //10
        // TODO: there is 100% a MUCH faster way to do this
        pub fn store(vm:*VM) NoError!void {
            var width = vm.pop();
            var ptr:[*]u8 = @ptrFromInt(vm.getRegister().*);
            var v = vm.pop();
            while (width > 0) : ({
                width -= 1;
                ptr += 1;
            }) {
                defer v >>= 8;
                ptr[0] = @intCast(v & 255);
            }
        }

        //11
        // TODO: there is 100% a MUCH faster way to do this
        pub fn load(vm:*VM) NoError!void {
            var width = vm.pop();
            var ptr:[*]u8 = @ptrFromInt(vm.getRegister().*);
            var v = vm.pop();
            while (width > 0) : ({
                width -= 1;
                ptr += 1;
            })
                v = (v << 8) | ptr[0];
            vm.push(v);
        }

        //12
        pub fn pushR(vm:*VM) NoError!void {
            vm.push(vm.getRegister().*);
        }

        //13
        pub fn jump(vm:*VM) NoError!void {
            vm.ip = vm.code.ptr + vm.next();
        }

        //14
        pub fn equals(vm:*VM) NoError!void {
            vm.push(@intFromBool(vm.getRegister().* == vm.getRegister().*));
        }

        //15
        pub fn jump_if(vm:*VM) NoError!void {
            if (vm.getRegBool())
                try jump(vm)
            else
                _ = vm.next();
        }

        //16
        pub fn greater(vm:*VM) NoError!void {
            const cond = vm.getRegister().* > vm.getRegister().*;
            vm.push(if (cond) 1 else 0);
        }
        //17
        pub fn less(vm:*VM) NoError!void {
            const cond = vm.getRegister().* < vm.getRegister().*;
            vm.push(if (cond) 1 else 0);
        }
        //18
        pub fn not(vm:*VM) NoError!void {
            vm.push(if (vm.getRegBool()) 0 else 1);
        }
        //19
        pub fn @"or"(vm:*VM) NoError!void {
            const one = vm.getRegBool();
            const two = vm.getRegBool();
            vm.push(if (one or two) 1 else 0);
        }
        //20
        pub fn @"and"(vm:*VM) NoError!void {
            const one = vm.getRegBool();
            const two = vm.getRegBool();
            vm.push(if (one and two) 1 else 0);
        }
        //21
        pub fn xor(vm:*VM) NoError!void {
            const one = vm.getRegBool();
            const two = vm.getRegBool();
            vm.push(if ((one and !two) or (!one and two)) 1 else 0);
        }
        //22
        pub fn nor(vm:*VM) NoError!void {
            const one = vm.getRegBool();
            const two = vm.getRegBool();
            vm.push(if (one and two) 0 else 1);
        }

        //23
        pub fn pop(vm:*VM) NoError!void {
            vm.getRegister().* = vm.pop();
        }
    };

    pub const Enum = struct {
        v:Instruction,

        pub fn op(i:Instruction) Enum {
            return .{ .v = i };
        }

        pub fn num(n:anytype) Enum {
            return .{ .v = @enumFromInt(n) };
        }

        pub fn ptr(p:*anyopaque) Enum {
            return .{ .v = @enumFromInt(@intFromPtr(p)) };
        }

        pub fn slice(comptime T:type, s:[]const T) Enum {
            return .{ .v = @enumFromInt(@intFromPtr(s.ptr)) };
        }

        pub fn register(r:anytype) !Enum {
            var n:Word = r;
            if ((n >= 'a' and n <= 'f') or (n >= '0' and n <= '9'))
                n = if (isDigit(r)) n - '0' else (n - 'a') + 10;
            if (n > 15) return error.InvalidRegister;
            return .reg(n);
        }

        //consider using .register(...) if an invalid register is possible
        pub inline fn reg(r:anytype) Enum {
            return .num(r);
        }
    };

    pub const Instruction = blk: {
        var names:[]const []const u8 = &.{};
        var indexes:[]const Word = &.{};
        for (@typeInfo(funcs).@"struct".decls, 0..) |decl, i| {
            if (@typeInfo(@TypeOf(@field(funcs, decl.name))) == .@"fn") {
                names = names ++ .{decl.name};
                indexes = indexes ++ .{i};
            }
        }
        break :blk @Enum(Word, .nonexhaustive, names, indexes[0..names.len]);
    };
};
