again:

  push 2        ;len of ptr in bytes
  alloc         ;allocates ptr and pushes to stack
  move r0       ;pops ptr from stack and places into r0

  push 97       ;'a'
  push 1        ;width of num in bytes
  store r0      ;puts value ('a') into ptr in r0

  push 1        ;push 1 to stack
  move r1       ;move to r1
  add r0 r1     ;add 1 to string ptr

  push 10       ;'\n' (newline
  push 1        ;width of num in bytes
  store r0      ;puts value ('a') into ptr in r0

  sub r0 r1     ;sub 1 from string ptr to revert back to start of string

  push 2        ;len of string
  move r1       ;move len of string to r1
  print r0 r1   ;print ptr in r0 with len in r1

  push 2        ;len (in bytes) of ptr
  free r0       ;frees ptr in r0

jump :again

jam           ;kills the VM (with err)
