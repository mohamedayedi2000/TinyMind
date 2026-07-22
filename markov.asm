; =====================================================================
; TINYMIND -- markov.asm
; A real, working statistical language model: as you talk to it, it
; records which word followed which (a first-order Markov chain over
; whole words, with observed-frequency counts), and can generate new,
; original sentences by weighted-random-walking that chain. This is
; genuine "learning" in the statistical sense -- not a canned response
; table -- and it gets more varied and more coherent the more it's used.
; Persisted (see storage.asm) so the model keeps growing across
; sessions rather than starting from nothing every time.
;
; Sentence boundaries share the exact same (word1, word2, count) table:
; mk_boundary_start/mk_boundary_end are single-byte "words" a person can
; never actually type (0x01/0x02), so learning "<START> firstword" and
; "lastword <END>" for every line costs no new data structure. Generation
; then asks mk_next_word(<START>) for a properly weighted, genuinely
; observed sentence-opener instead of an arbitrary random entry, and
; stops the moment <END> is the weighted pick rather than always running
; to MK_GEN_MAXWORDS.
; =====================================================================

mk_boundary_start: db 1, 0
mk_boundary_end:    db 2, 0

; mk_find_pair : is (word1 at SI, word2 at DI) already a known pair?
; Out: AX = index, or 0xFFFF if not found.
mk_find_pair:
    push bx
    push cx
    push dx
    push si
    push di
    push bp

    mov bp, di              ; bp = word2 ; si keeps word1 throughout

    xor cx, cx
.loop:
    mov al, [mk_count_n]
    mov ah, 0
    cmp cx, ax
    jae .notfound

    mov ax, cx
    mov bx, MKWORD_LEN
    mul bx
    mov di, mk_word1
    add di, ax
    call util_streq          ; si(word1) vs di(mk_word1[cx])
    cmp al, 0
    je .next

    mov ax, cx
    mov bx, MKWORD_LEN
    mul bx
    mov di, mk_word2
    add di, ax
    push si
    mov si, bp
    call util_streq           ; si(word2) vs di(mk_word2[cx])
    pop si
    cmp al, 0
    jne .found

.next:
    inc cx
    jmp .loop

.found:
    mov ax, cx
    jmp .done
.notfound:
    mov ax, 0xFFFF
.done:
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    ret

; mk_learn_pair : record that word2 (DI) followed word1 (SI) once more.
; Creates the pair if new (when there's room); otherwise increments its
; count, saturating at 255. A full table is a silent no-op -- missing
; one rare transition isn't worth an error message.
mk_learn_pair:
    push ax
    push bx
    push cx
    push si
    push di
    push bp

    mov bp, di

    call mk_find_pair
    cmp ax, 0xFFFF
    jne .bump

    mov al, [mk_count_n]
    cmp al, MAX_MK
    jb .create
    jmp .done

.create:
    mov al, [mk_count_n]
    mov ah, 0
    mov bx, MKWORD_LEN
    mul bx
    mov di, mk_word1
    add di, ax
    mov cx, MKWORD_LEN
    call util_copy_bounded

    mov si, bp
    mov al, [mk_count_n]
    mov ah, 0
    mov bx, MKWORD_LEN
    mul bx
    mov di, mk_word2
    add di, ax
    mov cx, MKWORD_LEN
    call util_copy_bounded

    mov bl, [mk_count_n]
    mov bh, 0
    mov byte [mk_count+bx], 1
    inc byte [mk_count_n]
    jmp .done

.bump:
    mov bx, ax
    cmp byte [mk_count+bx], 255
    jae .done
    inc byte [mk_count+bx]

.done:
    pop bp
    pop di
    pop si
    pop cx
    pop bx
    pop ax
    ret

; mk_learn : learn every consecutive word-pair in the current tokenized
; line (token_ptr/token_len/token_count). No-op on a 0- or 1-word line.
mk_learn:
    push ax
    push cx
    push si
    push di
    push bp

    mov al, [token_count]
    cmp al, 0
    je .done

    ; learn (<START>, token[0]) -- what legitimately opens a sentence
    mov al, 0
    call util_get_token             ; di -> scratch (token[0]'s text)
    mov si, mk_boundary_start
    call mk_learn_pair

    ; learn (token[last], <END>) -- what legitimately closes one
    mov al, [token_count]
    dec al
    call util_get_token               ; di -> scratch (last token's text)
    mov si, di
    mov di, mk_boundary_end
    call mk_learn_pair

    mov al, [token_count]
    cmp al, 2
    jb .done

    mov al, [token_count]
    mov ah, 0
    dec ax
    mov bp, ax                ; bp = number of pairs to learn

    xor cx, cx
.loop:
    cmp cx, bp
    jae .done

    mov al, cl
    call util_get_token         ; di -> scratch (word1)
    mov si, scratch
    mov di, scratch2
    push cx
    mov cx, SCRATCH_LEN
    call util_copy_bounded
    pop cx

    mov al, cl
    inc al
    call util_get_token          ; di -> scratch (word2)

    mov si, scratch2
    mov di, scratch
    call mk_learn_pair

    inc cx
    jmp .loop

.done:
    pop bp
    pop di
    pop si
    pop cx
    pop ax
    ret

; mk_next_word : given the current word (SI, NUL-terminated), pick a
; weighted-random word that has actually followed it before -- more
; frequently observed transitions are proportionally more likely.
; Out: CF = 1 if no continuation is known; CF = 0 and DI -> the chosen
; word2 (read-only, inside mk_word2[]) otherwise.
mk_next_word:
    push ax
    push bx
    push cx
    push si
    push bp

    mov bp, si

    mov word [mk_sum], 0
    xor cx, cx
.p1_loop:
    mov al, [mk_count_n]
    mov ah, 0
    cmp cx, ax
    jae .p1_done

    mov ax, cx
    mov bx, MKWORD_LEN
    mul bx
    mov di, mk_word1
    add di, ax
    mov si, bp
    call util_streq
    cmp al, 0
    je .p1_next

    mov bx, cx
    mov al, [mk_count+bx]
    mov ah, 0
    add [mk_sum], ax

.p1_next:
    inc cx
    jmp .p1_loop
.p1_done:

    cmp word [mk_sum], 0
    jne .have_weight
    stc
    jmp .done

.have_weight:
    mov cx, [mk_sum]
    call rng_range
    mov [mk_pick], ax

    xor cx, cx
.p2_loop:
    mov al, [mk_count_n]
    mov ah, 0
    cmp cx, ax
    jae .p2_none

    mov ax, cx
    mov bx, MKWORD_LEN
    mul bx
    mov di, mk_word1
    add di, ax
    mov si, bp
    call util_streq
    cmp al, 0
    je .p2_next

    mov bx, cx
    mov al, [mk_count+bx]
    mov ah, 0
    cmp ax, [mk_pick]
    ja .p2_found
    sub [mk_pick], ax

.p2_next:
    inc cx
    jmp .p2_loop

.p2_found:
    mov ax, cx
    mov bx, MKWORD_LEN
    mul bx
    mov di, mk_word2
    add di, ax
    clc
    jmp .done

.p2_none:
    stc

.done:
    pop bp
    pop si
    pop cx
    pop bx
    pop ax
    ret

; mk_generate : build one Markov-generated sentence into gen_buf.
; Out: CF = 1 if nothing has been learned yet (mk_count_n == 0);
;      CF = 0 and gen_buf holds a NUL-terminated sentence otherwise.
mk_generate:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp

    mov al, [mk_count_n]
    cmp al, 0
    jne .have_data
    stc
    jmp .done

.have_data:
    mov si, mk_boundary_start
    call mk_next_word                  ; di -> a weighted-random real sentence-opener
    jnc .got_start

    ; fallback (shouldn't normally trigger): no <START> data yet, so
    ; just pick any random entry's word1.
    mov al, [mk_count_n]
    mov ah, 0
    mov cx, ax
    call rng_range
    mov bx, MKWORD_LEN
    mul bx
    mov di, mk_word1
    add di, ax

.got_start:
    mov si, di
    mov di, gen_buf
    mov cx, MKWORD_LEN
    call util_copy_bounded
    mov bx, di                  ; bx = write position in gen_buf

    mov si, gen_buf
    mov di, scratch2
    mov cx, MKWORD_LEN
    call util_copy_bounded        ; scratch2 = current word

    mov bp, 0
.gen_loop:
    cmp bp, MK_GEN_MAXWORDS
    jae .finish

    mov si, scratch2
    call mk_next_word
    jc .finish

    ; stop (without appending) if the weighted pick was the end marker --
    ; a real, learned "this is a plausible place to stop" signal.
    mov si, mk_boundary_end
    call util_streq
    cmp al, 0
    jne .finish

    mov si, di
    mov di, scratch
    mov cx, MKWORD_LEN
    call util_copy_bounded

    mov byte [bx], ' '
    inc bx
    mov si, scratch
    mov di, bx
    mov cx, MKWORD_LEN
    call util_copy_bounded
    mov bx, di

    mov si, scratch
    mov di, scratch2
    mov cx, MKWORD_LEN
    call util_copy_bounded

    inc bp
    jmp .gen_loop

.finish:
    clc

.done:
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret
