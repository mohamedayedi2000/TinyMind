; =====================================================================
; TINYMIND -- interp.asm (v2)
; A small but genuinely Turing-loop-capable BASIC-flavoured language:
;   LET <name> = <term> [<op> <term2>]      op in + - * /
;   PRINT <term>
;   IF <term><relop><term> THEN PRINT <term>|LET <name>=<term>|GOTO <n>
;   GOTO <n>                          (only meaningful inside RUN)
;   <n> <statement>                   store <statement> as program line n
;   <n>                               (with nothing else) delete line n
;   RUN / PLIST / NEW / END (or STOP)
; <name> is any identifier not starting with a digit (see vars.asm);
; <term> is a <name> or a decimal number; relop is = < >.
; =====================================================================

kw_then:            db "THEN",0
eq_sign:            db "=",0
msg_syntax_error:   db "?SYNTAX ERROR",0
msg_var_full:       db "Variable table is full.",0
msg_prog_empty:     db "No program stored.",0
msg_prog_full:      db "Program is full.",0
msg_too_many_steps: db "?TOO MANY STEPS (possible infinite loop) -- stopped.",0
msg_undefined_line: db "?UNDEFINED LINE -- stopped.",0
msg_new_done:       db "New workspace: program and variables cleared.",0
msg_goto_no_run:    db "?GOTO only makes sense while a program is RUNning.",0
msg_gosub_full:     db "?GOSUB nested too deep.",0
msg_return_empty:   db "?RETURN without GOSUB.",0
msg_for_full:       db "?FOR nested too deep.",0
msg_next_empty:     db "?NEXT without FOR.",0
msg_next_mismatch:  db "?NEXT doesn't match its FOR.",0
kw_to:              db "TO",0
kw_step:            db "STEP",0

; ---------------------------------------------------------------------
; term evaluation
; ---------------------------------------------------------------------

; interp_get_term : evaluate token #AL as a term -- a variable name (any
; identifier not starting with a digit or '-') or a decimal number,
; optionally negative.
; Out: AX = value, CF = 1 on error (only when neither parses at all).
interp_get_term:
    push si
    push di
    push cx

    call util_get_token          ; di -> scratch (this token's text)
    mov si, di
    mov al, [si]
    cmp al, '-'
    je .as_number
    cmp al, '0'
    jb .as_var
    cmp al, '9'
    ja .as_var
.as_number:
    call util_atoi
    jmp .done
.as_var:
    call var_lookup_or_zero
    clc
.done:
    pop cx
    pop di
    pop si
    ret

; ---------------------------------------------------------------------
; LET / PRINT
; ---------------------------------------------------------------------

; interp_let : "LET <name> = <term> [<op> <term2>]"
interp_let:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    mov al, [token_count]
    mov ah, 0
    cmp ax, 4
    jae .have_min
    jmp .syntax_err

.have_min:
    mov al, 1
    call util_get_token             ; di -> scratch (destination name)
    mov al, [di]
    cmp al, '0'
    jb .name_ok
    cmp al, '9'
    jbe .syntax_err                  ; can't assign to something number-shaped
.name_ok:
    mov si, scratch
    mov di, scratch2
    mov cx, VARNAME_LEN
    call util_copy_bounded           ; scratch2 = destination name (safe copy)

    mov si, [token_ptr+4]             ; token[2]
    mov cl, [token_len+2]
    mov ch, 0
    mov di, eq_sign
    call util_tok_eq
    cmp al, 0
    jne .eq_ok
    jmp .syntax_err
.eq_ok:
    mov al, 3
    call interp_get_term
    jc .syntax_err

    mov bx, [token_count]
    and bx, 0x00ff
    cmp bx, 6
    jae .binary_form
    jmp .store

.binary_form:
    push ax

    mov al, [token_len+4]
    cmp al, 1
    jne .binary_err
    mov si, [token_ptr+8]              ; token[4] = operator
    mov dh, [si]

    mov al, 5
    call interp_get_term
    jc .binary_err
    mov bx, ax
    pop ax

    cmp dh, '+'
    jne .try_sub
    add ax, bx
    jmp .store
.try_sub:
    cmp dh, '-'
    jne .try_mul
    sub ax, bx
    jmp .store
.try_mul:
    cmp dh, '*'
    jne .try_div
    push dx
    mul bx
    pop dx
    jmp .store
.try_div:
    cmp dh, '/'
    jne .syntax_err
    cmp bx, 0
    je .syntax_err
    push dx
    cwd
    idiv bx
    pop dx
    jmp .store

.binary_err:
    add sp, 2                          ; discard the pushed term1
    jmp .syntax_err

.store:
    mov dx, ax
    mov si, scratch2
    call var_assign
    jc .table_full
    jmp .done

.table_full:
    mov si, msg_var_full
    call io_print_str
    call io_print_crlf
    jmp .done

.syntax_err:
    mov si, msg_syntax_error
    call io_print_str
    call io_print_crlf

.done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; interp_print : "PRINT <term>"
interp_print:
    push ax

    mov al, [token_count]
    mov ah, 0
    cmp ax, 2
    jae .have_arg
    jmp .syntax_err

.have_arg:
    mov al, 1
    call interp_get_term
    jc .syntax_err
    call io_print_num
    call io_print_crlf
    jmp .done

.syntax_err:
    push si
    mov si, msg_syntax_error
    call io_print_str
    call io_print_crlf
    pop si

.done:
    pop ax
    ret

; ---------------------------------------------------------------------
; IF ... THEN PRINT|LET|GOTO ...
; ---------------------------------------------------------------------

interp_if:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    mov al, [token_count]
    mov ah, 0
    cmp ax, 5
    jae .have_min
    jmp .syntax_err

.have_min:
    mov si, [token_ptr+8]         ; token[4]
    mov cl, [token_len+4]
    mov ch, 0
    mov di, kw_then
    call util_tok_eq
    cmp al, 0
    jne .then_ok
    jmp .syntax_err

.then_ok:
    mov al, 1
    call interp_get_term
    jc .syntax_err
    push ax

    mov al, [token_len+2]
    cmp al, 1
    jne .cond_err
    mov si, [token_ptr+4]          ; token[2] = relop
    mov dl, [si]

    mov al, 3
    call interp_get_term
    jc .cond_err
    pop bx                          ; bx = left value, ax = right value

    cmp dl, '='
    jne .try_lt
    cmp bx, ax
    je .cond_true
    jmp .cond_false
.try_lt:
    cmp dl, '<'
    jne .try_gt
    cmp bx, ax
    jl .cond_true
    jmp .cond_false
.try_gt:
    cmp dl, '>'
    jne .cond_false
    cmp bx, ax
    jg .cond_true
    jmp .cond_false

.cond_err:
    add sp, 2
    jmp .syntax_err

.cond_true:
    mov si, [token_ptr+10]           ; token[5]
    mov cl, [token_len+5]
    mov ch, 0
    mov di, kw_print
    call util_tok_eq
    cmp al, 0
    je .maybe_let_or_goto

    mov al, [token_count]
    mov ah, 0
    cmp ax, 7
    jae .then_print_ok
    jmp .syntax_err
.then_print_ok:
    mov al, 6
    call interp_get_term
    jc .syntax_err
    call io_print_num
    call io_print_crlf
    jmp .done

.maybe_let_or_goto:
    mov di, kw_let
    call util_tok_eq
    cmp al, 0
    jne .then_let
    mov di, kw_goto
    call util_tok_eq
    cmp al, 0
    jne .then_goto
    mov di, kw_gosub
    call util_tok_eq
    cmp al, 0
    jne .then_gosub
    jmp .syntax_err

.then_goto:
    mov al, [token_count]
    mov ah, 0
    cmp ax, 7
    jae .then_goto_ok
    jmp .syntax_err
.then_goto_ok:
    mov al, 6
    call interp_get_term
    jc .syntax_err
    call prog_do_goto
    jmp .done

.then_gosub:
    mov al, [token_count]
    mov ah, 0
    cmp ax, 7
    jae .then_gosub_ok
    jmp .syntax_err
.then_gosub_ok:
    mov al, 6
    call interp_get_term
    jc .syntax_err
    call prog_do_gosub
    jmp .done

.then_let:
    mov al, [token_count]
    mov ah, 0
    cmp ax, 9
    jae .then_let_ok
    jmp .syntax_err
.then_let_ok:
    mov al, 6
    call util_get_token              ; di -> scratch (destination name)
    mov al, [di]
    cmp al, '0'
    jb .let_name_ok
    cmp al, '9'
    jbe .syntax_err
.let_name_ok:
    mov si, scratch
    mov di, scratch2
    mov cx, VARNAME_LEN
    call util_copy_bounded

    mov si, [token_ptr+14]             ; token[7]
    mov cl, [token_len+7]
    mov ch, 0
    mov di, eq_sign
    call util_tok_eq
    cmp al, 0
    jne .let_eq_ok
    jmp .syntax_err
.let_eq_ok:
    mov al, 8
    call interp_get_term
    jc .syntax_err

    mov dx, ax
    mov si, scratch2
    call var_assign
    jmp .done

.cond_false:
    jmp .done

.syntax_err:
    mov si, msg_syntax_error
    call io_print_str
    call io_print_crlf

.done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ---------------------------------------------------------------------
; stored program: line storage, RUN, PLIST, NEW, END, GOTO
; ---------------------------------------------------------------------

; prog_find_line : is line number BX already stored?
; Out: AX = index, or 0xFFFF if not found. BX preserved.
prog_find_line:
    push bx
    push cx
    push si

    xor cx, cx
.loop:
    mov al, [prog_count]
    mov ah, 0
    cmp cx, ax
    jae .notfound

    mov si, cx
    shl si, 1
    cmp bx, [prog_line_no+si]
    je .found

    inc cx
    jmp .loop

.found:
    mov ax, cx
    jmp .done
.notfound:
    mov ax, 0xFFFF
.done:
    pop si
    pop cx
    pop bx
    ret

; prog_find_min : AX = smallest stored line number, or 0xFFFF if empty.
prog_find_min:
    push bx
    push cx
    push si

    mov al, [prog_count]
    cmp al, 0
    jne .have
    mov ax, 0xFFFF
    jmp .done
.have:
    mov bx, 0xFFFF
    xor cx, cx
.loop:
    mov al, [prog_count]
    mov ah, 0
    cmp cx, ax
    jae .finish

    mov si, cx
    shl si, 1
    mov ax, [prog_line_no+si]
    cmp ax, bx
    jae .next
    mov bx, ax
.next:
    inc cx
    jmp .loop
.finish:
    mov ax, bx
.done:
    pop si
    pop cx
    pop bx
    ret

; prog_find_next_after : AX = smallest stored line number strictly
; greater than BX, or 0xFFFF if none. BX preserved.
prog_find_next_after:
    push bx
    push cx
    push si
    push di

    mov si, 0xFFFF
    xor cx, cx
.loop:
    mov al, [prog_count]
    mov ah, 0
    cmp cx, ax
    jae .finish

    mov di, cx
    shl di, 1
    mov ax, [prog_line_no+di]
    cmp ax, bx
    jbe .next
    cmp si, 0xFFFF
    je .take
    cmp ax, si
    jae .next
.take:
    mov si, ax
.next:
    inc cx
    jmp .loop
.finish:
    mov ax, si
    pop di
    pop si
    pop cx
    pop bx
    ret

; prog_store_line : token[0] is a line number. token_count==1 deletes
; that line; otherwise "the rest of the line" (still space-intact,
; thanks to the non-destructive tokenizer) is stored as its text.
prog_store_line:
    push ax
    push bx
    push cx
    push si
    push di

    mov al, 0
    call util_get_token          ; di -> scratch (the line-number text)
    mov si, di
    call util_atoi
    jc .done                       ; not actually a valid number: ignore
    mov bx, ax                      ; bx = line number

    call prog_find_line             ; -> ax = existing index or 0xFFFF

    mov cx, [token_count]
    and cx, 0x00ff
    cmp cx, 1
    jne .store_text

    ; delete: only meaningful if it was found
    cmp ax, 0xFFFF
    je .done
    mov cx, ax                       ; cx = index to remove
    mov al, [prog_count]
    dec al
    cmp cl, al
    je .just_shrink                   ; removing the last slot: nothing to move

    ; move the LAST entry into the removed slot, then shrink
    push cx
    mov ah, 0
    mov al, [prog_count]
    dec ax
    shl ax, 1
    mov si, ax
    mov di, cx
    shl di, 1
    mov ax, [prog_line_no+si]
    mov [prog_line_no+di], ax
    pop cx

    push cx
    mov ah, 0
    mov al, [prog_count]
    dec al
    mov ah, 0
    mov bx, PROGLINE_LEN
    mul bx
    mov si, prog_text
    add si, ax
    pop ax
    mov bx, PROGLINE_LEN
    mul bx
    mov di, prog_text
    add di, ax
    mov cx, PROGLINE_LEN
    cld
    rep movsb

.just_shrink:
    dec byte [prog_count]
    jmp .done

.store_text:
    cmp ax, 0xFFFF
    jne .overwrite

    mov al, [prog_count]
    cmp al, MAX_PROG_LINES
    jb .append
    mov si, msg_prog_full
    call io_print_str
    call io_print_crlf
    jmp .done

.append:
    mov al, [prog_count]
    mov ah, 0
    shl ax, 1
    mov si, ax
    mov [prog_line_no+si], bx

    mov al, [prog_count]
    mov ah, 0
    mov bx, PROGLINE_LEN
    mul bx
    mov di, prog_text
    add di, ax
    mov si, [token_ptr+2]              ; token[1] onward: the statement text
    mov cx, PROGLINE_LEN
    call util_copy_bounded

    inc byte [prog_count]
    jmp .done

.overwrite:
    mov cx, ax
    mov ax, cx
    mov bx, PROGLINE_LEN
    mul bx
    mov di, prog_text
    add di, ax
    mov si, [token_ptr+2]
    mov cx, PROGLINE_LEN
    call util_copy_bounded

.done:
    pop di
    pop si
    pop cx
    pop bx
    pop ax
    ret

; prog_do_goto : In AX = requested target line number. Only takes
; effect while a program is RUNning; otherwise reports an error.
prog_do_goto:
    push si
    cmp byte [prog_running], 0
    jne .ok
    mov si, msg_goto_no_run
    call io_print_str
    call io_print_crlf
    jmp .done
.ok:
    mov [goto_target], ax
    mov byte [goto_requested], 1
.done:
    pop si
    ret

; cmd_goto : "GOTO <n>" as a standalone statement.
cmd_goto:
    push ax
    push si

    mov al, [token_count]
    cmp al, 2
    jae .have_arg
    jmp .synerr

.have_arg:
    mov al, 1
    call interp_get_term
    jc .synerr
    call prog_do_goto
    jmp .done

.synerr:
    mov si, msg_syntax_error
    call io_print_str
    call io_print_crlf

.done:
    pop si
    pop ax
    ret

; prog_do_gosub : In AX = requested target line number. Pushes the
; CURRENT line onto gosub_stack (so RETURN knows where to resume),
; then jumps exactly like GOTO. Only takes effect while RUNning.
prog_do_gosub:
    push ax
    push bx
    push si

    cmp byte [prog_running], 0
    jne .running
    mov si, msg_goto_no_run
    call io_print_str
    call io_print_crlf
    jmp .done

.running:
    mov bl, [gosub_sp]
    cmp bl, GOSUB_STACK_SIZE
    jb .room
    mov si, msg_gosub_full
    call io_print_str
    call io_print_crlf
    jmp .done

.room:
    mov bl, [gosub_sp]
    mov bh, 0
    shl bx, 1
    push ax
    mov ax, [current_line]
    mov [gosub_stack+bx], ax
    pop ax
    inc byte [gosub_sp]

    call prog_do_goto

.done:
    pop si
    pop bx
    pop ax
    ret

; cmd_gosub : "GOSUB <n>" as a standalone statement.
cmd_gosub:
    push ax
    push si

    mov al, [token_count]
    cmp al, 2
    jae .have_arg
    jmp .synerr

.have_arg:
    mov al, 1
    call interp_get_term
    jc .synerr
    call prog_do_gosub
    jmp .done

.synerr:
    mov si, msg_syntax_error
    call io_print_str
    call io_print_crlf

.done:
    pop si
    pop ax
    ret

; cmd_return : "RETURN" -- pop the GOSUB stack and resume just after
; the line that GOSUB'd from. Only valid while RUNning.
cmd_return:
    push ax
    push bx
    push si

    cmp byte [prog_running], 0
    jne .running
    mov si, msg_goto_no_run
    call io_print_str
    call io_print_crlf
    jmp .done

.running:
    mov al, [gosub_sp]
    cmp al, 0
    jne .have_frame
    mov si, msg_return_empty
    call io_print_str
    call io_print_crlf
    jmp .done

.have_frame:
    dec byte [gosub_sp]
    mov bl, [gosub_sp]
    mov bh, 0
    shl bx, 1
    mov bx, [gosub_stack+bx]      ; bx = the line the matching GOSUB was on

    call prog_find_next_after       ; bx -> ax = next line after it, or 0xFFFF
    cmp ax, 0xFFFF
    jne .have_next
    mov byte [prog_running], 0
    jmp .done

.have_next:
    mov [goto_target], ax
    mov byte [goto_requested], 1

.done:
    pop si
    pop bx
    pop ax
    ret

; cmd_end : "END" / "STOP" -- halts a running program early.
cmd_end:
    mov byte [prog_running], 0
    ret

; cmd_for : "FOR <var> = <start> TO <end> [STEP <step>]"  (STEP defaults to 1)
cmd_for:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    mov al, [token_count]
    mov ah, 0
    cmp ax, 6
    jae .have_min
    jmp .synerr

.have_min:
    mov al, 1
    call util_get_token             ; di -> scratch (loop variable name)
    mov al, [di]
    cmp al, '0'
    jb .name_ok
    cmp al, '9'
    jbe .synerr
.name_ok:
    mov si, scratch
    mov di, scratch2
    mov cx, VARNAME_LEN
    call util_copy_bounded            ; scratch2 = loop variable name

    mov al, [token_len+2]
    cmp al, 1
    jne .synerr
    mov si, [token_ptr+4]              ; token[2]
    mov cl, [token_len+2]
    mov ch, 0
    mov di, eq_sign
    call util_tok_eq
    cmp al, 0
    jne .eq_ok
    jmp .synerr
.eq_ok:
    mov al, 3
    call interp_get_term
    jc .synerr
    push ax                              ; save start value

    mov si, [token_ptr+8]                 ; token[4]
    mov cl, [token_len+4]
    mov ch, 0
    mov di, kw_to
    call util_tok_eq
    cmp al, 0
    jne .to_ok
    add sp, 2
    jmp .synerr
.to_ok:
    mov al, 5
    call interp_get_term
    jc .end_err
    push ax                                ; save end value

    mov al, [token_count]
    mov ah, 0
    cmp ax, 8
    jae .has_step
    mov ax, 1                                ; default step = 1
    jmp .got_step

.has_step:
    mov si, [token_ptr+12]                    ; token[6]
    mov cl, [token_len+6]
    mov ch, 0
    mov di, kw_step
    call util_tok_eq
    cmp al, 0
    jne .step_ok2
    jmp .step_err
.step_ok2:
    mov al, 7
    call interp_get_term
    jc .step_err

.got_step:
    mov dx, ax                               ; dx = step
    pop bx                                     ; bx = end
    pop ax                                       ; ax = start

    push ax
    push bx
    push dx
    mov al, [for_sp]
    cmp al, FOR_STACK_SIZE
    jb .room
    pop dx
    pop bx
    pop ax
    mov si, msg_for_full
    call io_print_str
    call io_print_crlf
    jmp .done

.room:
    pop dx
    pop bx
    pop ax
    ; ax=start, bx=end, dx=step

    push dx
    push bx
    mov dx, ax
    mov si, scratch2
    call var_assign
    pop bx
    pop dx
    ; bx=end, dx=step

    mov al, [for_sp]
    mov ah, 0
    mov cx, VARNAME_LEN
    push dx
    push bx
    mul cx
    pop bx
    pop dx
    mov di, for_var_name
    add di, ax
    mov si, scratch2
    call util_copy_bounded

    mov al, [for_sp]
    mov ah, 0
    mov di, ax
    shl di, 1
    mov [for_end+di], bx
    mov [for_step+di], dx
    mov ax, [current_line]
    mov [for_line+di], ax

    inc byte [for_sp]
    jmp .done

.step_err:
    add sp, 4
    jmp .synerr
.end_err:
    add sp, 2
.synerr:
    mov si, msg_syntax_error
    call io_print_str
    call io_print_crlf

.done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; cmd_next : "NEXT <var>" -- must name the innermost FOR's variable.
cmd_next:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    mov al, [token_count]
    cmp al, 2
    jae .have_arg
    jmp .synerr

.have_arg:
    mov al, [for_sp]
    cmp al, 0
    jne .have_frame
    mov si, msg_next_empty
    call io_print_str
    call io_print_crlf
    jmp .done

.have_frame:
    mov al, [for_sp]
    dec al
    mov ah, 0
    mov bx, VARNAME_LEN
    mul bx
    mov si, for_var_name
    add si, ax                     ; si -> the FOR-frame's variable name

    mov al, 1
    call util_get_token              ; di -> scratch (NEXT's own var name);
                                        ; si is preserved across this call
    call util_streq                     ; si(frame name) vs di(scratch)
    cmp al, 0
    jne .match
    mov si, msg_next_mismatch
    call io_print_str
    call io_print_crlf
    jmp .done

.match:
    mov al, [for_sp]
    dec al
    mov ah, 0
    mov di, ax
    shl di, 1
    mov bx, [for_end+di]
    mov dx, [for_step+di]
    push bx
    push dx

    mov al, [for_sp]
    dec al
    mov ah, 0
    mov bx, VARNAME_LEN
    mul bx
    mov di, for_var_name
    add di, ax
    mov si, di
    mov di, scratch2
    mov cx, VARNAME_LEN
    call util_copy_bounded              ; scratch2 = loop variable name

    pop dx
    pop bx
    push bx
    push dx

    mov si, scratch2
    call var_lookup_or_zero               ; ax = current value
    pop dx                                   ; dx = step
    add ax, dx                                 ; ax = new value

    push dx                                      ; step must survive var_assign too
    push ax
    mov dx, ax
    mov si, scratch2
    call var_assign
    pop ax
    pop dx
    pop bx
    ; ax=new value, dx=step, bx=end

    cmp dx, 0
    jl .counting_down
    cmp ax, bx
    jg .loop_done
    jmp .continue_loop
.counting_down:
    cmp ax, bx
    jl .loop_done

.continue_loop:
    mov al, [for_sp]
    dec al
    mov ah, 0
    mov di, ax
    shl di, 1
    mov bx, [for_line+di]        ; bx = the FOR statement's own line number
    call prog_find_next_after      ; ax = the line right after it (the loop body)
    mov [goto_target], ax
    mov byte [goto_requested], 1
    jmp .done

.loop_done:
    dec byte [for_sp]
    jmp .done

.synerr:
    mov si, msg_syntax_error
    call io_print_str
    call io_print_crlf

.done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; cmd_new : "NEW" -- clear the stored program and all variables.
cmd_new:
    push si
    mov byte [prog_count], 0
    mov byte [var_count], 0
    mov byte [gosub_sp], 0
    mov byte [for_sp], 0
    mov si, msg_new_done
    call io_print_str
    call io_print_crlf
    pop si
    ret

; cmd_plist : "PLIST" -- show the stored program in line-number order.
cmd_plist:
    push ax
    push bx
    push cx
    push dx
    push si

    mov al, [prog_count]
    cmp al, 0
    jne .have
    mov si, msg_prog_empty
    call io_print_str
    call io_print_crlf
    jmp .done

.have:
    call prog_find_min
    mov bx, ax
.loop:
    cmp bx, 0xFFFF
    je .done

    mov ax, bx
    call io_print_num
    mov dl, ' '
    call io_print_char

    call prog_find_line
    mov cx, ax
    mov ax, cx
    mov dx, PROGLINE_LEN
    mul dx
    mov si, prog_text
    add si, ax
    call io_print_str
    call io_print_crlf

    call prog_find_next_after
    mov bx, ax
    jmp .loop

.done:
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; cmd_run : execute the stored program from its lowest line number,
; following GOTO by line number, until it falls off the end, hits
; END/STOP, or exceeds the safety step limit.
cmd_run:
    push ax
    push bx
    push cx
    push si
    push di

    call prog_find_min
    cmp ax, 0xFFFF
    jne .start
    mov si, msg_prog_empty
    call io_print_str
    call io_print_crlf
    jmp .done

.start:
    mov bx, ax
    mov byte [prog_running], 1
    mov byte [goto_requested], 0
    mov word [run_steps], 0

.step:
    cmp word [run_steps], RUN_STEP_LIMIT
    jb .step_ok
    mov si, msg_too_many_steps
    call io_print_str
    call io_print_crlf
    jmp .stop
.step_ok:
    inc word [run_steps]
    mov [current_line], bx

    call prog_find_line
    cmp ax, 0xFFFF
    jne .exec
    mov si, msg_undefined_line
    call io_print_str
    call io_print_crlf
    jmp .stop

.exec:
    mov cx, ax
    mov ax, cx
    mov si, PROGLINE_LEN
    mul si
    mov si, prog_text
    add si, ax
    call lexer_tokenize

    mov al, [token_count]
    cmp al, 0
    je .advance

    call dispatch_handle

    cmp byte [prog_running], 0
    je .stop
    cmp byte [goto_requested], 0
    jne .do_goto
    jmp .advance

.do_goto:
    mov byte [goto_requested], 0
    mov bx, [goto_target]
    jmp .step

.advance:
    call prog_find_next_after
    cmp ax, 0xFFFF
    je .stop
    mov bx, ax
    jmp .step

.stop:
    mov byte [prog_running], 0
    mov byte [goto_requested], 0

.done:
    pop di
    pop si
    pop cx
    pop bx
    pop ax
    ret
