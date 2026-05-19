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

Making a Linux syscall (this constructs a string (`aaaaaaaaaa`) and prints it to stdout):
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
push 1         ;stdout
push SysCall#write
push byte 3
syscall

push void
  return
```
