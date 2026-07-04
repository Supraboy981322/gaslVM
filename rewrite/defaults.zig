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
            const f = @field(funcs, decl.name);
            set = set ++ .{ f };
        }
        break :blk set;
    };

    const NoError = error{};

    pub const funcs = struct {
        //0
        pub fn move(self:*VM) NoError!void {
            self.getRegister().* = self.pop();
        }

        //1
        pub fn add(self:*VM) NoError!void {
            self.getRegister().* +%= self.getRegister().*;
        }

        //2
        pub fn sub(self:*VM) NoError!void {
            self.getRegister().* -%= self.getRegister().*;
        }

        //3
        pub fn div(self:*VM) error{DivideByZero}!void {
            const left = self.getRegister();
            const right = self.getRegister();
            if (left.* == 0 or right.* == 0) return error.DivideByZero;
            left.* /= right.*;
        }

        //4
        pub fn mult(self:*VM) NoError!void {
            self.getRegister().* *%= self.getRegister().*;
        }

        //5
        pub fn push(self:*VM) NoError!void {
            self.push(self.next());
        }

        //6
        pub fn print(self:*VM) NoError!void {
            const ptr:[*]u8 = @ptrFromInt(self.getRegister().*);
            const len:Word = self.getRegister().*;
            std.debug.print("{s}", .{ptr[0..len]});
        }

        //7
        pub fn jam(_:*VM) error{Jammed}!void {
            return error.Jammed;
        }

        //8
        pub fn alloc(self:*VM) error{OutOfMemory}!void {
            const len = self.pop();
            // TODO: probably a better way to do this
            const ptr:[*]u8 = (try self.alloc.alloc(u8, len)).ptr;
            self.push(@intFromPtr(ptr));
        }

        //9
        pub fn free(self:*VM) NoError!void {
            const ptr = self.getRegister().*;
            const len = self.pop();
            const s:[*]u8 = @ptrFromInt(ptr);
            self.alloc.free(s[0..len]);
        }

        //10
        // TODO: there is 100% a MUCH faster way to do this
        pub fn store(self:*VM) NoError!void {
            var width = self.pop();
            var ptr:[*]u8 = @ptrFromInt(self.getRegister().*);
            var v = self.pop();
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
        pub fn load(self:*VM) NoError!void {
            var width = self.pop();
            var ptr:[*]u8 = @ptrFromInt(self.getRegister().*);
            var v = self.pop();
            while (width > 0) : ({
                width -= 1;
                ptr += 1;
            })
                v = (v << 8) | ptr[0];
            self.push(v);
        }

        //12
        pub fn pushR(self:*VM) NoError!void {
            self.push(self.getRegister().*);
        }

        //13
        pub fn jump(self:*VM) NoError!void {
            self.ip = self.code.ptr + self.next();
        }

        //14
        pub fn equals(self:*VM) NoError!void {
            self.push(@intFromBool(self.getRegister().* == self.getRegister().*));
        }

        //15
        pub fn jump_if(self:*VM) NoError!void {
            if (self.getRegBool())
                try jump(self)
            else
                _ = self.next();
        }

        //16
        pub fn greater(self:*VM) NoError!void {
            const cond = self.getRegister().* > self.getRegister().*;
            self.push(if (cond) 1 else 0);
        }
        //17
        pub fn less(self:*VM) NoError!void {
            const cond = self.getRegister().* < self.getRegister().*;
            self.push(if (cond) 1 else 0);
        }
        //18
        pub fn not(self:*VM) NoError!void {
            self.push(if (self.getRegBool()) 0 else 1);
        }
        //19
        pub fn @"or"(self:*VM) NoError!void {
            const one = self.getRegBool();
            const two = self.getRegBool();
            self.push(if (one or two) 1 else 0);
        }
        //20
        pub fn @"and"(self:*VM) NoError!void {
            const one = self.getRegBool();
            const two = self.getRegBool();
            self.push(if (one and two) 1 else 0);
        }
        //21
        pub fn xor(self:*VM) NoError!void {
            const one = self.getRegBool();
            const two = self.getRegBool();
            self.push(if ((one and !two) or (!one and two)) 1 else 0);
        }
        //22
        pub fn nor(self:*VM) NoError!void {
            const one = self.getRegBool();
            const two = self.getRegBool();
            self.push(if (one and two) 0 else 1);
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
