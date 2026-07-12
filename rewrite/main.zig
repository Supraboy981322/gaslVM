const std = @import("std");

const instruction_set = @import("InstructionSet.zig").Make(instructions, .halt);
const VM = @import("vm.zig").Make(instruction_set);
const parser = @import("parser.zig").Make(VM);

pub fn main(init:std.process.Init) !u8 {
    var vm:VM = try .init(init.gpa, .{});
    defer vm.deinit();

    var reader:std.Io.Reader = .fixed(@embedFile("bar.asm"));
    const parsed = try parser.do(init.gpa, &reader);
    defer parsed.deinit(init.gpa);
    if (parsed.failed()) |*info| {
        std.debug.print("parse error: {t}\n\t", .{info.err});
        if (info.chunk) |chunk| std.debug.print("here -> |{s}| ", .{chunk});
        std.debug.print("(line {d})\n", .{info.state.line_num});
        return 1;
    }

    const code = try VM.codeFromEnumSlice(init.gpa, parsed.ok().?);
    defer init.gpa.free(code);

    return 0;
}

const instructions = struct {
    pub inline fn push(vm:*VM) !void {
        vm.push(vm.next());
    }
    pub inline fn add(vm:*VM) !void {
        vm.push(vm.pop() + vm.pop());
    }
    pub inline fn print(vm:*VM) !void {
        const n = vm.pop();
        defer vm.push(n);
        std.debug.print("{d}\n", .{n});
    }
    pub inline fn done(vm:*VM) error{Interupt}!void {
        vm.push(vm.getRegister().*);
        vm.interupt_msg = .finished;
        return error.Interupt;
    }
    pub inline fn halt(_:*VM) error{Halted}!void {
        return error.Halted;
    }
    pub inline fn pop(vm:*VM) !void {
        vm.getRegister().* = vm.pop();
    }
};
