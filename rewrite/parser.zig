const std = @import("std");
const VM = @import("vm.zig");
const Data = @import("data.zig");

const Instruction = VM.defaults.instruction_set.Enum;
const isDigit = std.ascii.isDigit;
const stringToEnum = std.meta.stringToEnum;

const Word = VM.Word;

pub const ParseError = error {
    InvalidToken,
    InvalidRegister,
    UnexpectedEOF,
};
pub const ParseReturn = union(enum) {
    err:Error,
    okay:Ok,

    pub const Ok = []Instruction;
    pub const Error = struct {
        state:State,
        chunk:?[]const u8,
        err:ParseError,
    };

    pub fn fail(err:ParseError, state:State, chunk:?[]const u8) ParseReturn {
        return .{
            .err = .{
                .err = err,
                .state = state,
                .chunk = chunk
            }
        };
    }
    pub fn done(result:Ok) ParseReturn {
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

pub const State = struct {
    line_num:usize = 0,
    line_start:usize = 0,
    pos:usize = 0,

    pub fn next(self:*State, reader:*std.Io.Reader) !u8 {
        return self.hook(try reader.takeByte());
    }
    
    pub fn toss(self:*State, reader:*std.Io.Reader) void {
        _ = self.next(reader) catch null;
    }

    pub fn hook(self:*State, b:u8) u8 {
        self.pos += 1;
        switch (b) {
            '\n' => {
                self.line_num += 1;
                self.line_start = self.pos;
            },
            else => {},
        }
        return b;
    }
};

pub fn do(alloc:std.mem.Allocator, reader:*std.Io.Reader) !ParseReturn {
    var res:std.ArrayList(Instruction) = .empty;
    defer res.deinit(alloc);

    var mem:std.ArrayList(u8) = .empty;
    defer mem.deinit(alloc);

    var data:Data = try .init(alloc);
    defer data.deinit();

    var state:State = .{};

    while (state.next(reader)) |b| {
        if (std.ascii.isWhitespace(b)) {
            if (mem.items.len == 0) continue;

            const chunk = try mem.toOwnedSlice(alloc);

            if (stringToEnum(VM.defaults.instruction_set.Instruction, chunk)) |in| {
                try res.append(alloc, .op(in));
                alloc.free(chunk);
                continue;
            }

            if (chunk.len == 3 or chunk.len == 2) if (chunk[0] == 'r') {
                switch (chunk.len) {
                    2 => try res.append(alloc, try .register(chunk[1])),
                    3 => {
                        const c = chunk[1..];
                        if (isDigit(c[0]) or isDigit(c[1]) or c[0] > '1' or c[1] > '5')
                            return .fail(error.InvalidRegister, state, chunk);
                        var n:u8 = (c[0]-'0') * 10;
                        n += c[1]-'0';
                        try res.append(alloc, try .register(n));
                    },
                    else => unreachable,
                }
                alloc.free(chunk);
                continue;
            };

            if (std.fmt.parseInt(Word, chunk, 10)) |n| {
                try res.append(alloc, .num(n));
                alloc.free(chunk);
                continue;
            } else |_| {}

            return .fail(error.InvalidToken, state, chunk);
        }
        if (b == ';') {
            while (reader.takeByte()) |c| {
                if (c == '\n') break;
            } else |err| return switch (err) {
                error.EndOfStream => .fail(error.UnexpectedEOF, state, null),
                inline else => |e| e,
            };
            continue;
        }
        try mem.append(alloc, b);
    } else |err| switch (err) {
        error.EndOfStream => {},
        inline else => |e| return e,
    }

    return .done(try res.toOwnedSlice(alloc));
}

pub fn isNum(chunk:[]const u8) bool {
    for (chunk) |b| if (!isDigit(b)) return false;
    return true;
}
