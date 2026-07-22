; =====================================================================
; TINYMIND -- io.asm : console I/O primitives, the only place that
; talks to INT 21h for reading/printing. Every routine preserves every
; register it doesn't use to return a value.
; =====================================================================

; io_print_str : DS:SI -> NUL-terminated string. Prints it.
io_print_str:
    push ax
    push dx
    push si
.next:
    mov al, [si]
    cmp al, 0
    je .done
    mov dl, al
    mov ah, 0x02
    int 0x21
    inc si
    jmp .next
.done:
    pop si
    pop dx
    pop ax
    ret

; io_print_char : DL = character to print.
io_print_char:
    push ax
    push dx
    mov ah, 0x02
    int 0x21
    pop dx
    pop ax
    ret

; io_print_crlf : prints CR LF.
io_print_crlf:
    push dx
    mov dl, 13
    call io_print_char
    mov dl, 10
    call io_print_char
    pop dx
    ret

; io_read_line : reads one line from the keyboard into input_buf,
; NUL-terminates it in place of the CR, and folds it to upper case.
; Out: SI -> the line (input_buf+2).
io_read_line:
    push ax
    push bx
    push cx

    mov byte [input_buf], INPUT_MAX
    mov dx, input_buf
    mov ah, 0x0a
    int 0x21

    xor cx, cx
    mov cl, [input_buf+1]
    mov bx, input_buf+2
    add bx, cx
    mov byte [bx], 0        ; NUL where DOS left the CR
    mov bx, input_buf+2

    mov si, bx
.upcase:
    mov al, [si]
    cmp al, 0
    je .done
    cmp al, 'a'
    jb .next
    cmp al, 'z'
    ja .next
    sub al, 32
    mov [si], al
.next:
    inc si
    jmp .upcase
.done:
    mov si, bx

    pop cx
    pop bx
    pop ax
    ret

; io_print_num : prints AX as a signed decimal number.
io_print_num:
    push ax
    push bx
    push cx
    push dx

    test ax, ax
    jns .positive
    push ax
    mov dl, '-'
    call io_print_char
    pop ax
    neg ax
.positive:

    mov cx, 0
    mov bx, 10
.conv:
    xor dx, dx
    div bx              ; ax = ax/10, dx = remainder digit
    push dx
    inc cx
    test ax, ax
    jnz .conv
.print:
    pop dx
    add dl, '0'
    call io_print_char
    loop .print

    pop dx
    pop cx
    pop bx
    pop ax
    ret

; io_write_block : BX = file handle, DX = buffer, CX = byte count.
; Out: CF = 1 on error, or if fewer bytes were written than requested.
io_write_block:
    push ax
    push cx
    mov ah, 0x40
    push cx
    int 0x21
    pop cx
    jc .err
    cmp ax, cx
    jne .err
    clc
    jmp .done
.err:
    stc
.done:
    pop cx
    pop ax
    ret

; io_read_block : BX = file handle, DX = buffer, CX = byte count.
; Out: CF = 1 on error, or if fewer bytes were read than requested
; (a short/corrupt/old-format save file is treated as an error, not
; silently accepted with whatever partial data happened to load).
io_read_block:
    push ax
    push cx
    mov ah, 0x3f
    push cx
    int 0x21
    pop cx
    jc .err
    cmp ax, cx
    jne .err
    clc
    jmp .done
.err:
    stc
.done:
    pop cx
    pop ax
    ret
