const std = @import("std");
const parser = @import("parser.zig");
const VM = @import("vm.zig");

pub fn main(init:std.process.Init) !u8 {
    var vm:VM = try .init(init.gpa, .{});
    defer vm.deinit();

    var reader:std.Io.Reader = .fixed(@embedFile("foo.asm"));
    const parsed = try parser.do(init.gpa, &reader);
    if (parsed.failed()) |info| {
        std.debug.print("parse error: {t}\n\t", .{info.err});
        if (info.chunk) |chunk| {
            std.debug.print("here -> |{s}| ", .{chunk});
            init.gpa.free(chunk);
        }
        std.debug.print("(line {d})\n", .{info.state.line_num});
        return 1;
    }
    const tokens = parsed.ok().?;
    defer init.gpa.free(tokens);

    const code = try VM.codeFromEnumSlice(init.gpa, tokens);
    defer init.gpa.free(code);

    try vm.do(code);

    return 0;
}
