const std = @import("std");

const instruction_set = @import("defaults.zig").instruction_set;
const VM = instruction_set.VmType;
const parser = @import("parser.zig").Make(VM);

pub fn main(init:std.process.Init) !u8 {
    var vm:VM = try .init(init.gpa, .{});
    defer vm.deinit();

    var reader:std.Io.Reader = .fixed(@embedFile("foo.asm"));
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

    const result = try vm.do(code);
    std.debug.print("result: {d}\n", .{result});

    return 0;
}


test "_" {
    _ = @import("test.zig");
}
