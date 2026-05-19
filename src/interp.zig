const std = @import("std");
const common = @import("common.zig");
const options = @import("options");
const compiler = @import("compiler.zig");
const Tokenizer = @import("tokenizer.zig");
const VM = @import("vm.zig");
const Value = @import("value.zig").Value;

const Interp = @This();

alloc:std.mem.Allocator,
reader:*std.Io.Reader,
opts:Opts,

pub const Opts = struct {
    mode:common.Mode = .debug,
    defines:?common.DefineList = null,
};

pub fn init(alloc:std.mem.Allocator, reader:*std.Io.Reader, opts:Opts) Interp {
    return .{
        .alloc = alloc,
        .reader = reader,
        .opts = opts,
    };
}

pub fn deinit(self:*Interp) void {
    if (self.opts.defines) |defines| {
        for (defines) |def| {
            self.alloc.free(def.k);
            self.alloc.free(def.v orelse continue);
        }
        self.alloc.free(defines);
    }
}

pub fn do(self:*Interp) !VM.InterpResult {

    var tokenizer:Tokenizer = .init(self.alloc);
    defer tokenizer.deinit(.{ .free_result = true });

    const tokenized_result = try tokenizer.do(self.reader);
    const tokenized = switch (tokenized_result) {
        .err => |e| return .{  .tokenize_err = .mk(e.err, e.info orelse unreachable) },
        .ok => |toks| toks,
    };
    defer {
        self.alloc.free(tokenized.positions);
        for (tokenized.tokens) |tok| if (tok.value == .literal) switch (tok.value.literal) {
            .name_literal => |name| self.alloc.free(name),
            else => {},
        };
        self.alloc.free(tokenized.tokens);
    }
    if (self.opts.mode == .debug) {
        std.debug.print("\n\n==== tokenized ====\n", .{});
        for (tokenized.tokens) |token| @import("debug.zig").print_token(token);
    }

    var compiled = try compiler.do(tokenized, self.alloc, self.opts.mode);
    defer compiled.deinit();
    if (self.opts.mode == .debug) {
        std.debug.print("\n\n==== compiled ====\n", .{});
        @import("debug.zig").print_chunk(compiled);
        std.debug.print("\n\n==== interpreted ====\n", .{});
    }

    var vm:VM = .init(self.alloc, .{ .mode = self.opts.mode });
    defer vm.deinit();
    var res = vm.interpret(&compiled);
    switch (res) {
        .ok => |*ok| {
            defer if (ok.* == .ptr) cancel: {
                const pos = ok.ptr.val orelse blk: {
                    break :blk vm.chunk.?.constants.items[ok.ptr.ident].ptr.val;
                };
                vm.vm_alloc.free(pos orelse break :cancel, 1) catch break :cancel;
            };
            return .okay(try ok.dupe(self.alloc, &vm));
        },
        .runtime_err => |e| return .{
            .compile_err = .{
                .err = e.err,
                .info = blk: {
                    const line_no = vm.get_line_no();
                    break :blk try std.fmt.allocPrint(
                        self.alloc, "line:{?d} |{s}|", .{
                            line_no,
                            if (e.info.len > 0) e.info else @tagName(vm.ip[0]) //cur instruction
                        }
                    );
                },
            },
        },
        else => unreachable,
    }
    unreachable;
}
