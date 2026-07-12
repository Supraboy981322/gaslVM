const std = @import("std");
const VM = @import("vm.zig").Make;

const isDigit = std.ascii.isDigit;

pub fn Make(comptime functions:anytype) type {
    return struct {
        const VmType = VM(@This());
        const Word = VmType.Word;

        pub const array = blk: {
            var set:[]const *const fn (*VmType) anyerror!void = &.{};
            for (@typeInfo(funcs).@"struct".decls) |decl| {
                set = set ++ .{ @field(funcs, decl.name) };
            }
            break :blk set[0..set.len];
        };

        const NoError = error{};

        pub const funcs = functions;

        pub const Instruction = struct {
            v:Enum,

            pub fn op(i:Enum) Instruction {
                return .{ .v = i };
            }

            pub fn num(n:anytype) Instruction {
                return .{ .v = @enumFromInt(n) };
            }

            pub fn ptr(p:*anyopaque) Instruction {
                return .{ .v = @enumFromInt(@intFromPtr(p)) };
            }

            pub fn slice(comptime T:type, s:[]const T) Instruction {
                return .{ .v = @enumFromInt(@intFromPtr(s.ptr)) };
            }

            pub fn register(r:anytype) !Instruction {
                var n:Word = r;
                if ((n >= 'a' and n <= 'f') or (n >= '0' and n <= '9'))
                    n = if (isDigit(r)) n - '0' else (n - 'a') + 10;
                if (n > 15) return error.InvalidRegister;
                return .reg(n);
            }

            //consider using .register(...) if an invalid register is possible
            pub inline fn reg(r:anytype) Instruction {
                return .num(r);
            }
        };

        pub const Enum = blk: {
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
}
