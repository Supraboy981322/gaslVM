const std = @import("std");

const Interp = @import("interp.zig");
const VM = @import("vm.zig");

var result:VM.InterpResult = undefined;

// HACK:
//  This kind-of abuses the fact that Zig runs arguments that're functions
//    from left to right, meaning if this behavior ever changes, the checks
//      in the tests will fail
//        (I hope they don't ever change that, they might knowing Zig)

test "empty source" {
    _ = try check(
        run(""),
        @constCast(&[_]bool{
            result == .ok,
            result.ok == .void,
        })
    );
}

test "(values) int" {
    _ = try check(
        run(
            \\push int 12
            \\  return
        ),
        @constCast(&[_]bool{
            result == .ok,
            result.ok == .int,
            result.ok.int == 12,
        })
    );
}

test "(values) byte" {
    _ = try check(
        run(
            \\push byte 97 
            \\  return
        ),
        @constCast(&[_]bool{
            result == .ok,
            result.ok == .byte,
            result.ok.byte == 'a',
        })
    );
}

test "(values) uint" {
    _ = try check(
        run(
            \\push uint 12
            \\  return
        ),
        @constCast(&[_]bool{
            result == .ok,
            result.ok == .uint,
            result.ok.uint == 12,
        })
    );
}

test "(data section) macros" {
    _ = try check(
        run(
            \\data 10 foo def end
            \\push %foo
            \\  return
        ),
        @constCast(&[_]bool{
            result == .ok,
            result.ok == .byte,
            result.ok.byte == 10,
        })
    );
}

test "(data section) word set" {
    _ = try check(
        run(
            \\data ( foo bar baz ) Foo words end
            \\push Foo#bar
            \\  return
        ),
        @constCast(&[_]bool{
            result == .ok,
            result.ok == .word,
            result.ok.word == 1,
        })
    );
}

test "(opcodes) bool" {
    _ = try check(
        run(
            \\false
            \\  not
            \\true
            \\  eql
            \\    return
        ),
        @constCast(&[_]bool{
            result == .ok,
            result.ok == .bool,
            result.ok.bool,
        })
    );
}

test "basic math" {
    _ = try check(
        run(
            \\push f32 1.2
            \\push f32 3.4
            \\  add
            \\push f32 5.6
            \\  mult
            \\  negate
            \\    return
        ),
        @constCast(&[_]bool{
            result == .ok,
            result.ok == .f32,
            result.ok.f32 == -25.760002,
        })
    );
}

test "pointers" {
    _ = try check(
        run(
            \\ptr foo
            \\push $foo
            \\push byte 10
            \\  alloc
            \\push byte 4
            \\  save
            \\push $foo
            \\  get
            \\  return
        ),
        @constCast(&[_]bool{
            result == .ok,
            result.ok == .byte,
            result.ok.byte == 4,
        })
    );
}

test "loop" {
    _ = try check(
        run(
            \\ptr num
            \\push $num
            \\push byte 1
            \\  alloc
            \\push byte 0
            \\  save
            \\pos loop
            \\  push $num
            \\    get
            \\  push byte 1
            \\    add
            \\  push $num
            \\    overwrite
            \\push $num
            \\  get
            \\push byte 10
            \\  eql
            \\  not
            \\push @loop
            \\  jmpif
            \\push $num
            \\  get
            \\  return
        ),
        @constCast(&[_]bool{
            result == .ok,
            result.ok == .byte,
            result.ok.byte == 10,
        }),
    );
}

fn run(code:[]const u8) !std.mem.Allocator {
    const alloc = std.testing.allocator;
    var reader:std.Io.Reader = .fixed(code);
    var interp:Interp = .init(alloc, &reader, .{ .mode = .silent });
    defer interp.deinit();
    result = try interp.do();
    return alloc;
}

pub fn check(res:anyerror!std.mem.Allocator, conditions:[]bool) !std.mem.Allocator {
    var alloc:std.mem.Allocator = undefined;
    try std.testing.expect(
        if (res) |a| blk: {
            alloc = a;
            break :blk true;
        } else |_| false
    );
    for (conditions) |chk| try std.testing.expect(chk);
    return alloc;
}
