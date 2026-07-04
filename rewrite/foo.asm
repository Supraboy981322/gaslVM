push 1        ;len of ptr in bytes
alloc         ;allocates ptr and pushes to stack
move r0       ;pops ptr from stack and places into r0

push 97       ;'a'
push 1        ;width of num in bytes
put r0        ;puts value ('a') into ptr in r0

push 1        ;len of string
move r1       ;move len of string to r1
print r0 r1   ;print ptr in r0 with len in r1

push 1        ;len (in bytes) of ptr
free r0       ;frees ptr in r0

jam           ;kills the VM (with err)
