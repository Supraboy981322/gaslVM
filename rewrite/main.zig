const std = @import("std");
const parser = @import("parser.zig");
const VM = @import("vm.zig");

pub fn main(init:std.process.Init) !u8 {
    var vm:VM = try .init(init.gpa, .{});
    defer vm.deinit();

    var reader:std.Io.Reader = .fixed(@embedFile("foo.asm"));
    if ((try parser.do(init.gpa, &reader)).unwrap()) |parsed| {
        defer init.gpa.free(parsed);
        const code = try VM.codeFromEnumSlice(init.gpa, parsed);
        defer init.gpa.free(code);
        try vm.do(code);
    } else |err|
        std.debug.print("{t}\n", .{err});
    return 0;
}
