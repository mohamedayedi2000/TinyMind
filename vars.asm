; =====================================================================
; TINYMIND -- vars.asm
; The interpreter's variable symbol table: any identifier (a token that
; doesn't start with a digit) can be a variable name now, not just a
; single letter. Plain linear scan by name -- MAX_VARS is small enough
; (40) that this is plenty fast for an interactive toy.
; =====================================================================

; var_find : is the NUL-terminated name at SI already known?
; SI preserved. Out: AX = index, or 0xFFFF if not found.
var_find:
    push bx
    push si
    push di
    push dx
    push bp

    xor bp, bp
.loop:
    mov al, [var_count]
    mov ah, 0
    cmp bp, ax
    jae .notfound

    mov ax, bp
    mov bx, VARNAME_LEN
    mul bx
    mov di, var_names
    add di, ax

    call util_streq
    cmp al, 0
    jne .found

    inc bp
    jmp .loop

.found:
    mov ax, bp
    jmp .done
.notfound:
    mov ax, 0xFFFF
.done:
    pop bp
    pop dx
    pop di
    pop si
    pop bx
    ret

; var_lookup_or_zero : In: SI = name. Out: AX = its value, or 0 if unknown.
var_lookup_or_zero:
    push bx
    push si

    call var_find
    cmp ax, 0xFFFF
    jne .have
    xor ax, ax
    jmp .done
.have:
    mov bx, ax
    shl bx, 1
    mov ax, [var_values+bx]
.done:
    pop si
    pop bx
    ret

; var_assign : In: SI = name, DX = value to store.
; Creates the variable if it doesn't exist yet (when there's room).
; Out: CF = 1 if it needed to create a new one and the table was full
; (the assignment did not happen); CF = 0 otherwise.
var_assign:
    push ax
    push bx
    push si
    push di

    call var_find
    cmp ax, 0xFFFF
    jne .update

    mov al, [var_count]
    cmp al, MAX_VARS
    jb .create
    stc
    jmp .done

.create:
    push dx
    mov al, [var_count]
    mov ah, 0
    mov bx, VARNAME_LEN
    mul bx
    mov di, var_names
    add di, ax
    mov cx, VARNAME_LEN
    call util_copy_bounded
    pop dx

    mov bl, [var_count]
    mov bh, 0
    shl bx, 1
    mov [var_values+bx], dx

    inc byte [var_count]
    clc
    jmp .done

.update:
    mov bx, ax
    shl bx, 1
    mov [var_values+bx], dx
    clc

.done:
    pop di
    pop si
    pop bx
    pop ax
    ret
