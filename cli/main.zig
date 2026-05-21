const std = @import("std");
const hlp = @import("common").helpers;
const gaslVM = @import("gaslVM");

// WARNING:
//  this is purely for testing; it doesn't do much.
//    it's mostly just a wrapper to test scripts

pub fn main(init:std.process.Init) !u8 {
    const alloc = init.gpa;

    // TODO: swap run and build as defaults
    var opts:struct{
        run:bool = true,
        build:bool = false,
        defines:std.ArrayList(gaslVM.Define) = .empty,
        pub fn deinit(self:*@This(), a:std.mem.Allocator) void {
            for (self.defines.items) |def| {
                a.free(def.k);
                a.free(def.v orelse continue);
            }
            self.defines.deinit(a);
        }
        pub fn get_define(self:*@This(), name:[]const u8) ?[]const u8 {
            for (self.defines.items) |def| if (std.mem.eql(u8, def.k, name)) {
                return def.v;
            };
            return null;
        }
        pub fn dupe_defines(self:*@This(), a:std.mem.Allocator) !gaslVM.DefineList {
            var res:[]gaslVM.Define = try a.dupe(gaslVM.Define, self.defines.items);
            for (0..res.len) |i| {
                res[i].k = try a.dupe(u8, self.defines.items[i].k);
                res[i].v = try a.dupe(u8, self.defines.items[i].v orelse continue);
            }
            return res;
        }
    } = .{};
    defer opts.deinit(alloc);

    var filename:?[]const u8 = null;
    var args = init.minimal.args.iterate();
    defer args.deinit();
    _ = args.skip();
    var prog_args:[][]const u8 = try alloc.alloc([]const u8, 1);
    defer  {
        for (prog_args) |arg| alloc.free(arg);
        alloc.free(prog_args);
    }
    while (args.next()) |a| {
        const match = std.meta.stringToEnum(
            enum{ run, build, @"--" }, a
        ) orelse {
            var err:[]const u8 = "invalid arg";
            if (std.mem.startsWith(u8, a, "-D")) if (a.len > 2) {
                const slice:[]const u8 = a[2..a.len];
                const pair = hlp.cut(@constCast(slice), '=') orelse blk: {
                    break :blk [_][]u8{ @constCast(slice), @constCast("") };
                };
                const key, const val = .{ pair[0], if (pair[1].len == 0) null else pair[1] };
                try opts.defines.append(alloc, .{
                    .k = try alloc.dupe(u8, key),
                    .v = if (val) |v| try alloc.dupe(u8, v) else null,
                });
                continue;
            } else {
                err = "no 'DEFINE' provided to '-D' arg";
            };
            std.debug.print("{s}: {s}\n", .{err, a});
            return 1;
        };
        switch (match) {
            .run => {
                opts.run = true;
                const filename_R = args.next() orelse {
                    std.debug.print("missing arg value: {s}\n", .{a});
                    return 1;
                };
                filename = filename_R.ptr[0..filename_R.len];
                prog_args[0] = try alloc.dupe(u8, filename.?);
            },
            .build => @panic("TODO: build to binary"),
            .@"--" => {
                while (args.next()) |arg| {
                    const new = try alloc.alloc([]const u8, prog_args.len+1);
                    for (0..prog_args.len) |i| new[i] = prog_args[i];
                    new[new.len-1] = try alloc.dupe(u8, arg);
                    alloc.free(prog_args);
                    prog_args = new;
                }
            },
        }
    }

    if (filename == null){
        std.debug.print("missing filename\n", .{});
        return 1;
    }

    var file = std.Io.Dir.cwd().openFile(init.io, filename orelse unreachable, .{}) catch |e| {
        std.debug.print("failed to open file: {t}\n", .{e});
        return 1;
    };
    defer file.close(init.io);

    var buf:[1024]u8 = undefined;
    var crappy_reader = file.reader(init.io, &buf);
    const reader = &crappy_reader.interface;

    if (!opts.run) unreachable; // TODO: compile to binary

    const mode = std.meta.stringToEnum(
        gaslVM.Mode, opts.get_define("mode") orelse "debug"
    ) orelse {
        std.debug.print(
            \\invalid mode: |{s}|
            \\  expected one of the following:
        ++ "\n", .{opts.get_define("mode").?});
        for (std.meta.tags(gaslVM.Mode)) |mode|
            std.debug.print("\t- {s}\n", .{@tagName(mode)});
        return 1;
    };

    const enable_vm_leak_test = blk: {
        const raw = opts.get_define("VMLeakTest") orelse break :blk null;
        break :blk
            if (std.mem.eql(u8, "true", raw))
                true
            else if (std.mem.eql(u8, "false", raw))
                false
            else {
                std.debug.print(
                    \\invalid VM opt value: |{s}| ({s})
                    \\  expected one of the following:
                    ++ "\n\t- true\n\t- false\n",
                    .{ raw, "VMLeakTest" }
                );
                return 1;
            };
    };

    var interpreter:gaslVM.Interp = .init(alloc, reader, .{
        .args = prog_args,
        .defines = try opts.dupe_defines(alloc),
        .common = .{
            .mode = mode,
            .vm_leak_test = enable_vm_leak_test,
        },
    });
    defer interpreter.deinit();
    const res = try interpreter.do();
    if (res != .ok) {
        switch (res) {
            inline .runtime_err, .compile_err => |e| {
                std.debug.print(
                    \\
                    \\
                    \\error {s} -> {t}
                    \\(TODO: better error messages)
                    ++ "\n", .{ e.info, e.err }
                );
            },
            .tokenize_err => |e| {
                std.debug.print(
                    \\tokenizer error: {t}
                    \\    line:{d} (byte {d}) -> {s}
                    \\ last valid token: {any}
                    \\ expected: {s}
                ++ "\n", .{
                    e.err,
                    e.info.pos.line.number, e.info.pos.byte,
                    e.info.pos.line.string, // TODO: syntax highlighting
                    e.info.last_token,
                    if (e.info.expected.type) |ex| @tagName(ex) else "not that",
                });
                if (e.info.mem.len > 0) std.debug.print(
                    " tokenizer memory: ({x}) |{s}|\n",
                    .{e.info.mem, e.info.mem}
                );
                if (e.info.aux_str) |a|
                    std.debug.print(" additional info: {s}\n", .{a});

            },
            .ok => unreachable,
        }
        return 1;
    }

    if (mode != .silent)
        std.debug.print("{any}\n", .{res.ok});
    return 0;
}
