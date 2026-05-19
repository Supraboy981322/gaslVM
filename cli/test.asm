ptr str
push $str
push 10
  alloc
push byte 0
  save

push $str
push 10
push @build_string
  jmp_sav
  discard

ptr return_code
push $return_code
push byte 1
  alloc
push byte 0
  save

push 10
push $str getH ;host pointer to string
push 1         ;stdout
push .write
push byte 3
  syscall
push $return_code
  overwrite

push $str
push 10
  free

push $return_code
  stop

pos build_string

  hold ;length (internally remaining length)
  hold ;result pointer

 push 10 ;'a'
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

  push @build_string_loop
  push 1 take_off ;length
  push 0
    eql
    not
    jmpif

push void
  return
