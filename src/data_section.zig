const std = @import("std");
const common = @import("common.zig");
const Tokenizer = @import("tokenizer.zig");
const ProcessValue = @import("value.zig").ProcessValue;
const Keyword = common.Keyword;
const TokenWord = common.Data.TokenWord;

pub const DataKeywords = enum {
    words,
    macro,
    load, //constant values loaded by the VM at startup like argv/argc
};

pub const DataSymbols = enum {
    @"(", @")",
    @"{", @"}",
};

const Parser = @This();

tokenizer:*Tokenizer,
collection:[][]u8 = undefined,
value:?[]u8 = null,
name:?[]u8 = null,

fn init(tokenizer:*Tokenizer) Parser {
    return .{
        .tokenizer = tokenizer,
    };
}

pub fn parse(tokenizer:*Tokenizer) !void {
    var parser:Parser = .init(tokenizer);
    try parser.do();
}

const ParsingAs = enum {
    collection,
    macro,
};

fn do(self:*Parser) !void {
    var alloc = self.tokenizer.alloc;

    self.collection = try alloc.alloc([]u8, 0);

    defer {
        if (self.value) |v| alloc.free(v);
        if (self.name) |n| alloc.free(n);
    }

    var parsing:?ParsingAs = null;

    while (try self.tokenizer.take_word_or_null()) |word| {
        if (std.meta.stringToEnum(Keyword, word)) |keyword| {
            alloc.free(word);
            switch (keyword) {
                .end => return,
                else => return error.MisplacedKeyword,
            }
            continue;
        }
        if (self.name) |_| {
            if (std.meta.stringToEnum(DataKeywords, word)) |keyword| {
                alloc.free(word);
                switch (keyword) {
                    .words => {
                        try self.add_words(self.collection, self.name.?);
                        alloc.free(self.collection);
                        self.collection = try alloc.alloc([]u8, 0);
                        self.name = null;
                    },
                    .macro => {
                        if (self.value == null) return error.MissingMacroDef;
                        try self.add_macro(try alloc.dupe(u8, self.value.?[0..self.value.?.len-1]), self.name.?);
                        self.collection = try alloc.alloc([]u8, 0);
                        self.name = null;
                    },
                    .load => {
                        const what = std.meta.stringToEnum(
                            ProcessValue, self.name orelse return error.MissplacedKeyword
                        ) orelse return error.InvalidLoad;
                        try self.tokenizer.loads.append(alloc, what);
                        alloc.free(self.name.?);
                        self.name = null;
                        continue;
                    },
                }
                continue;
            }
            return error.InvalidToken;
        }

        if (std.meta.stringToEnum(DataSymbols, word)) |symbol| switch (symbol) {
            inline .@"(", .@"{" => |which| if (parsing == null) {
                alloc.free(word);
                if (self.collection.len > 0) return error.MisplacedSymbol;
                parsing = switch (comptime which) {
                    .@"(" => .collection,
                    .@"{" => .macro,
                    else => unreachable,
                };
                continue;
            },
            inline .@")", .@"}" => |which|
                if (parsing == (comptime if (which == .@")") .collection else .macro)) {
                    alloc.free(word);
                    self.name = try self.tokenizer.take_word();
                    parsing = null;
                    continue;
                },
        };

        if (parsing) |p| {
            try self.do_type(p, word);
            continue;
        }

        if (self.value) |_|
            self.name = word
        else if (self.name == null)
            self.value = word
        else
            return error.InvalidToken;
    }
}

pub fn add_words(self:*Parser, collection:[][]u8, name:[]u8) !void {
    var alloc = &self.tokenizer.alloc;
    try self.tokenizer.words.map.put(name, blk: {
        var res:[]TokenWord = try alloc.alloc(TokenWord, 0);
        for (collection, 0..) |w, i| {
            var new = try alloc.alloc(TokenWord, res.len+1);
            for (0..res.len) |j| new[j] = res[j];
            new[new.len-1] = .{
                .name = w,
                .value = @intCast(i),
            };
            alloc.free(res);
            res = new;
        }
        break :blk res;
    });
}

pub fn add_macro(self:*Parser, value:[]u8, name:[]u8) !void {
    try self.tokenizer.macros.put(name, value);
}

fn do_type(self:*Parser, p:ParsingAs, word:[]u8) !void {
    var alloc = self.tokenizer.alloc;

    switch (p) {
        .collection => {
            const new = try alloc.alloc([]u8, self.collection.len+1);
            for (self.collection, 0..) |item, i| new[i] = item;
            new[new.len-1] = word;
            alloc.free(self.collection);
            self.collection = new;
        },
        .macro => {
            defer alloc.free(word);
            var new = try alloc.alloc(u8, if (self.value) |v| v.len+word.len+1 else word.len+1);
            if (self.value) |v| {
                for (0..v.len) |i| new[i] = v[i];
                alloc.free(v);
            }
            for (0..word.len) |i| new[(new.len-word.len-1)+i] = word[i];
            new[new.len-1] = ' ';
            self.value = new;
        },
    }
}
