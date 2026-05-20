data
  { byte 10 } str_len macro
  ; TODO: debug macros; creating a complex macro has strange behavior
end

ptr str
push $str
push %str_len
  alloc
push byte 0
  save

push $str
push %str_len
push @build_string
  jmp_sav
  discard

push %str_len
push $str getH ;host pointer to string
push usize 1     ;stdout
push SysCall#write
push byte 3
  syscall
  discard

push $str
push %str_len
  free

push byte 0
push SysCall#exit
push byte 1
  syscall

unreachable

pos build_string

  hold ;length (internally remaining length)
  hold ;result pointer

  push 10 ;'\n'
  push 1 take_off ;length
    push 1
    sub
  take_copy ;result pointer
    ptr_add
    overwrite

  push 1 take_off
  push 1
    sub
  push 1
    hold_off

  pos build_string_loop

    push 97 ;'a'
    push 1 take_off ;length
      push 1
      sub
    take_copy ;result pointer
      ptr_add
      overwrite

    push 1 take_off
    push 1
      sub
    push 1
      hold_off

  push 1 take_off ;length
  push 0
    eql
    not
  push @build_string_loop
    jmpif

push void
  return
