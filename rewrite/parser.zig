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
    err:ParseError,
    okay:Ok,

    pub const Ok = []Instruction;

    pub fn fail(err:ParseError) ParseReturn {
        return .{ .err = err };
    }
    pub fn done(result:Ok) ParseReturn {
        return .{ .okay = result };
    }

    pub fn failed(self:ParseReturn) ?ParseError {
        if (self == .err) return self.err;
        return null;
    }
    pub fn ok(self:ParseReturn) ?Ok {
        return self.unwrap() catch null;
    }

    pub fn unwrap(self:ParseReturn) ParseError!Ok {
        return switch (self) {
            .err => |err| err,
            .okay => |result| result,
        };
    }
};

pub fn do(alloc:std.mem.Allocator, reader:*std.Io.Reader) !ParseReturn {
    var res:std.ArrayList(Instruction) = .empty;
    defer res.deinit(alloc);

    var mem:std.ArrayList(u8) = .empty;
    defer mem.deinit(alloc);

    var data:Data = try .init(alloc);
    defer data.deinit();

    while (reader.takeByte()) |b| {
        if (std.ascii.isWhitespace(b)) {
            if (mem.items.len == 0) continue;

            const chunk = try mem.toOwnedSlice(alloc);
            defer alloc.free(chunk);

            if (stringToEnum(VM.defaults.instruction_set.Instruction, chunk)) |in| {
                try res.append(alloc, .op(in));
                continue;
            }

            if (chunk.len == 3 or chunk.len == 2) if (chunk[0] == 'r') {
                switch (chunk.len) {
                    2 => try res.append(alloc, try .register(chunk[1])),
                    3 => {
                        const c = chunk[1..];
                        if (isDigit(c[0]) or isDigit(c[1]) or c[0] > '1' or c[1] > '5')
                            return .fail(error.InvalidRegister);
                        var n:u8 = (c[0]-'0') * 10;
                        n += c[1]-'0';
                        try res.append(alloc, try .register(n));
                    },
                    else => unreachable,
                }
                continue;
            };

            if (std.fmt.parseInt(Word, chunk, 10)) |n| {
                try res.append(alloc, .num(n));
                continue;
            } else |_| {}

            std.debug.print("here -> {s}\n", .{chunk});
            return .fail(error.InvalidToken);
        }
        if (b == ';') {
            while (reader.takeByte()) |c| {
                if (c == '\n') break;
            } else |err| return switch (err) {
                error.EndOfStream => .fail(error.UnexpectedEOF),
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
