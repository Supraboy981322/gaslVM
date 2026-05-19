const std = @import("std");
const common = @import("common.zig");
const Tokenizer = @import("tokenizer.zig");
const Keyword = common.Keyword;
const TokenWord = common.Data.TokenWord;

pub const DataKeywords = enum {
    words,
    def,
};

const Parser = @This();

tokenizer:*Tokenizer,

fn init(tokenizer:*Tokenizer) Parser {
    return .{
        .tokenizer = tokenizer,
    };
}

pub fn parse(tokenizer:*Tokenizer) !void {
    var parser:Parser = .init(tokenizer);
    try parser.do();
}

fn do(self:*Parser) !void {
    var alloc = self.tokenizer.alloc;

    var collection:[][]u8 = try alloc.alloc([]u8, 0);
    defer alloc.free(collection);

    var name:?[]u8 = null;
    var parsing_collection:bool = false;

    var value:?[]u8 = null;

    while (try self.tokenizer.take_word_or_null()) |word| {
        if (std.meta.stringToEnum(Keyword, word)) |keyword| {
            alloc.free(word);
            switch (keyword) {
                .end => return,
                else => return error.MisplacedKeyword,
            }
            continue;
        }
        if (name) |_| {
            if (std.meta.stringToEnum(DataKeywords, word)) |keyword| {
                alloc.free(word);
                switch (keyword) {
                    .words => {
                        try self.add_words(collection, name.?);
                        alloc.free(collection);
                        collection = try alloc.alloc([]u8, 0);
                        name = null;
                    },
                    .def => {
                        try self.add_def(value.?, name.?);
                        alloc.free(collection);
                        collection = try alloc.alloc([]u8, 0);
                        name = null;
                    },
                }
                continue;
            }
            return error.InvalidToken;
        }

        if (std.mem.eql(u8, word, "(")) {
            alloc.free(word);
            if (collection.len > 0) return error.MisplacedSymbol;
            parsing_collection = true;
            continue;
        } else if (std.mem.eql(u8, word, ")")) {
            alloc.free(word);
            name = try self.tokenizer.take_word();
            parsing_collection = false;
            continue;
        }

        if (parsing_collection) {
            const new = try alloc.alloc([]u8, collection.len+1);
            for (collection, 0..) |item, i| new[i] = item;
            new[new.len-1] = word;
            alloc.free(collection);
            collection = new;
            continue;
        }

        if (value) |_|
            name = word
        else if (name == null)
            value = word
        else
            return error.InvalidToken;
    }
}

pub fn add_words(self:*Parser, collection:[][]u8, name:[]u8) !void {
    var alloc = &self.tokenizer.alloc;
    try self.tokenizer.words.put(name, blk: {
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

pub fn add_def(self:*Parser, value:[]u8, name:[]u8) !void {
    try self.tokenizer.defs.put(name, value);
}
