const std = @import("std");
const Parser = @import("parser.zig").Make;
const VM = @import("vm.zig").Make;
const InstructionSet = @import("InstructionSet.zig").Make;

test "vm + custom instruction set" {
    const alloc = std.testing.allocator;

    const instructions = struct {
        const VmType = InstructionSet(@This(), .halt).VmType;
        pub inline fn mov(vm:*VmType) !void {
            vm.getRegister().* = vm.next();
        }
        pub inline fn add(vm:*VmType) !void {
            vm.getRegister().* += vm.getRegister().*;
        }
        pub inline fn fputs(vm:*VmType) !void {
            std.debug.print("{d}\n", .{vm.getRegister().*});
        }
        pub inline fn done(vm:*VmType) error{Interupt}!void {
            vm.push(vm.getRegister().*);
            vm.interupt_msg = .finished;
            return error.Interupt;
        }
        pub inline fn halt(_:*VmType) error{Halted}!void {
            return error.Halted;
        }
    };
    const set = InstructionSet(instructions, .halt);
    const VmType = set.VmType;

    var vm:VmType = try .init(alloc, .{});
    defer vm.deinit();

    const code = try VmType.codeFromEnumSlice(alloc, &.{
        .op(.mov), .reg(0x1), .num(1),
        .op(.mov), .reg(0x2), .num(2),
        .op(.add), .reg(0x1), .reg(0x2),
        .op(.done), .reg(0x1),
    });
    defer alloc.free(code);

    const result = try vm.do(code);
    try std.testing.expect(result == 3);
}

test "default instruction set" {
    const alloc = std.testing.allocator;

    const VmType = @import("defaults.zig").VmType;
    var vm:VmType = try .init(alloc, .{});
    defer vm.deinit();
    const parser = Parser(VmType);
    var reader:std.Io.Reader = .fixed(
        \\push 0
        \\move rf
        \\again:

        \\  push 1
        \\  move r0
        \\  add rf r0

        \\  push 10
        \\  move r0
        \\  equals r0 rf
        \\  move r0
        \\  jump_if r0 :end

        \\  push 2        ;len of ptr in bytes
        \\  alloc         ;allocates ptr and pushes to stack
        \\  move r0       ;pops ptr from stack and places into r0

        \\  push 97       ;'a'
        \\  push 1        ;width of num in bytes
        \\  store r0      ;puts value ('a') into ptr in r0

        \\  push 1        ;push 1 to stack
        \\  move r1       ;move to r1
        \\  add r0 r1     ;add 1 to string ptr

        \\  push 10       ;'\n' (newline
        \\  push 1        ;width of num in bytes
        \\  store r0      ;puts value ('a') into ptr in r0

        \\  sub r0 r1     ;sub 1 from string ptr to revert back to start of string

        \\  push 2        ;len of string
        \\  move r1       ;move len of string to r1
        \\  print r0 r1   ;print ptr in r0 with len in r1

        \\  push 2        ;len (in bytes) of ptr
        \\  free r0       ;frees ptr in r0

        \\jump :again     ;continue loop

        \\end:
        \\done rf         ;kills the VM (with err)
        \\
    );
    const code = try parser.do(alloc, &reader);
    const binary = try VmType.codeFromEnumSlice(alloc, try code.unwrap());
    code.deinit(alloc);
    defer alloc.free(binary);

    const result = try vm.do(binary);
    try std.testing.expect(result == 10);
}
