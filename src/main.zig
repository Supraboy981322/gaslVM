const std = @import("std");
const hlp = @import("helpers.zig");
const common = @import("common.zig");
const Interp = @import("interp.zig");
const VM = @import("vm.zig");
const Tokenizer = @import("tokenizer.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    // TODO: swap run and build as defaults
    var opts:struct{
        run:bool = true,
        build:bool = false,
        defines:std.ArrayList(common.Define) = .empty,
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
        pub fn dupe_defines(self:*@This(), a:std.mem.Allocator) !common.DefineList {
            var res:[]common.Define = try a.dupe(common.Define, self.defines.items);
            for (0..res.len) |i| {
                res[i].k = try a.dupe(u8, self.defines.items[i].k);
                res[i].v = try a.dupe(u8, self.defines.items[i].v orelse continue);
            }
            return res;
        }
    } = .{};
    defer opts.deinit(alloc);

    var filename:?[:0]const u8 = null;
    var args = std.process.args();
    defer args.deinit();
    _ = args.skip();
    while (args.next()) |a| {
        const match = std.meta.stringToEnum(
            enum{ run, build }, a
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
            std.process.abort();
            unreachable;
        };
        switch (match) {
            .run => {
                opts.run = true;
                filename = args.next() orelse {
                    std.debug.print("missing arg value: {s}\n", .{a});
                    std.process.abort();
                    unreachable;
                };
            },
            .build => @panic("TODO: build to binary"),
        }
    }

    if (filename == null){
        std.debug.print("missing filename\n", .{});
        std.process.abort();
    }

    var file = std.fs.cwd().openFileZ(filename orelse unreachable, .{}) catch |e| {
        std.debug.print("failed to open file: {t}\n", .{e});
        std.process.abort();
        unreachable;
    };
    defer file.close();

    var buf:[1024]u8 = undefined;
    var crappy_reader = file.reader(&buf);
    const reader = &crappy_reader.interface;

    if (!opts.run) unreachable; // TODO: compile to binary

    const mode = std.meta.stringToEnum(
        common.Mode, opts.get_define("mode") orelse "debug"
    ) orelse {
        std.debug.print(
            \\invalid mode: |{s}|
            \\  expected one of the following:
        ++ "\n", .{opts.get_define("mode").?});
        for (std.meta.tags(common.Mode)) |mode|
            std.debug.print("\t- {s}\n", .{@tagName(mode)});
        std.process.abort();
    };

    var interpreter:Interp = .init(alloc, reader, .{
        .mode = mode,
        .defines = try opts.dupe_defines(alloc),
    });
    defer interpreter.deinit();
    const res = try interpreter.do();
    if (res != .ok) {
        const e, const i =
            if (res == .runtime_err)
                .{ res.runtime_err.err, res.runtime_err.info }
            else
                .{ res.compile_err.err, res.compile_err.info };
        std.debug.print(
            \\
            \\
            \\error {s} -> {t}
            \\(TODO: better error messages)
            ++ "\n", .{i, e}
        );
        std.process.abort();
    }

    if (mode != .silent)
        std.debug.print("{any}\n", .{res.ok});
}
