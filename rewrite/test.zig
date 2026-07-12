const std = @import("std");
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
