; =====================================================================
; TINYMIND -- dispatch.asm (v2)
; The single place that decides which module handles a typed line.
; To add a new command: write its handler in its own module, then add
; one row to dispatch_table below. Nothing else has to change -- this
; is the "swappable module" registry the whole design is built around.
; Each keyword now maps straight to its real handler (a keyword is
; already uniquely identified by the scan below, so an extra re-check
; inside the handler would just be repeated work).
; =====================================================================

kw_let:     db "LET",0
kw_print:   db "PRINT",0
kw_if:      db "IF",0
kw_goto:    db "GOTO",0
kw_gosub:   db "GOSUB",0
kw_return:  db "RETURN",0
kw_for:     db "FOR",0
kw_next:    db "NEXT",0
kw_run:     db "RUN",0
kw_plist:   db "PLIST",0
kw_new:     db "NEW",0
kw_end:     db "END",0
kw_stop:    db "STOP",0
kw_fact:    db "FACT",0
kw_rule:    db "RULE",0
kw_ask:     db "ASK",0
kw_list:    db "LIST",0
kw_teach:   db "TEACH",0
kw_think:   db "THINK",0
kw_save:    db "SAVE",0
kw_load:    db "LOAD",0
kw_help:    db "HELP",0
kw_exit:    db "EXIT",0

; each row: dw keyword-string-pointer, dw handler-routine-offset
dispatch_table:
    dw kw_let,    interp_let
    dw kw_print,  interp_print
    dw kw_if,     interp_if
    dw kw_goto,   cmd_goto
    dw kw_gosub,  cmd_gosub
    dw kw_return, cmd_return
    dw kw_for,    cmd_for
    dw kw_next,   cmd_next
    dw kw_run,    cmd_run
    dw kw_plist,  cmd_plist
    dw kw_new,    cmd_new
    dw kw_end,    cmd_end
    dw kw_stop,   cmd_end
    dw kw_fact,   fact_add
    dw kw_rule,   rule_add
    dw kw_ask,    ask_goal
    dw kw_list,   list_facts
    dw kw_teach,  chatbot_teach
    dw kw_think,  chatbot_think
    dw kw_save,   storage_save
    dw kw_load,   storage_load
    dw kw_help,   cmd_help
    dw kw_exit,   cmd_exit
    dw 0, 0

; dispatch_handle : token_ptr/token_len/token_count already filled in
; (caller guarantees token_count > 0). Looks at token 0, routes to the
; matching module, or falls back to the chatbot for ordinary conversation.
dispatch_handle:
    push ax
    push bx
    push cx
    push si
    push di

    mov si, [token_ptr]
    mov cl, [token_len]
    mov ch, 0

    mov bx, dispatch_table
.scan:
    mov di, [bx]
    cmp di, 0
    je .fallback
    call util_tok_eq
    cmp al, 0
    jne .found
    add bx, 4
    jmp .scan

.found:
    mov di, [bx+2]
    call di
    jmp .done

.fallback:
    call chatbot_handle

.done:
    pop di
    pop si
    pop cx
    pop bx
    pop ax
    ret
