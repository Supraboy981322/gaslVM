# instructions

a usage example is included for most instructions
(and each usage example is a complete runnable segment of code)

## generic
- `return`

  returns value popped from the stack.

>[!NOTE]
>Every program should end with a value and a `return` (it is undefined behavior otherwise).

  TODO: don't end VM, return value to 'pos' (or something)

  ```asm
  push void
    return ;.{ .void = void }
  ```


- `no_op`

  does nothing; moves on to next instruction

  ```asm
  no_op
  push void
    return
  ```

- `push`

  push a value onto the stack

  ```asm
  push int 1
    discard
  push void
    return
  ```

- `discard`

  pops from stack, discarding value

  ```asm
  ptr foo
  push $foo
    discard
  push void
    return
  ```

- `syscall`

  makes a syscall to either host's OS or a hook to code outside the VM (ie: a Zig function)

  TODO: said hooks

  (assuming that `$string` is pointer to a string and `$idx` is the length of the string)

  ```asm
  push $idx get  ;string length 
  push $string getH ;get host pointer
  push 1         ;stdout
  push .write    ;which syscall
  push byte 3    ;number of arguments
    syscall
    return ;.{ .u64 = 10 } (the return value varies)
  ```

- `jmp`

  jump to a 'pos' in code

  ```asm
  ;infinite loop (never returns a value)
  pos foo
  push @foo
    jmp
  ```

- `jmpif`

  conditional jump; only jumps if popped value is 'true'

>[!NOTE]
>this pops the 'pos' first, then the boolean

  ```asm
  ;infinite loop (never returns a value)
  pos foo
  push int 10
  push int 9
    sub
  push int 1
    eql
  push @foo
    jmpif
  ```

---

## arithmetic instructions

- `negate`

  pops a value and negates it

  ```asm
  push int 1
    negate
    return ;.{ .int = -1 }
  ```

- `add`

  pops two values and adds them

  ```asm
  push uint 1
  push uint 2
    add
    return ;.{ .uint = 3 }
  ```

- `sub`

  pops two values and subtracts them

  ```asm
  push f32 1.1
  push f32 2
    sub
    return ;.{ .f32 = -0.9 }
  ```

- `mult`

  pops two values and multiplies them

  ```asm
  push f64 3.3
  push f64 0.1
    mult
    return ;.{ .f32 = 0.33 }
  ```

- `div`

  pops two values and divides them

  ```asm
  push f32 3.3
  push f32 1.1
    div
    return ;.{ .f32 = 3 }
  ```
---

## instructions for common values

These all just push the value to the stack

- `true`
- `false`
- `null`

## logical instructions

>[!WARNING]
>all of these have very little type safety,
>  they pop values and immediately access the expected field types
>    (as in without checking the type)

- `not`

  pops a boolean value and does logical negate

  ```asm
  true
  false
    not
    eql
    return ;.{ .bool = true }
  ```

- `eql`

  pops two values and checks if they're equal

  ```asm
  push byte 10
  push int 11
    eql
    not
  return ;.{ .bool = true }
  ```

- `greater`

  pops two values and checks if the second popped value is greater than the first

  ```asm
  push int 2
  push int 1
    greater
    return ;.{ .bool = true }
  ```

- `less`

  pops two values and checks if hte second popped value is less than the first

  ```asm
  push int 1
  push int 3
    less
    return ;.{ .bool = true }
  ```

---

## pointers and allocation

>[!NOTE]
>memory is marked as "leaked" in debug mode if it is not freed
>  meaning if you return a value which was allocated, it will be marked
>    as leaked (all of these examples except `free` leak memory)

- `alloc`

  allocates space for value in memory, pushes pointer to stack

>[!NOTE] this does not set the value of the pointer;
>  it simply pushes the new pointer to the stack, you
>    must save the pointer manually

  ```asm
  ptr foo
  push $foo
  push byte 1
    alloc
  push byte 15
    save
  push $foo
    get
    return ;.{ .byte = 15 }
  ```

- `free`

  marks a section of memory as not taken and sets the value of the pointer to `null`

>[!NOTE]
>this does not actually free host's memory

  ```asm
  ptr foo
  push $foo
  push byte 1
    alloc
  push byte 15
    save
  push $foo
  push byte 1
    free
  push $foo
    return ;.{ .ptr = .{ .ident = 1, .val = null } }
  ```

- `save`

  saves a value from the stack into a pointer in memory

>[!NOTE]
>'save' does not push back onto the stack

  ```asm
  ptr foo      ;create pointer
  push $foo    ;push pointer to stack
  push byte 1  ;push length to stack
    alloc      ;allocate space for value (pushes pointer to stack)
  push byte 0  ;push value
    save       ;save value to pointer
  push $foo
    get
    return ;.{ .byte = 0 }
  ```

- `overwrite`

  changes value in memory from existing pointer

>[!NOTE]
>calling `get` is illegal, this instruction changes the value in-place
>  (meaning, do not push a pointer, call `get`, then try to call `overwrite`)

  ```asm
  ptr foo
  push $foo
  push byte 1
    alloc
  push byte 2
    save
  push byte 10 ;push value to stack
  push $foo    ;push pointer to stack
    overwrite  ;change the value
  push $foo
    get
    return ;.{ .byte = 10 }
  ```

- `get`

  pushes a value from an existing pointer in memory to the stack

>[!NOTE]
>this pushes the VM's pointer, not the actual host's pointer
>  (see `getH` for the host system's pointer)

  ```asm
  ptr foo
  push $foo
  push byte 1
    alloc
  push byte 1
    save

  push $foo
    get
  push byte 1
    add
  push $foo
    overwrite
  push $foo
    get
    return ;.{ .byte = 2 }
  ```

- `getH`
  mostly used the same as 'get' but pushes host pointer; at the moment, this is 
  just for things like syscalls

>[!WARNING]
>this just creates a `u64` value for the literal number value of the pointer
>  therefore things like `ptr_add` and `ptr_sub` are illegal here

  ```
  ptr foo      ;create pointer
  push $foo    ;push pointer to stack
  push byte 1  ;push length to stack
    alloc      ;allocate space for value (pushes pointer to stack)
  push byte 0  ;push value
    save       ;save value to pointer
  push $foo
    getH
    return ;.{ .u64 = 140266932862976 }  (the exact value will vary)
  ```

- `ptr_add`

  pointer arithmetic addition

  ```asm
  ptr foo

  push byte 1 ;this doesn't get popped until first 'ptr_add'
  push $foo
  push byte 2
    alloc
    ptr_add
  push byte 97
    save
  
  push byte 1
  push $foo
    ptr_add
    return ;.{ .byte = 97 }
  ```

- `ptr_sub`

  pointer arithmetic subtraction

  ```asm
  ptr foo

  push $foo
  push byte 1
    alloc
    discard

  push byte 1 ;this doesn't get popped until the first 'ptr_sub'
  push $foo
  push byte 1
    alloc
    ptr_sub
  push byte 97
    save
  
  push byte 1
  push $foo
    ptr_sub
    return ;.{ .byte = 97 }
  ```

<!--
    // TODO: these
    remove,  //removes from pointer pool
-->


## instructions for Zig debug builds

>[!WARNING]
>the following functions are only legal in Zig debug builds
>  use of them outside of a Zig debug build will trigger an
>    `error.IllegalInstruction` at runtime

- `print`
  prints a value of the union type `Value` using Zig's std.Io.Writer.print

  format string `{any}`, followed by a newline

  ```asm
  push byte 100
    print  ;.{ .byte = 100 }
  push void
    return ;.{ .void = void }
  ```
