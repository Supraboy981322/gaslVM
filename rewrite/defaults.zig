const VM = @import("vm.zig");
const std = @import("std");
const InstructionSet = @import("InstructionSet.zig").Make;

const assert = std.debug.assert;
const isDigit = std.ascii.isDigit;

pub const stack_size:usize = 16;

pub const instruction_set = InstructionSet(instruction_funcs);
pub const VmType = VM.Make(instruction_set);
pub const Word = VmType.Word;

const NoError = error{};

pub const instruction_funcs = struct {

    //0
    pub fn move(vm:*VmType) NoError!void {
        vm.getRegister().* = vm.pop();
    }

    //1
    pub fn add(vm:*VmType) NoError!void {
        vm.getRegister().* +%= vm.getRegister().*;
    }

    //2
    pub fn sub(vm:*VmType) NoError!void {
        vm.getRegister().* -%= vm.getRegister().*;
    }

    //3
    pub fn div(vm:*VmType) error{DivideByZero}!void {
        const left = vm.getRegister();
        const right = vm.getRegister();
        if (left.* == 0 or right.* == 0) return error.DivideByZero;
        left.* /= right.*;
    }

    //4
    pub fn mult(vm:*VmType) NoError!void {
        vm.getRegister().* *%= vm.getRegister().*;
    }

    //5
    pub fn push(vm:*VmType) NoError!void {
        vm.push(vm.next());
    }

    //6
    pub fn print(vm:*VmType) NoError!void {
        const ptr:[*]u8 = @ptrFromInt(vm.getRegister().*);
        const len:Word = vm.getRegister().*;
        std.debug.print("{s}", .{ptr[0..len]});
    }

    //7
    pub fn jam(_:*VmType) error{Jammed}!void {
        return error.Jammed;
    }

    //8
    pub fn alloc(vm:*VmType) error{OutOfMemory}!void {
        const len = vm.pop();
        // TODO: probably a better way to do this
        const ptr:[*]u8 = (try vm.alloc.alloc(u8, len)).ptr;
        vm.push(@intFromPtr(ptr));
    }

    //9
    pub fn free(vm:*VmType) NoError!void {
        const ptr = vm.getRegister().*;
        const len = vm.pop();
        const s:[*]u8 = @ptrFromInt(ptr);
        vm.alloc.free(s[0..len]);
    }

    //10
    // TODO: there is 100% a MUCH faster way to do this
    pub fn store(vm:*VmType) NoError!void {
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
    pub fn load(vm:*VmType) NoError!void {
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
    pub fn pushR(vm:*VmType) NoError!void {
        vm.push(vm.getRegister().*);
    }

    //13
    pub fn jump(vm:*VmType) NoError!void {
        vm.ip = vm.code.ptr + vm.next();
    }

    //14
    pub fn equals(vm:*VmType) NoError!void {
        vm.push(@intFromBool(vm.getRegister().* == vm.getRegister().*));
    }

    //15
    pub fn jump_if(vm:*VmType) NoError!void {
        if (vm.getRegBool())
            try jump(vm)
        else
            _ = vm.next();
    }

    //16
    pub fn greater(vm:*VmType) NoError!void {
        const cond = vm.getRegister().* > vm.getRegister().*;
        vm.push(if (cond) 1 else 0);
    }
    //17
    pub fn less(vm:*VmType) NoError!void {
        const cond = vm.getRegister().* < vm.getRegister().*;
        vm.push(if (cond) 1 else 0);
    }
    //18
    pub fn not(vm:*VmType) NoError!void {
        vm.push(if (vm.getRegBool()) 0 else 1);
    }
    //19
    pub fn @"or"(vm:*VmType) NoError!void {
        const one = vm.getRegBool();
        const two = vm.getRegBool();
        vm.push(if (one or two) 1 else 0);
    }
    //20
    pub fn @"and"(vm:*VmType) NoError!void {
        const one = vm.getRegBool();
        const two = vm.getRegBool();
        vm.push(if (one and two) 1 else 0);
    }
    //21
    pub fn xor(vm:*VmType) NoError!void {
        const one = vm.getRegBool();
        const two = vm.getRegBool();
        vm.push(if ((one and !two) or (!one and two)) 1 else 0);
    }
    //22
    pub fn nor(vm:*VmType) NoError!void {
        const one = vm.getRegBool();
        const two = vm.getRegBool();
        vm.push(if (one and two) 0 else 1);
    }

    //23
    pub fn pop(vm:*VmType) NoError!void {
        vm.getRegister().* = vm.pop();
    }

    //24
    pub fn syscall(vm:*VmType) error{InvalidArgument}!void {
        const syscall_name:std.posix.system.SYS = @enumFromInt(vm.pop());
        const arg_count = vm.pop();
        const ret = switch (arg_count) {
            0 => std.posix.system.syscall0(syscall_name),
            1 => std.posix.system.syscall1(syscall_name,
                @intCast(vm.getRegister().*),
            ),
            2 => std.posix.system.syscall2(syscall_name,
                @intCast(vm.getRegister().*),
                @intCast(vm.getRegister().*),
            ),
            3 => std.posix.system.syscall3(syscall_name,
                @intCast(vm.getRegister().*),
                @intCast(vm.getRegister().*),
                @intCast(vm.getRegister().*),
            ),
            4 => std.posix.system.syscall4(syscall_name,
                @intCast(vm.getRegister().*),
                @intCast(vm.getRegister().*),
                @intCast(vm.getRegister().*),
                @intCast(vm.getRegister().*),
            ),
            5 => std.posix.system.syscall5(syscall_name,
                @intCast(vm.getRegister().*),
                @intCast(vm.getRegister().*),
                @intCast(vm.getRegister().*),
                @intCast(vm.getRegister().*),
                @intCast(vm.getRegister().*),
            ),
            6 => std.posix.system.syscall6(syscall_name,
                @intCast(vm.getRegister().*),
                @intCast(vm.getRegister().*),
                @intCast(vm.getRegister().*),
                @intCast(vm.getRegister().*),
                @intCast(vm.getRegister().*),
                @intCast(vm.getRegister().*),
            ),
            else => return error.InvalidArgument
        };
        vm.push(@intCast(ret));
    }
};
