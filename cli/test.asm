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

ptr return_code
push $return_code
push u64 1
  alloc
push byte 0
  save

push %str_len
push $str getH ;host pointer to string
push 1         ;stdout
push SysCall#write
push byte 3
  syscall
push $return_code
  overwrite

push $str
push %str_len
  free

push $return_code
  stop

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
