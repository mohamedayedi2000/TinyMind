; =====================================================================
; TINYMIND -- chatbot.asm (v3)
; Tiers of "understanding", tried in order, plus live learning that
; runs no matter which tier answers:
;   1. Best keyword-pattern match. A pattern may need ONE keyword
;      (TEACH WORD reply) or TWO together (TEACH WORD1+WORD2 reply);
;      a fully-satisfied two-keyword pattern always beats a one-keyword
;      one, and ties are broken by preferring the more recently taught.
;   2. ELIZA-style reflection: if the line contains any word that has a
;      reflection (see reflect_table -- the trigger check reads that
;      same table, so there's only one vocabulary to maintain).
;   3. A Markov-generated sentence, once enough has been learned.
;   4. A static fallback, if nothing else applies yet.
; Every conversational line (whichever tier answers it) is fed to
; mk_learn, so tier 3 keeps getting richer the more you talk to it.
; =====================================================================

MK_FALLBACK_THRESHOLD equ 20   ; need at least this many learned pairs
                                 ; before Markov generation is used as a
                                 ; fallback (still usable earlier via THINK).
                                 ; Higher than it looks like it needs to be:
                                 ; every learned line now contributes two
                                 ; "free" boundary pairs (see markov.asm),
                                 ; so this crosses faster than a raw word
                                 ; count would suggest.

chat_seed_count equ 6

; Built-in patterns are all single-keyword: chat_seed_pat2 is empty for
; every one of them (an empty string means "no second keyword needed").
chat_seed_pat1:
.p0: db "HELLO",0
     times PATTERN_LEN-($-.p0) db 0
.p1: db "NAME",0
     times PATTERN_LEN-($-.p1) db 0
.p2: db "HOW",0
     times PATTERN_LEN-($-.p2) db 0
.p3: db "BYE",0
     times PATTERN_LEN-($-.p3) db 0
.p4: db "THANK",0
     times PATTERN_LEN-($-.p4) db 0
.p5: db "SORRY",0
     times PATTERN_LEN-($-.p5) db 0

chat_seed_resp:
.r0: db "Hello! I'm TINYMIND, running on an 8086. Type HELP for commands.",0
     times RESPONSE_LEN-($-.r0) db 0
.r1: db "I'm TINYMIND -- a small pattern-matching program, not really a mind.",0
     times RESPONSE_LEN-($-.r1) db 0
.r2: db "Running fine, thank you. How can I help?",0
     times RESPONSE_LEN-($-.r2) db 0
.r3: db "Goodbye for now.",0
     times RESPONSE_LEN-($-.r3) db 0
.r4: db "You're welcome.",0
     times RESPONSE_LEN-($-.r4) db 0
.r5: db "No need to apologise.",0
     times RESPONSE_LEN-($-.r5) db 0

chat_fallback:      db "I see. Tell me more.",13,10,0
msg_teach_usage:    db "Usage: TEACH <keyword>[+<keyword2>] <response text...>",0
msg_pattern_full:   db "Pattern table is full.",0
msg_learned:        db "OK, learned it.",0
msg_think_empty:    db "I haven't learned enough yet -- talk to me some more first.",0

; ---- ELIZA-style reflection. This table is the ONLY vocabulary list --
; both the trigger check and the word-by-word rewrite read it, so
; extending reflection is always exactly one place. ----
word_I:        db "I",0
word_ME:       db "ME",0
word_MY:       db "MY",0
word_MYSELF:   db "MYSELF",0
word_MINE:     db "MINE",0
word_AM:       db "AM",0
word_WAS:      db "WAS",0
word_YOU:      db "YOU",0
word_YOUR:     db "YOUR",0
word_YOURSELF: db "YOURSELF",0
word_YOURS:    db "YOURS",0
word_ARE:      db "ARE",0
word_WERE:     db "WERE",0

reflect_table:
    dw word_I,        word_YOU
    dw word_ME,       word_YOU
    dw word_MY,       word_YOUR
    dw word_MYSELF,   word_YOURSELF
    dw word_MINE,     word_YOURS
    dw word_AM,       word_ARE
    dw word_WAS,      word_WERE
    dw word_YOU,      word_I
    dw word_YOUR,     word_MY
    dw word_YOURSELF, word_MYSELF
    dw word_YOURS,    word_MINE
    dw word_ARE,      word_AM
    dw word_WERE,     word_WAS
    dw 0, 0

tmpl0a: db "Why do you say that ",0
tmpl0b: db "?",13,10,0
tmpl1a: db "Tell me more about why ",0
tmpl1b: db ".",13,10,0
tmpl2a: db "How does it make you feel that ",0
tmpl2b: db "?",13,10,0

; reflect_lookup : does word (SI, NUL-terminated) have a reflection?
; Out: DI -> the reflected word if found, or SI itself if not (so the
; caller can always just copy from DI either way).
reflect_lookup:
    push ax
    push si
    push bx

    mov bx, reflect_table
.loop:
    mov di, [bx]
    cmp di, 0
    je .none
    call util_streq
    cmp al, 0
    jne .found
    add bx, 4
    jmp .loop
.found:
    mov di, [bx+2]
    jmp .done
.none:
    mov di, si
.done:
    pop bx
    pop si
    pop ax
    ret

; reflect_build : word-by-word reflected copy of the WHOLE current line
; into reflect_buf.
reflect_build:
    push ax
    push cx
    push si
    push di
    push bp

    mov di, reflect_buf
    xor bp, bp
.loop:
    mov al, [token_count]
    mov ah, 0
    cmp bp, ax
    jae .finish

    push di

    mov ax, bp
    call util_get_token           ; di -> scratch (this token's text)
    mov si, scratch
    call reflect_lookup             ; di -> reflected word (or original)
    mov si, di
    mov di, scratch2
    mov cx, SCRATCH_LEN
    call util_copy_bounded            ; scratch2 = the reflected word, safe copy

    pop di

    cmp bp, 0
    je .no_space
    mov byte [di], ' '
    inc di
.no_space:
    mov si, scratch2
    mov cx, SCRATCH_LEN
    call util_copy_bounded

    inc bp
    jmp .loop

.finish:
    pop bp
    pop di
    pop si
    pop cx
    pop ax
    ret

; chat_has_reflect_trigger : does any token in the current line appear
; as a key (or target) in reflect_table? Out: AL = 1/0.
chat_has_reflect_trigger:
    push bx
    push cx
    push si
    push di
    push bp

    xor bp, bp
.loop:
    mov al, [token_count]
    mov ah, 0
    cmp bp, ax
    jae .no

    mov bx, bp
    shl bx, 1
    mov si, [token_ptr+bx]
    mov bx, bp
    mov cl, [token_len+bx]
    mov ch, 0

    mov bx, reflect_table
.tbl_loop:
    mov di, [bx]
    cmp di, 0
    je .tbl_done
    call util_tok_eq
    cmp al, 0
    jne .yes
    add bx, 4
    jmp .tbl_loop
.tbl_done:

    inc bp
    jmp .loop

.yes:
    mov al, 1
    jmp .done
.no:
    mov al, 0
.done:
    pop bp
    pop di
    pop si
    pop cx
    pop bx
    ret

; chat_reflect_respond : builds and prints a reflective response.
chat_reflect_respond:
    push ax
    push cx
    push si

    call reflect_build

    mov cx, 3
    call rng_range
    cmp ax, 0
    je .t0
    cmp ax, 1
    je .t1

    mov si, tmpl2a
    call io_print_str
    mov si, reflect_buf
    call io_print_str
    mov si, tmpl2b
    call io_print_str
    jmp .done
.t0:
    mov si, tmpl0a
    call io_print_str
    mov si, reflect_buf
    call io_print_str
    mov si, tmpl0b
    call io_print_str
    jmp .done
.t1:
    mov si, tmpl1a
    call io_print_str
    mov si, reflect_buf
    call io_print_str
    mov si, tmpl1b
    call io_print_str

.done:
    pop si
    pop cx
    pop ax
    ret

; chat_token_matches : does ANY token in the current line match the
; NUL-terminated keyword at DI? DI is never modified, so no save/restore
; of it is needed.
chat_token_matches:
    push bx
    push cx
    push si
    push bp

    xor bp, bp
.loop:
    mov al, [token_count]
    mov ah, 0
    cmp bp, ax
    jae .no

    mov bx, bp
    shl bx, 1
    mov si, [token_ptr+bx]
    mov bx, bp
    mov cl, [token_len+bx]
    mov ch, 0

    call util_tok_eq
    cmp al, 0
    jne .yes

    inc bp
    jmp .loop

.yes:
    mov al, 1
    jmp .done
.no:
    mov al, 0
.done:
    pop bp
    pop si
    pop cx
    pop bx
    ret

; chat_find_best_pattern : score every known pattern against the
; current line. A pattern with a second keyword only counts as a match
; if BOTH keywords are found (somewhere in the line, not necessarily
; adjacent); such a pattern scores 2, a single-keyword match scores 1.
; Highest score wins; ties go to the more recently taught (higher index).
; Out: AX = best pattern index, or 0xFFFF if nothing matched at all.
chat_find_best_pattern:
    push bx
    push cx
    push dx
    push di
    push bp

    mov word [best_pat_idx], 0xFFFF
    mov word [best_pat_score], 0

    xor bp, bp
.loop:
    mov al, [chat_count]
    mov ah, 0
    cmp bp, ax
    jae .done

    mov ax, bp
    mov dx, PATTERN_LEN
    mul dx
    mov di, chat_pat1
    add di, ax
    call chat_token_matches
    cmp al, 0
    je .next

    mov ax, bp
    mov dx, PATTERN_LEN
    mul dx
    mov di, chat_pat2
    add di, ax
    cmp byte [di], 0
    je .score1

    call chat_token_matches
    cmp al, 0
    je .next
    mov dx, 2
    jmp .have_score
.score1:
    mov dx, 1
.have_score:
    cmp dx, [best_pat_score]
    jl .next
    jg .take
    cmp bp, [best_pat_idx]
    jbe .next
.take:
    mov [best_pat_score], dx
    mov [best_pat_idx], bp

.next:
    inc bp
    jmp .loop

.done:
    mov ax, [best_pat_idx]

    pop bp
    pop di
    pop dx
    pop cx
    pop bx
    ret

; chatbot_handle : the conversational fallback for anything that isn't
; a recognised command. Learns from the line first, then tries (in
; order) a keyword pattern, ELIZA-style reflection, Markov generation,
; and finally the static default.
chatbot_handle:
    push ax
    push bx
    push dx
    push si

    call mk_learn

    call chat_find_best_pattern
    cmp ax, 0xFFFF
    je .no_pattern

    mov bx, ax
    mov dx, RESPONSE_LEN
    mul dx
    mov si, chat_resp
    add si, ax
    call io_print_str
    call io_print_crlf
    jmp .done

.no_pattern:
    call chat_has_reflect_trigger
    cmp al, 0
    je .no_reflect
    call chat_reflect_respond
    jmp .done

.no_reflect:
    mov al, [mk_count_n]
    cmp al, MK_FALLBACK_THRESHOLD
    jb .default

    call mk_generate
    jc .default
    mov si, gen_buf
    call io_print_str
    call io_print_crlf
    jmp .done

.default:
    mov si, chat_fallback
    call io_print_str

.done:
    pop si
    pop dx
    pop bx
    pop ax
    ret

; chatbot_think : "THINK" -- explicitly generate a Markov sentence,
; regardless of the fallback threshold above (the person asked for it
; directly, so even a short/rough result is a fair answer).
chatbot_think:
    push ax
    push si

    call mk_generate
    jc .empty
    mov si, gen_buf
    call io_print_str
    call io_print_crlf
    jmp .done
.empty:
    mov si, msg_think_empty
    call io_print_str
    call io_print_crlf
.done:
    pop si
    pop ax
    ret

; chat_find_plus : SI -> NUL-terminated text. Out: AX = offset of the
; first '+' found, or 0xFFFF if none.
chat_find_plus:
    push si
    push cx
    xor cx, cx
.loop:
    mov al, [si]
    cmp al, 0
    je .none
    cmp al, '+'
    je .found
    inc si
    inc cx
    jmp .loop
.found:
    mov ax, cx
    jmp .done
.none:
    mov ax, 0xFFFF
.done:
    pop cx
    pop si
    ret

; chatbot_teach : "TEACH <keyword>[+<keyword2>] <response text...>"
; token[1] = keyword (optionally "WORD1+WORD2"), token[2..end of line] =
; response (read straight from the untouched original line).
chatbot_teach:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    mov al, [token_count]
    cmp al, 3
    jae .have_args
    mov si, msg_teach_usage
    call io_print_str
    call io_print_crlf
    jmp .done

.have_args:
    mov al, [chat_count]
    cmp al, MAX_PATTERNS
    jb .room
    mov si, msg_pattern_full
    call io_print_str
    call io_print_crlf
    jmp .done

.room:
    mov al, 1
    call util_get_token             ; di -> scratch (the keyword token)
    mov si, di
    call chat_find_plus               ; ax = '+' offset within it, or 0xFFFF

    cmp ax, 0xFFFF
    je .single_keyword

    ; split scratch in place: the '+' becomes a NUL, so scratch is now
    ; word1 (NUL-terminated) followed immediately by word2's own text.
    mov bx, ax
    mov byte [scratch+bx], 0
    inc bx                              ; bx = offset of word2 within scratch

    mov al, [chat_count]
    mov ah, 0
    push bx
    mov dx, PATTERN_LEN
    mul dx
    mov di, chat_pat1
    add di, ax
    mov si, scratch
    mov cx, PATTERN_LEN
    call util_copy_bounded
    pop bx

    mov al, [chat_count]
    mov ah, 0
    mov dx, PATTERN_LEN
    mul dx
    mov di, chat_pat2
    add di, ax
    mov si, scratch
    add si, bx
    mov cx, PATTERN_LEN
    call util_copy_bounded
    jmp .have_keywords

.single_keyword:
    mov al, [chat_count]
    mov ah, 0
    mov dx, PATTERN_LEN
    mul dx
    mov di, chat_pat1
    add di, ax
    mov si, scratch
    mov cx, PATTERN_LEN
    call util_copy_bounded

    mov al, [chat_count]
    mov ah, 0
    mov dx, PATTERN_LEN
    mul dx
    mov di, chat_pat2
    add di, ax
    mov byte [di], 0

.have_keywords:
    mov bx, 2
    shl bx, 1
    mov si, [token_ptr+bx]

    mov al, [chat_count]
    mov ah, 0
    mov dx, RESPONSE_LEN
    mul dx
    mov di, chat_resp
    add di, ax
    mov cx, RESPONSE_LEN
    call util_copy_bounded

    inc byte [chat_count]

    mov si, msg_learned
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
