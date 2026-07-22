; =====================================================================
; TINYMIND -- lexer.asm
; Splits a line into up to MAX_TOKENS whitespace-separated tokens
; WITHOUT modifying the original line. Each token is recorded as
; (start offset, length) rather than being NUL-chopped in place, so
; "everything from token N to the end of the line" is still a single,
; valid, space-intact string -- which TEACH relies on.
; =====================================================================

; lexer_tokenize : SI -> NUL-terminated line (already upper-cased).
; Fills token_ptr[i]/token_len[i] for i = 0..token_count-1.
lexer_tokenize:
    push ax
    push si
    push di
    push bp
    push cx
    push dx

    xor dx, dx              ; dx = token count so far
    mov di, token_ptr
    mov bp, token_len

.skip_spaces:
    mov al, [si]
    cmp al, 0
    je .finish
    cmp al, ' '
    jne .start_token
    inc si
    jmp .skip_spaces

.start_token:
    cmp dx, MAX_TOKENS
    jae .swallow_rest        ; already have enough tokens; ignore the rest

    mov [di], si             ; record this token's start address
    xor cx, cx                ; length counter

.measure:
    mov al, [si]
    cmp al, 0
    je .end_token
    cmp al, ' '
    je .end_token
    inc si
    inc cx
    jmp .measure

.end_token:
    mov [bp], cl
    add di, 2
    inc bp
    inc dx
    jmp .skip_spaces

.swallow_rest:
    mov al, [si]
    cmp al, 0
    je .finish
    inc si
    jmp .swallow_rest

.finish:
    mov [token_count], dl

    pop dx
    pop cx
    pop bp
    pop di
    pop si
    pop ax
    ret
