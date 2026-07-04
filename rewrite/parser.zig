const std = @import("std");
const VM = @import("vm.zig");
const Data = @import("data.zig");

const Instruction = VM.defaults.instruction_set.Enum;
const isDigit = std.ascii.isDigit;
const stringToEnum = std.meta.stringToEnum;
const isAlpha = std.ascii.isAlphabetic;
const maxInt = std.math.maxInt;
const assert = std.debug.assert;

const Word = VM.Word;

pub const ParseError = error {
    InvalidToken,
    InvalidRegister,
    UnexpectedEOF,
    DuplicateLabel,
    UnexpectedToken,
    UnknownLabel,
};
pub const ParseReturn = union(enum) {
    err:Error,
    okay:Ok,

    pub const Ok = []Instruction;
    pub const Error = struct {
        state:*State,
        chunk:?[]const u8,
        err:ParseError,
    };

    pub fn deinit(self:ParseReturn, alloc:std.mem.Allocator) void {
        switch (self) {
            .err => |e| {
                @constCast(&e).state.deinit();
                if (e.chunk) |chunk| alloc.free(chunk);
            },
            .okay => |code| alloc.free(code),
        }
    }

    pub fn fail(err:ParseError, state:*State, chunk:?[]const u8) ParseReturn {
        state.errored = true;
        return .{
            .err = .{
                .err = err,
                .state = state,
                .chunk = chunk
            }
        };
    }
    pub fn done(result:Ok, state:*State) ParseReturn {
        state.deinit();
        return .{ .okay = result };
    }

    pub fn failed(self:ParseReturn) ?Error {
        if (self == .err) return self.err;
        return null;
    }
    pub fn ok(self:ParseReturn) ?Ok {
        return self.unwrap() catch null;
    }

    pub fn unwrap(self:ParseReturn) ParseError!Ok {
        return switch (self) {
            .err => |err| err.err,
            .okay => |result| result,
        };
    }
};

pub fn do(alloc:std.mem.Allocator, reader:*std.Io.Reader) !ParseReturn {
    var res:std.ArrayList(Instruction) = .empty;
    defer res.deinit(alloc);

    var data:Data = try .init(alloc);
    defer data.deinit();

    var state:State = .init(alloc);

    while (state.next(reader)) |b| {
        if (std.ascii.isWhitespace(b)) switch (try state.whitespace()) {
            .ok => |in| {
                if (in) |i| try res.append(alloc, i);
                continue;
            },
            .err => |e| return .fail(e[0], &state, e[1]),
        };
        if (b == ':') {
            if (state.mem.items.len > 0) {
                const name = try state.mem.toOwnedSlice(alloc);
                if (state.positions.getPtr(name)) |position| {
                    defer alloc.free(name);
                    if (position.* == .pos)
                        return .fail(error.DuplicateLabel, &state, name);
                    const pos = res.items.len;
                    for (position.*.todo) |back| {
                        assert(@intFromEnum(res.items[back].v) == maxInt(Word));
                        res.items[back] = .num(pos);
                    }
                    alloc.free(position.*.todo);
                    position.* = .{ .pos = pos };
                } else
                    try state.positions.put(name, .{ .pos = res.items.len });
                continue;
            }
            var name:std.ArrayList(u8) = .empty;
            defer name.deinit(alloc);
            while (state.next(reader) catch null) |c| {
                if (!isAlpha(c) and !isDigit(c)) break;
                try name.append(alloc, c);
            }
            if (state.positions.getPtr(name.items)) |position| {
                if (position.* == .pos) {
                    try res.append(alloc, .num(position.pos));
                    continue;
                }
                var new = try alloc.alloc(usize, position.*.todo.len+1);
                for (position.*.todo, 0..) |pos, i| new[i] = pos;
                new[new.len-1] = res.items.len;
                alloc.free(position.*.todo);
                position.*.todo = new;
                try res.append(alloc, .num(maxInt(Word)));
            } else {
                try state.positions.put(try name.toOwnedSlice(alloc), .{
                    .todo = try alloc.dupe(usize, &[_]usize{res.items.len})
                });
                try res.append(alloc, .num(maxInt(Word)));
            }
            continue;
        }
        if (b == ';') {
            while (reader.takeByte()) |c| {
                if (c == '\n') break;
            } else |err| return switch (err) {
                error.EndOfStream => .fail(error.UnexpectedEOF, &state, null),
                inline else => |e| e,
            };
            continue;
        }
        try state.mem.append(alloc, b);
    } else |err| switch (err) {
        error.EndOfStream => {},
        inline else => |e| return e,
    }

    {
        var itr = state.positions.iterator();
        while (itr.next()) |pos| if (pos.value_ptr.* == .todo) {
            return .fail(error.UnknownLabel, &state, null);
        };
    }

    return .done(try res.toOwnedSlice(alloc), &state);
}

pub const State = struct {
    line_num:usize = 0,
    line_start:usize = 0,
    pos:usize = 0,
    line:std.ArrayList(u8) = .empty,

    errored:bool = false,

    mem:std.ArrayList(u8) = .empty,
    alloc:std.mem.Allocator,

    positions:std.StringHashMap(Pos),

    pub const Pos = union(enum) {
        todo:[]usize,
        pos:usize,
    };

    pub fn init(alloc:std.mem.Allocator) State {
        return .{
            .alloc = alloc,
            .positions = .init(alloc),
        };
    }

    pub fn deinit(self:*State) void {
        self.mem.deinit(self.alloc);
        self.line.deinit(self.alloc);
        var itr = self.positions.iterator();
        while (itr.next()) |kv| {
            self.alloc.free(kv.key_ptr.*);
            if (kv.value_ptr.* == .todo) self.alloc.free(kv.value_ptr.todo);
        }
        self.positions.deinit();
    }

    pub fn next(self:*State, reader:*std.Io.Reader) !u8 {
        return try self.hook(try reader.takeByte());
    }

    pub fn peek(_:*State, reader:*std.Io.Reader) !u8 {
        return try reader.peekByte();
    }

    pub fn toss(self:*State, reader:*std.Io.Reader) void {
        _ = self.next(reader) catch null;
    }

    pub fn hook(self:*State, b:u8) !u8 {
        try self.line.append(self.alloc, b);
        self.pos += 1;
        switch (b) {
            '\n' => {
                self.line_num += 1;
                self.line_start = self.pos;
                self.line.clearAndFree(self.alloc);
            },
            else => {},
        }
        return b;
    }

    pub const InstructionReturn = union(enum) {
        err:struct{ ParseError, []const u8 },
        ok:?Instruction,

        pub fn fail(e:ParseError, i:[]const u8) @This() {
            return .{ .err = .{ e, i } };
        }
        pub fn done(i:?Instruction) @This() {
            return .{ .ok = i };
        }
    };

    pub fn whitespace(self:*State) !InstructionReturn {
        if (self.mem.items.len == 0) return .done(null);

        const chunk = try self.mem.toOwnedSlice(self.alloc);
        errdefer self.alloc.free(chunk);

        if (stringToEnum(VM.defaults.instruction_set.Instruction, chunk)) |in| {
            self.alloc.free(chunk);
            return .done(.op(in));
        }

        if (chunk.len == 3 or chunk.len == 2) if (chunk[0] == 'r') {
            switch (chunk.len) {
                2 => {
                    const reg = Instruction.register(chunk[1]) catch |e| {
                        return .fail(e, chunk);
                    };
                    self.alloc.free(chunk);
                    return .done(reg);
                },
                3 => {
                    const c = chunk[1..];
                    if (isDigit(c[0]) or isDigit(c[1]) or c[0] > '1' or c[1] > '5')
                        return .fail(error.InvalidRegister, chunk);
                    var n:u8 = (c[0]-'0') * 10;
                    n += c[1]-'0';
                    self.alloc.free(chunk);
                    return .done(try .register(n));
                },
                else => unreachable,
            }
        };

        if (std.fmt.parseInt(Word, chunk, 10)) |n| {
            self.alloc.free(chunk);
            return .done(.num(n));
        } else |_| {}

        return .fail(error.InvalidToken, chunk);
    }
};
