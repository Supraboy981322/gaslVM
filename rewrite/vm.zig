const std = @import("std");


pub fn Make(comptime InstructionSet:type) type {
    return struct {
        registers:Registers,
        code:[]Word,
        ip:[*]Word = undefined,

        stack:[]Word,
        stack_top:[*]Word = undefined,
        stack_size:usize = defaults.stack_size,

        alloc:std.mem.Allocator,

        const VM = @This();

        pub const Registers = MkRegisters(16, Word);
        pub const word_size:u16 = 64;
        pub const Word = @Int(.unsigned, word_size);
        pub const instructions = struct {
            pub const Set = InstructionSet;
            pub const InstructionFn = *const fn (*VM) anyerror!void;
            pub const InstructionArray = [InstructionSet.array.len]InstructionFn;
            pub const array = InstructionSet.array;
            pub const Enum = InstructionSet.Enum;
            pub const Instruction = InstructionSet.Instruction;
        };

        pub const defaults = @import("defaults.zig");

        pub fn codeFromEnumSlice(alloc:std.mem.Allocator, slice:[]const InstructionSet.Instruction) ![]Word {
            var res = try alloc.alloc(Word, slice.len);
            for (0..slice.len) |i| res[i] = @intFromEnum(slice[i].v);
            return res;
        }

        pub fn MkRegisters(comptime count:usize, comptime T:type) type {
            const Attr = @TypeOf(@typeInfo(u8)).StructField.Attributes;
            var names:[count][]const u8 = undefined;
            for (0..count) |i| {
                if (i < 10) {
                    names[i] = &.{ 'r', '0', @intCast(i+'0') };
                    continue;
                }
                var n:usize = i;
                while (n > 9) n /= 10;
                names[i] = ([_]u8{ 'r', @intCast(n+'0'), @intCast((i - (10*n))+'0') })[0..];
            }
            const final = names[0..];
            return @Struct(
                .auto,
                null,
                final,
                &([_]type{T} ** count),
                &([_]Attr{ .{ .default_value_ptr = &@as(usize, 0) } } ** count),
            );
        }

        pub const InitOpts = struct {
            stack_size:?usize = null,
        };
        pub fn init(alloc:std.mem.Allocator, opts:InitOpts) !VM {
            return .{
                .stack_size = if (opts.stack_size) |s| s else defaults.stack_size,
                .stack =
                    if (opts.stack_size) |s|
                        try alloc.alloc(usize, s)
                    else
                        try alloc.alloc(usize, defaults.stack_size),
                .alloc = alloc,
                .registers = .{},
                .code = try codeFromEnumSlice(alloc, &.{.op(.jam)}),
            };
        }
        pub fn deinit(self:*VM) void {
            self.alloc.free(self.stack);
        }

        pub fn next(self:*VM) Word {
            defer self.ip += 1;
            return self.ip[0];
        }
        pub fn getRegister(self:*VM) *Word {
            const idx = self.next();
            const fields = comptime std.meta.fieldNames(Registers);
            return switch (idx) {
                inline 0...fields.len-1 => |i| &@field(self.registers, fields[i]),
                else => unreachable, //invalid register
            };
        }
        pub fn pop(self:*VM) Word {
            self.stack_top -= 1;
            return self.stack_top[0];
        }
        pub fn push(self:*VM, v:Word) void {
            self.stack_top[0] = v;
            self.stack_top += 1;
        }

        pub fn getRegBool(self:*VM) bool {
            return self.getRegister().* != 0;
        }

        pub fn do(self:*VM, code:[]Word) !void {
            self.alloc.free(self.code);
            self.code = code;
            self.ip = self.code.ptr;
            self.stack_top = self.stack.ptr;
            while (true) switch (self.next()) {
                inline 0...instructions.array.len-1 => |i| try instructions.array[i](self),
                else => return error.InstructionOutOfBounds,
            };
        }
    };
}
