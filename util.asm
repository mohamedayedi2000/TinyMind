; =====================================================================
; TINYMIND -- util.asm : small helpers shared by every module.
; Convention: comparison routines return a plain boolean in AL (1/0),
; never rely on flags surviving a run of push/pop -- easier to get
; right by hand, and easier to read six months from now.
; =====================================================================

; util_streq : compare two NUL-terminated strings.
; In:  SI, DI -> the two strings
; Out: AL = 1 if equal, 0 if not
util_streq:
    push si
    push di
    push bx
.loop:
    mov al, [si]
    mov bl, [di]
    cmp al, bl
    jne .no
    cmp al, 0
    je .yes
    inc si
    inc di
    jmp .loop
.yes:
    mov al, 1
    jmp .done
.no:
    mov al, 0
.done:
    pop bx
    pop di
    pop si
    ret

; util_tok_eq : compare a length-bounded token to a NUL-terminated word.
; In:  SI = token start, CX = token length, DI -> word to compare to
; Out: AL = 1 if equal, 0 if not. SI, CX, DI unchanged.
util_tok_eq:
    push si
    push di
    push cx
    push bx
.loop:
    jcxz .tail
    mov bl, [di]
    cmp bl, 0
    je .no              ; word ended before token did
    mov al, [si]
    cmp al, bl
    jne .no
    inc si
    inc di
    dec cx
    jmp .loop
.tail:
    cmp byte [di], 0     ; token ended; word must end here too
    jne .no
    mov al, 1
    jmp .done
.no:
    mov al, 0
.done:
    pop bx
    pop cx
    pop di
    pop si
    ret

; util_get_token : copy token #AL (0-based) into `scratch`, NUL-terminated,
; truncated to SCRATCH_LEN-1 chars if necessary.
; In:  AL = token index (caller ensures it is < token_count)
; Out: DI -> scratch
util_get_token:
    push ax
    push bx
    push cx
    push si

    mov ah, 0
    mov bx, ax
    mov cl, [token_len+bx]
    mov ch, 0
    cmp cx, SCRATCH_LEN-1
    jbe .lenok
    mov cx, SCRATCH_LEN-1
.lenok:
    shl bx, 1
    mov si, [token_ptr+bx]

    mov di, scratch
.copy:
    jcxz .term
    mov al, [si]
    mov [di], al
    inc si
    inc di
    dec cx
    jmp .copy
.term:
    mov byte [di], 0
    mov di, scratch

    pop si
    pop cx
    pop bx
    pop ax
    ret

; util_atoi : parse a decimal number (optionally negative) from a
; NUL-terminated string.
; In:  SI -> numeral string
; Out: AX = value, CF = 1 if no digits were found at all (error)
util_atoi:
    push bx
    push cx
    push dx
    push si

    xor ax, ax
    xor cx, cx
    mov dl, 0                 ; dl = 1 if we saw a leading '-'
    cmp byte [si], '-'
    jne .digits
    mov dl, 1
    inc si
.digits:
.loop:
    mov bl, [si]
    cmp bl, '0'
    jb .done
    cmp bl, '9'
    ja .done
    sub bl, '0'
    xor bh, bh
    push bx
    push dx
    mov dx, 10
    mul dx              ; dx:ax = ax*10 (dx discarded, we only keep 16 bits)
    pop dx
    pop bx
    add ax, bx
    inc cx
    inc si
    jmp .loop
.done:
    cmp cx, 0
    jne .ok
    stc
    jmp .ret
.ok:
    cmp dl, 0
    je .clc
    neg ax
.clc:
    clc
.ret:
    pop si
    pop dx
    pop cx
    pop bx
    ret

; util_copy_bounded : copy a NUL-terminated string at SI into the DI
; slot, up to CX-1 bytes, always NUL-terminating within the CX-byte
; slot. Used everywhere a name/word/response has to fit a fixed slot
; (chatbot patterns, facts, rules, variables, Markov words).
; In: SI = source, DI = dest, CX = slot size including the terminator.
util_copy_bounded:
    push ax
    push cx
    dec cx
.loop:
    jcxz .term
    mov al, [si]
    cmp al, 0
    je .term
    mov [di], al
    inc si
    inc di
    dec cx
    jmp .loop
.term:
    mov byte [di], 0
    pop cx
    pop ax
    ret

; util_tok_first_is_digit : does token #AL start with '0'-'9'?
; In:  AL = token index
; Out: AL = 1/0. SI, CX untouched (BX used as scratch only).
util_tok_first_is_digit:
    push bx
    push si

    mov ah, 0
    mov bx, ax
    shl bx, 1
    mov si, [token_ptr+bx]
    mov al, [si]
    cmp al, '0'
    jb .no
    cmp al, '9'
    ja .no
    mov al, 1
    jmp .done
.no:
    mov al, 0
.done:
    pop si
    pop bx
    ret
