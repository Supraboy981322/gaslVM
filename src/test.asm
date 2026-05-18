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
push .write
push byte 3
  syscall
  return
