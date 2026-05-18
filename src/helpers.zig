pub const std = @import("std");

pub fn is_num(str:[]u8) bool {
    return for (str) |b| {
        if ((b > '9' or b < '0') and (b != '.' and b != ',')) break false;
    } else true;
}

pub fn cut(str:[]u8, thing:u8) ?[2][]u8 {
    for (str, 0..) |b, i|
        if (b == thing) return .{ str[0..i], str[if (i+1 < str.len) i+1 else i..] };
    return null;
}
