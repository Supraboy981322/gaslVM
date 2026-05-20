const std = @import("std");
const value = @import("value.zig");
const common = @import("common.zig");

const VM_Allocator = @import("memory.zig").VM_Allocator;
pub const CodeByte = common.CodeByte;
const Value = value.Value;

pub const OpCode = enum(u8) {
    //pops value from stack then jumps to last 'jmp_sav' position
    //  or ends VM
    //  usage:
    //      save_pos
    //      push void
    //        return
    //      stop ;.{ .void = void }
    //    (behaves identically to 'stop' if no 'pos' is saved)
    @"return",

    //stops VM and returns value at top of stack to host
    //  usage:
    //      push byte 1
    //        stop ;.{ .byte = 1 }
    stop,

    //saves the current position in the bytecode (for 'return' to jump back to)
    //  usage:
    //      save_pos
    //      push byte 1 
    //        return
    //      stop ;.{ .byte = 1 }
    //      
    // NOTE: this (with 'return') could be used for control flow
    //   without creating labeled positions
    @"save_pos",

    //pops value from stack and pushes it to a secondary (smaller) stack
    //  usage:
    //      push byte 2
    //      push byte 1
    //        hold
    //      discard
    //      take
    //        return ;.{ .byte = 1 }
    hold,
    //pops value from secondary stack and pushes it to main stack
    //  (see 'hold' for usage)
    take,
    //same as 'hold' but takes an offset from the top
    //  usage:
    //      push byte 2
    //        hold
    //      push byte 1
    //        hold
    //      push byte 3
    //      push byte 1
    //        hold_off
    //      take
    //        discard
    //      take
    //        return ;.{ .byte = 3 }
    hold_off,

    //same as popping a value from stack and pushing it twice
    //  usage
    //      push byte 1
    //        dupe
    //        discard
    //      return ;.{ .byte = 1 }
    dupe,

    //behaves identically to 'save_pos' immediately followed by 'jmp'
    //  usage:
    //      push @foo
    //        jmp_sav
    //        stop ;.{ .byte = 1 }
    //      pos foo
    //      push byte 1
    //        return
    jmp_sav,

    //dupes value from secondary stack into main stack
    //  usage:
    //      push byte 2
    //        hold
    //      push byte 1
    //        hold
    //      take_copy
    //        discard
    //      take
    //        return ;.{ .byte = 1 }
    take_copy,
    //'take' but pops a number from main stack as an offset from 
    //  top of secondary stack
    //  usage:
    //      push byte 2
    //        hold
    //      push byte 1
    //        hold
    //      push byte 1
    //        take_off
    //        return ;.{ .byte = 2 }
    take_off,

    no_op, //does nothing; moves on to next instruction

    //push a value onto the stack
    //  usage:
    //      push 1
    //        return ;.{ .byte = 1 }
    push,

    //arithmetic instructions
    negate, //arithmetic negate pop()
    add,
    sub,
    mult, //multiplication
    div, //division

    //opcodes for faster hard-coded booleans and null
    true,
    false,
    null,

    //logical instructions
    not, //logical negate pop()
    eql, //pop() equals pop()
    greater, //pop() greater-than pop()
    less, //pop() less-than pop()

    //jump to a 'pos' in code
    //  usage:
    //    pos foo
    //    push @foo
    //      jmp
    jmp,

    //conditional jump; only jumps if popped value is 'true'
    //  usage:
    //      pos foo
    //      push int 10
    //      push int 9
    //        sub
    //      push int 1
    //        eql
    //      push @foo
    //        jmpif
    //  NOTE: this pops the 'pos' first, then the boolean
    jmpif,

    //pops from stack, discarding value
    //  usage:
    //      ptr foo
    //      push $foo
    //        discard
    discard,
    
    //allocates space for value in memory, pushes pointer to stack
    //  usage:
    //      ptr foo
    //      push $foo
    //      push byte 2
    //        alloc
    //  NOTE: this does not set the value of the pointer;
    //   it simply pushes the new pointer to the stack,
    //     you must save the pointer manually
    alloc,

    //frees space for value in memory
    //  usage:
    //    push $foo
    //      get
    //      free
    //  NOTE: this does not actually free host's memory
    free,

    // TODO: re-implement these
    ptr_add,
    ptr_sub,

    //saves value from stack into pointer in memory
    //  usage:
    //      ptr foo      ;create pointer
    //      push $foo    ;push pointer to stack
    //      push byte 1  ;push length to stack
    //        alloc      ;allocate space for value (pushes pointer to stack)
    //      push byte 0  ;push value
    //        save       ;save value to pointer
    //  NOTE: 'save' does not push back onto stack
    save,

    //changes value in memory from existing pointer
    //  usage:
    //      push byte 10 ;push value to stack
    //      push $foo    ;push pointer to stack
    //      overwrite    ;change the value
    //  NOTE: calling 'get' is illegal, this instruction changes value in-place
    overwrite,

    //pushes value from (existing) pointer in memory to stack
    //  usage:
    //      push $foo
    //        get
    //      push byte 1
    //        add
    //      push $foo
    //      overwrite
    //  NOTE: this pushes the VM's pointer, not the actual host's pointer
    //   TODO: instruction to specifically push host's pointer (maybe)
    get,
    getH, //same as 'get' but pushes host pointer

    //makes a syscall to either host's OS or a hook to code outside the VM (ie: a Zig function)
    //  usage: (assuming that $idx is the length of the string)
    //      push $idx get  ;string length 
    //      push $string getH ;get host pointer
    //      push 1         ;stdout
    //      push SysCall#.write
    //      push byte 3
    //      syscall
    syscall,

    // TODO: these
    mutex,   //triggers a lock for VM; locking blocks until unlocked
    remove,  //removes from pointer pool


    print, // TODO: remove (for debugging purposes)
    

    pub fn from_byte(b:u8) OpCode {
        return @enumFromInt(b);
    }

    pub fn to_string(self:OpCode) []u8 {
        return @ptrCast(@constCast(@tagName(self)));
    }
};

pub const Chunk = struct {
    code:std.ArrayList(CodeByte) = .empty,
    constants:std.ArrayList(Value) = .empty,
    alloc:std.mem.Allocator,
    vm_alloc:VM_Allocator,
    line_nums:[]usize = @constCast(&[_]usize{}), // TODO: this is really inefficient for memory
    running:bool = false,

    pub fn init(alloc:std.mem.Allocator, vm_alloc:VM_Allocator) Chunk {
        return .{
            .alloc = alloc,
            .vm_alloc = vm_alloc,
        };
    }

    pub fn deinit(self:*Chunk) void {
        self.code.deinit(self.alloc);
        for (self.constants.items) |_| {
            //if (c == .string) self.alloc.free(c.string);
        }
        self.constants.deinit(self.alloc);
        self.alloc.free(self.line_nums);
        self.vm_alloc.deinit();
    }

    pub fn add_line_no(self:*Chunk, num:usize) !void {
        var new = try self.alloc.alloc(usize, self.line_nums.len+1);
        for (self.line_nums, 0..) |n, i| new[i] = n;
        self.alloc.free(self.line_nums);
        new[new.len-1] = num;
        self.line_nums = new;
    }

    pub fn add_op(self:*Chunk, c:OpCode, line_num:?usize) !void {
        if (line_num) |n| try self.add_line_no(n);
        try self.code.append(self.alloc, .{ .code = @intFromEnum(c) });
    }

    pub fn add_const(self:*Chunk, v:Value, line_num:usize) !u16 {
        if (self.running) unreachable;
        try self.add_line_no(line_num);
        try self.constants.append(self.alloc, v);
        const constant:CodeByte =
            if (self.constants.items.len > std.math.maxInt(u8))
                .{ .long_const = @intCast(self.constants.items.len-1) }
            else
                .{ .short_const = @intCast(self.constants.items.len-1) };
        try self.code.append(self.alloc, constant);
        return @intCast(self.constants.items.len);
    }

    pub fn get_const(self:*Chunk, i:usize) *Value {
        if (self.code.items.len < i) unreachable; //index into const pool out of range
        const thing = self.code.items[i];
        const idx:usize =
            if (thing == .short_const)
                @intCast(thing.short_const)
            else if (thing == .long_const)
                thing.long_const
            else
                unreachable; //get_const() index into non-constant byte
        return @constCast(&self.constants.items[idx]);
    }

    pub fn get_pos_ptr(self:*Chunk, pos:?usize) [*]CodeByte {
        const p = if (pos) |p| p else self.code.items.len-1;
        return self.code.items.ptr + p;
    }
};
