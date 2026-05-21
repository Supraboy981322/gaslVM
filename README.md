# gaslVM
Generic and Simple Language VM

## examples

This returns `-25.760002`:
```asm
push f32 1.2
push f32 3.4
  add
push f32 5.6
  mult
  negate
  return
```

printing to stdout (`foo` followed by a newline) (note that this leaks 4 bytes of memory (plus a type identifier byte))
```asm
data
  1 no_leak_test setting
end

push byte 4   ;length of string (for the syscall)
push byte 102 ;'f'
push byte 111 ;'o'
push byte 111 ;'o'
push byte 10  ;newline
push byte 4   ;length of string (for 'string' instruction)
  string
  getH        ;get the host's pointer (for the syscall)
push usize 1  ;stdout
push SysCall#write
push byte 3   ;number of parameters (length, string, then fd)
  syscall     ;actually make the syscall

;end the interpreter
push void
  stop
```

constructing a string (`aaaaaaaaaa`) and printing it to stderr:
```asm
ptr str
push $str
push byte 10
  alloc
push byte 97
  save

ptr idx
push $idx
push byte 1
  alloc
push byte 0
  save

pos loop

  push 97
  push $idx
    get
  push $str
    ptr_add
    overwrite

  push $idx
    get
  push 1
    add
  push $idx
    overwrite

push $idx
  get
push 10
  eql
  not
push @loop
  jmpif

push $idx get  ;string length 
push $str getH ;get host pointer
push 2         ;stderr
push SysCall#write
push byte 3
syscall

push void
  return
```
