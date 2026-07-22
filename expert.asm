; =====================================================================
; TINYMIND -- expert.asm
; A tiny propositional expert system: FACT asserts a fact, RULE adds an
; "a AND b => c" inference rule (use "-" for b when only one antecedent
; is needed), ASK runs forward chaining and reports whether a goal is
; derivable, LIST shows everything currently known.
; =====================================================================

wildcard_dash:      db "-",0
msg_fact_usage:      db "Usage: FACT <name>",0
msg_rule_usage:      db "Usage: RULE <a> <b> <c>  (use - for b if only one antecedent)",0
msg_ask_usage:       db "Usage: ASK <name>",0
msg_already_known:   db "Already known.",0
msg_fact_full:       db "Fact table is full.",0
msg_rule_full:       db "Rule table is full.",0
msg_yes:             db "YES",0
msg_no:              db "NO",0
msg_no_facts:        db "No facts yet.",0
msg_ok:              db "OK.",0

; fact_find : is the NUL-terminated name at SI already in facts[]?
; SI preserved. Out: AX = index, or 0xFFFF if not found.
fact_find:
    push bx
    push si
    push di
    push dx
    push bp

    xor bp, bp
.loop:
    mov al, [fact_count]
    mov ah, 0
    cmp bp, ax
    jae .notfound

    mov ax, bp
    mov bx, FACT_LEN
    mul bx
    mov di, facts
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

; fact_add : "FACT <name>"
fact_add:
    push ax
    push bx
    push cx
    push si
    push di

    mov al, [token_count]
    cmp al, 2
    jae .have_arg
    mov si, msg_fact_usage
    call io_print_str
    call io_print_crlf
    jmp .done

.have_arg:
    mov al, 1
    call util_get_token
    mov si, di

    call fact_find
    cmp ax, 0xFFFF
    je .new
    mov si, msg_already_known
    call io_print_str
    call io_print_crlf
    jmp .done

.new:
    mov al, [fact_count]
    cmp al, MAX_FACTS
    jb .room
    mov si, msg_fact_full
    call io_print_str
    call io_print_crlf
    jmp .done

.room:
    mov al, [fact_count]
    mov ah, 0
    mov bx, FACT_LEN
    mul bx
    mov di, facts
    add di, ax

    mov si, scratch
    mov cx, FACT_LEN
    call util_copy_bounded

    inc byte [fact_count]
    mov si, msg_ok
    call io_print_str
    call io_print_crlf

.done:
    pop di
    pop si
    pop cx
    pop bx
    pop ax
    ret

; rule_add : "RULE <a> <b> <c>"  meaning a AND b => c ("-" for b to skip it)
rule_add:
    push ax
    push bx
    push cx
    push si
    push di

    mov al, [token_count]
    cmp al, 4
    jae .have_args
    mov si, msg_rule_usage
    call io_print_str
    call io_print_crlf
    jmp .done

.have_args:
    mov al, [rule_count]
    cmp al, MAX_RULES
    jb .room
    mov si, msg_rule_full
    call io_print_str
    call io_print_crlf
    jmp .done

.room:
    mov al, [rule_count]
    mov ah, 0
    mov bx, FACT_LEN
    mul bx
    push ax
    mov al, 1
    call util_get_token
    pop ax
    mov si, scratch
    mov di, rule_a
    add di, ax
    mov cx, FACT_LEN
    call util_copy_bounded

    mov al, [rule_count]
    mov ah, 0
    mov bx, FACT_LEN
    mul bx
    push ax
    mov al, 2
    call util_get_token
    pop ax
    mov si, scratch
    mov di, rule_b
    add di, ax
    mov cx, FACT_LEN
    call util_copy_bounded

    mov al, [rule_count]
    mov ah, 0
    mov bx, FACT_LEN
    mul bx
    push ax
    mov al, 3
    call util_get_token
    pop ax
    mov si, scratch
    mov di, rule_c
    add di, ax
    mov cx, FACT_LEN
    call util_copy_bounded

    inc byte [rule_count]
    mov si, msg_ok
    call io_print_str
    call io_print_crlf

.done:
    pop di
    pop si
    pop cx
    pop bx
    pop ax
    ret

; forward_chain : run all rules to a fixpoint (repeat until a full pass
; adds no new facts). Purely a side-effecting routine.
forward_chain:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp

.pass:
    mov byte [fc_changed], 0
    xor bp, bp
.rule_loop:
    mov al, [rule_count]
    mov ah, 0
    cmp bp, ax
    jae .pass_done

    mov ax, bp
    mov bx, FACT_LEN
    mul bx
    mov si, rule_a
    add si, ax
    call fact_find
    cmp ax, 0xFFFF
    je .skip

    mov ax, bp
    mov bx, FACT_LEN
    mul bx
    mov si, rule_b
    add si, ax
    mov di, wildcard_dash
    call util_streq
    cmp al, 1
    je .b_ok
    call fact_find
    cmp ax, 0xFFFF
    je .skip
.b_ok:

    mov ax, bp
    mov bx, FACT_LEN
    mul bx
    mov si, rule_c
    add si, ax
    call fact_find
    cmp ax, 0xFFFF
    jne .skip

    mov al, [fact_count]
    cmp al, MAX_FACTS
    jae .skip

    mov al, [fact_count]
    mov ah, 0
    mov bx, FACT_LEN
    mul bx
    mov di, facts
    add di, ax

    mov ax, bp
    mov bx, FACT_LEN
    mul bx
    mov si, rule_c
    add si, ax
    mov cx, FACT_LEN
    call util_copy_bounded

    inc byte [fact_count]
    mov byte [fc_changed], 1

.skip:
    inc bp
    jmp .rule_loop

.pass_done:
    cmp byte [fc_changed], 0
    jne .pass

    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ask_goal : "ASK <name>" -- run forward chaining, report YES/NO.
ask_goal:
    push ax
    push si
    push di

    mov al, [token_count]
    cmp al, 2
    jae .have_arg
    mov si, msg_ask_usage
    call io_print_str
    call io_print_crlf
    jmp .done

.have_arg:
    call forward_chain

    mov al, 1
    call util_get_token
    mov si, di
    call fact_find
    cmp ax, 0xFFFF
    je .no

    mov si, msg_yes
    call io_print_str
    call io_print_crlf
    jmp .done
.no:
    mov si, msg_no
    call io_print_str
    call io_print_crlf

.done:
    pop di
    pop si
    pop ax
    ret

; list_facts : "LIST" -- run forward chaining, print everything known.
list_facts:
    push ax
    push bx
    push si
    push bp

    call forward_chain

    mov al, [fact_count]
    cmp al, 0
    jne .have_facts
    mov si, msg_no_facts
    call io_print_str
    call io_print_crlf
    jmp .done

.have_facts:
    xor bp, bp
.loop:
    mov al, [fact_count]
    mov ah, 0
    cmp bp, ax
    jae .done

    mov ax, bp
    mov bx, FACT_LEN
    mul bx
    mov si, facts
    add si, ax
    call io_print_str
    call io_print_crlf

    inc bp
    jmp .loop

.done:
    pop bp
    pop si
    pop bx
    pop ax
    ret
