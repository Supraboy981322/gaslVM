const std = @import("std");
const Token = @import("token.zig");
const chunk = @import("chunk.zig");
const common = @import("common.zig");
const hlp = @import("common").helpers;

const parseInt = std.fmt.parseInt;
const parseFloat = std.fmt.parseFloat;

const OpCode = chunk.OpCode;
const Value = @import("value.zig").Value;
const ProcessValue = @import("value.zig").ProcessValue;
const Keyword = common.Keyword;

const Tokenizer = @This();

alloc:std.mem.Allocator,

mem:std.ArrayList(u8) = .empty,
res:std.ArrayList(Token) = .empty,
string:?u8 = null,
type:?std.meta.Tag(Value) = null,

// TODO: merge these
line_no:usize = 0,
pos:struct{
    line:?[]u8 = null,
    byte:usize = 0,
    arena:std.heap.ArenaAllocator,
},

reader:?*std.Io.Reader = null,

ptrs:std.StringHashMap(u16) = undefined,
labels:std.StringHashMap(usize) = undefined,
words:Token.WordMap = .{},
macros:std.StringHashMap([]u8) = undefined,
loads:std.ArrayList(ProcessValue) = .empty,
ident_counter:u16 = 0,

pub fn init(alloc:std.mem.Allocator) Tokenizer {
    return .{
        .alloc = alloc,
        .pos = .{ .arena = .init(alloc) },
    };
}

pub const DeinitOpts = struct {
    free_result:bool = false,
};

pub fn deinit(self:*Tokenizer, opts:DeinitOpts) void {
    self.mem.deinit(self.alloc);

    if (opts.free_result)
        for (self.res.items) |*tok|
            tok.free(self.alloc);

    self.res.deinit(self.alloc);

    var p_itr = self.ptrs.iterator();
    while (p_itr.next()) |p| self.alloc.free(p.key_ptr.*);
    self.ptrs.deinit();

    var l_itr = self.labels.iterator();
    while (l_itr.next()) |p| self.alloc.free(p.key_ptr.*);
    self.labels.deinit();

    var w_itr = self.words.map.iterator();
    while (w_itr.next()) |s| {
        for (s.value_ptr.*) |w|
            self.alloc.free(w.name);
        self.alloc.free(s.value_ptr.*);
        self.alloc.free(s.key_ptr.*);
    }
    self.words.map.deinit();
}

pub const TokenizerError = error {
    UnknownType,
    TypeMissmatch,
    InvalidToken,
    UnknownIdent,
    MissplacedKeyword,
    MisplacedKeyword,
    MissingName,
    MisplacedSymbol,
    UnknownMacro,
    MissingMacroDef,
    InvalidLoad,
} || SeekError
  || std.fmt.ParseIntError
  || std.fmt.ParseFloatError
  || std.mem.Allocator.Error;

pub const TokenizeResult = union(enum) {
    ok:Tokenized,
    err:struct{
        info:?ErrInfo, // TODO: make this not optional
        err:TokenizerError,

        pub fn mk(e:TokenizerError, info:?ErrInfo) @This() {
            return .{
                .info = info,
                .err = e,
            };
        }
    },

    pub const ErrInfo = struct {
        //the exact error
        err:TokenizerError,
        //may contain some additional information
        aux_str:?[]u8,
        //a buffer used by the tokenizer (holds whitespace to current pos)
        mem:[]u8,
        //holds string type if not null (eg: '"')
        string:?u8,
        //last valid token (null if no valid tokens)
        last_token:?Token,
        //info about expected token
        expected:struct{
            type:?std.meta.Tag(Value)
        },
        //position in the source
        pos:struct{
            //the current byte
            byte:usize,
            //current line
            line:struct {
                number:usize,
                string:[]u8,
            },
        },
    };

    pub const Tokenized = struct {
        positions:[]usize,
        tokens:[]Token,
        pub fn deinit(self:*Tokenized, tokenizer:*Tokenizer) void {
            tokenizer.alloc.free(self.positions);
            for (self.tokens) |tok| if (tok.value == .literal) switch (tok.value.literal) {
                else => {},
            };
            tokenizer.alloc.free(self.tokens);
        }
    };

    pub fn mk_err(e:TokenizerError, info:?ErrInfo) TokenizeResult {
        return .{ .err = .mk(e, info) };
    }

    pub fn okay(self:*Tokenizer) !TokenizeResult {
        const tokens = try self.res.toOwnedSlice(self.alloc);
        {
            var itr = self.macros.iterator();
            while (itr.next()) |macro| {
                self.alloc.free(macro.value_ptr.*);
                self.alloc.free(macro.key_ptr.*);
            }
            self.macros.deinit();
        }
        return .{ .ok = .{
            .tokens = tokens,
            .positions = blk: {
                var res:std.ArrayList(usize) = .empty;
                defer res.deinit(self.alloc);
                var itr = self.labels.iterator();
                // TODO: very efficient refactor this
                while (itr.next()) |pos| {
                    try res.append(self.alloc, pos.value_ptr.*);
                    for (tokens) |*tok| if (tok.value == .ptr) if (tok.value.ptr == .use) {
                        if (tok.value.ptr.use.name) |name| {
                            if (std.mem.eql(u8, name, pos.key_ptr.*))
                                tok.value.ptr.use.val = @intCast(pos.value_ptr.*);
                            self.alloc.free(name);
                            tok.value.ptr.use.name = null;
                        }
                    };
                }
                break :blk try res.toOwnedSlice(self.alloc);
            },
        }};
    }
};

pub fn do(self:*Tokenizer, reader:*std.Io.Reader) TokenizerError!TokenizeResult {
    self.reader = reader;
    self.ptrs = .init(self.alloc);
    try self.init_words();
    self.macros = .init(self.alloc);
    self.labels = .init(self.alloc);
    var string:?u8 = null;

    while (try self.next()) |b| {
        if (string) |s| {
            if (s == b) string = null;
            try self.mem.append(self.alloc, b);
            continue;
        }

        if (std.ascii.isWhitespace(b))
            if (self.mem.items.len > 0) {
                const new = (self.determine() catch |e| {
                    return .mk_err(e, try self.construct_err(e));
                }) orelse continue;
                try self.res.append(self.alloc, new);
                continue;
            } else
                continue;

        switch (b) {
            '"' => string = '"',
            ';' => try self.delim('\n', .toss),
            else => {},
        }
        try self.mem.append(self.alloc, b);
    }

    blk: {
        const new = (self.determine() catch |e| {
            return .mk_err(e, try self.construct_err(e));
        }) orelse break :blk;
        try self.res.append(self.alloc, new);
    }

    return try .okay(self);
}

pub fn do_data(self:*Tokenizer) !void {
    try @import("data_section.zig").parse(self);
}

pub fn determine(self:*Tokenizer) !?Token {
    const thing = self.mem.items;
    defer self.mem.clearAndFree(self.alloc);

    if (thing.len == 0) return null;

    if (std.meta.stringToEnum(Keyword, thing)) |keyword| switch (keyword) {
        .data => {
            try self.do_data();
            return null;
        },
        .end => return error.MissplacedKeyword,
    };

    if (std.meta.stringToEnum(OpCode, thing)) |opcode|
        return .{ .line = self.line_no, .value = .{ .opcode = opcode } };

    if (std.meta.stringToEnum(std.meta.Tag(Value), thing)) |t| {
        switch (t) {
            .ptr => {
                //const size_str = try self.take_word();
                //defer self.alloc.free(size_str);
                //const size = try parseInt(usize, size_str, 10);

                const name = try self.take_word();
                errdefer self.alloc.free(name);

                self.ident_counter += 1;
                try self.ptrs.put(name, self.ident_counter);
                return .{
                    .line = self.line_no,
                    .value = .{ .ptr = .{ .def = .{ .val = self.ident_counter } } }
                };
            },
            .pos => {
                const name = try self.take_word();
                if (self.labels.contains(name)) {
                    defer self.alloc.free(name);
                    return .{
                        .line = self.line_no,
                        .value = .{ .ptr = .{ .def = .{ .pos = self.labels.get(name).?, } } }
                    };
                }
                self.ident_counter += 1;
                try self.labels.putNoClobber(name, self.ident_counter);
                return .{
                    .line = self.line_no,
                    .value = .{ .ptr = .{ .def = .{ .pos = self.ident_counter, } } }
                };
            },
            .void => {
                return .{ .line = self.line_no, .value = .{ .literal = .void } };
            },
            else => {
                self.type = t;
                return null;
            },
        }
    }

    if (thing[0] == '%' or thing[0] == '&') {
        if (self.macros.get(thing[1..])) |macro| {
            var recurse:Tokenizer = .init(self.alloc);
            defer recurse.deinit(.{ .free_result = true });
            var reader:std.Io.Reader = .fixed(macro);
            const res = try recurse.do(&reader);
            if (res != .ok) return res.err.err;
            try self.res.appendSlice(self.alloc, res.ok.tokens);
            recurse.alloc.free(res.ok.tokens);
            return null;
        } else
            return error.UnknownMacro;
    }

    if (thing[0] == '@') {
        const res:Token = .{
            .line = self.line_no,
            .value = .{ .ptr = .{
                .use = .{
                    .name = try self.alloc.dupe(u8, thing[1..]),
                    .val = @intCast(self.labels.get(thing[1..]) orelse blk: {
                        self.ident_counter += 1;
                        const name = try self.alloc.dupe(u8, thing[1..]);
                        self.mem.clearAndFree(self.alloc);
                        try self.labels.putNoClobber(name, self.ident_counter);
                        self.type = .pos;
                        break :blk self.ident_counter;
                    }),
                }
            } }
        };
        return res;
    }

    if (thing[0] == '$')
        return .{
            .line = self.line_no,
            .value = .{ .ptr = .{
                .use = .{ .val = (self.ptrs.get(thing[1..]) orelse return error.UnknownIdent) }
            } },
        };

    if (hlp.is_num(thing)) {
        return .{
            .line = self.line_no,
            .value = .{
                .literal = switch (self.type orelse .byte) {
                    .int  => .{ .int  = try parseInt(i256, thing, 10) },
                    .uint => .{ .uint = try parseInt(u256, thing, 10) },
                    .byte => .{ .byte = try parseInt(u8, thing, 10) },

                    .s8  => .{ .s8  = try parseInt(i8, thing, 10) },
                    .s16 => .{ .s16 = try parseInt(i16, thing, 10) },
                    .s32 => .{ .s32 = try parseInt(i32, thing, 10) },
                    .s64 => .{ .s64 = try parseInt(i64, thing, 10) },

                    // NOTE: u8 is covered by 'byte'
                    .u16 => .{ .u16 = try parseInt(u16, thing, 10) },
                    .u32 => .{ .u32 = try parseInt(u32, thing, 10) },
                    .u64 => .{ .u64 = try parseInt(u64, thing, 10) },

                    .f32 => .{ .f32 = try parseFloat(f32, thing) },
                    .f64 => .{ .f64 = try parseFloat(f32,  thing) },

                    .usize => .{ .usize = try parseInt(usize, thing, 10) },
                    .isize => .{ .isize = try parseInt(isize, thing, 10) },

                    else => return error.TypeMissmatch,
                }
            }
        };
    }

    //if (thing.len > 1) if (thing[0] == '"' and thing[thing.len-1] == '"')
    //    return .{
    //        .line = self.line_no,
    //        .value = .{ .literal = .{
    //            .string = try self.alloc.dupe(u8, thing[1..thing.len-1])
    //        } }
    //    };

    if (hlp.cut(thing, '#')) |word_set| {
        const collection = self.words.map.get(word_set[0]) orelse {
            return error.UnknownIdent;
        };
        for (collection) |w| if (std.mem.eql(u8, w.name, word_set[1])) {
            return .{
                .line = self.line_no,
                .value = .{ .literal = .{ .word = w.value } }
            };
        };
    }

    std.debug.print("(line: {d}) |{s}|\n", .{self.line_no, thing});
    return error.InvalidToken;
}

pub fn init_words(self:*Tokenizer) !void {
    self.words.map = .init(self.alloc);
    inline for (comptime [_]struct{ []const u8, type }{
        .{ "SysCall", std.posix.system.SYS },
        .{ "Proc",    ProcessValue         },
    }) |set|
        try self.words.add_set(set[0], set[1]);
}

pub fn construct_err(self:*Tokenizer, err:TokenizerError) !TokenizeResult.ErrInfo {
    inline for ([_]type{
        std.fmt.ParseIntError,
        std.fmt.ParseFloatError,
        std.mem.Allocator.Error,
        std.Io.Writer.Error,
    }) |T|
        if (hlp.err_is_of_type(err, T)) return err;
    return .{
        .err = err,
        .aux_str = null,
        .mem = try self.alloc.dupe(u8, self.mem.items),
        .string = self.string,
        .last_token = self.res.getLastOrNull(),
        .expected = .{
            .type = self.type,
        },
        .pos = .{
            //the current byte
            .byte = self.pos.byte,
            //current line
            .line = .{
                .number = self.line_no,
                .string = self.pos.line orelse "",
            },
        },
    };
}

pub const SeekError = error {
    ReadFailed,
    NotInitialized,
}
  //for tracking the current line in state (for rich errors)
  || std.Io.Writer.Error
  || std.mem.Allocator.Error;

pub fn next(self:*Tokenizer) SeekError!?u8 {
    if (self.reader == null) return error.NotInitialized;
    return
        if (self.reader.?.takeByte()) |byte|
            try self.seek_hook(byte, .advance)
        else |err| switch (err) {
            error.EndOfStream => null,
            error.ReadFailed => error.ReadFailed,
        };
}

pub fn peek(self:*Tokenizer) SeekError!u8 {
    if (self.reader == null) return error.NotInitialized;
    return
        if (self.reader.?.peekByte()) |byte|
            try self.seek_hook(byte, .stay) orelse 0
        else |err| switch (err) {
            error.EndOfStream => 0,
            error.ReadFailed => error.ReadFailed,
        };
}

//gets the nth byte from cur pos
pub fn peekN(self:*Tokenizer, n:usize) SeekError!u8 {
    if (self.reader == null) return error.NotInitialized;
    return
        if (self.reader.?.peek(n)) |c|
            try self.seek_hook(c[c.len-1], .stay) orelse 0
        else |err| switch (err) {
            error.EndOfStream => 0,
            error.ReadFailed => error.ReadFailed,
        };
}

pub fn toss(self:*Tokenizer, n:usize) error{NotInitialized}!void {
    if (self.reader == null) return error.NotInitialized;
    self.reader.?.toss(n);
}

pub fn peek_word(self:*Tokenizer) ![]u8 {
    var res:[]u8 = try self.alloc.alloc(u8, 0);
    while (std.ascii.isWhitespace(try self.peek())) try self.toss(1);
    var o:usize = 1;
    while (true) {
        defer o += 1;
        const b = try self.peekN(o);
        if (b == 0) break;
        if (std.ascii.isWhitespace(b) or b == ';') return res;
        var new = try self.alloc.alloc(u8, res.len+1);
        for (0..res.len) |i| new[i] = res[i];
        new[new.len-1] = b;
        self.alloc.free(res);
        res = new;
    }
    return res;
}

pub fn take_word_if_eql(self:*Tokenizer, target:[]const u8) !?[]u8 {
    const word = try self.peek_word();
    if (std.mem.eql(u8, target, word)) {
        self.toss(word.len);
        return word;
    }
    self.alloc.free(word);
    return null;
}

pub fn take_word(self:*Tokenizer) ![]u8 {
    const w = try self.peek_word();
    try self.toss(w.len);
    return w;
}

pub fn take_word_or_null(self:*Tokenizer) !?[]u8 {
    var res:[]u8 = try self.alloc.alloc(u8, 0);
    while (try self.next()) |b| {
        if (std.ascii.isWhitespace(b) or b == ';') if (res.len > 0) return res else continue;
        const new = try self.alloc.alloc(u8, res.len+1);
        for (0..res.len) |i| new[i] = res[i];
        self.alloc.free(res);
        new[new.len-1] = b;
        res = new;
    }

    if (res.len > 0) return res;
    self.alloc.free(res);
    return null;
}

pub fn toss_word(self:*Tokenizer) !void {
    self.alloc.free(try self.take_word());
}

pub fn toss_word_if_eql(self:*Tokenizer, target:[]const u8) !bool {
    if (try self.take_word_if_eql(target)) |match| {
        self.alloc.free(match);
        return true;
    }
    return false;
}

pub fn bump_line(self:*Tokenizer) !void {
    _ = self.pos.arena.reset(.free_all);
    self.line_no += 1;
    self.pos.line = self.reader.?.peekDelimiterExclusive('\n') catch |e| blk: {
        switch (e) {
            error.EndOfStream, error.StreamTooLong => {
                var res:std.Io.Writer.Allocating = .init(self.pos.arena.allocator());
                defer res.deinit();
                var offset:usize = 1;
                while (true) : (offset += 1) {
                    const b = try self.peekN(offset);
                    if (b == 0) break;
                    if (b != '\n')
                        try res.writer.writeAll(&[_]u8{b})
                    else
                        break;
                }
                break :blk try res.toOwnedSlice();
            },
            error.ReadFailed => |err| return err,
        }
    };
}

pub fn seek_hook(self:*Tokenizer, b:u8, action:enum{advance, stay}) !?u8 {
    self.pos.byte += 1;
    if (b == '\n') try self.bump_line();
    if (b == ';') while (true) {
        const skipped = self.reader.?.discardDelimiterInclusive('\n') catch |e| {
            return switch (e) {
                error.EndOfStream => null,
                error.ReadFailed => error.ReadFailed
            };
        };
        self.pos.byte += skipped;
        try self.bump_line();
        return if (action == .stay) try self.peek() else try self.next();
    };
    return b;
}

pub fn delim(
    self:*Tokenizer,
    b:u8,
    comptime what:enum{ toss, take, peek }
) !if (what == .toss) void else []u8 {
    return switch (what) {
        .toss => while (true) {
            const c = try self.peek();
            if (c == b or c == 0) break;
        },
        .take => try self.reader.?.takeDelimiter(b),
        .peek => try self.reader.?.peekDelimiterExclusive(b),
    };
}
