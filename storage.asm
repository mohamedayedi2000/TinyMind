; =====================================================================
; TINYMIND -- storage.asm (v2)
; SAVE / LOAD persist EVERYTHING TINYMIND has learned or been given:
; chatbot patterns, expert-system facts and rules, interpreter
; variables, the live Markov language model, and the stored program.
; One flat sequential file: for each section, a one-byte count
; followed by that many fixed-size records. Two small macros do the
; repetitive part so the two routines below just list the sections.
; =====================================================================

%macro SAVE_COUNT 1
    mov cx, 1
    mov dx, %1
    call io_write_block
    jc .err_close
%endmacro

%macro SAVE_ARRAY 3
    ; %1 = count variable, %2 = data buffer, %3 = bytes per entry
    mov al, [%1]
    mov ah, 0
%if %3 = 1
    mov cx, ax
%else
    mov cx, %3
    mul cx
    mov cx, ax
%endif
    mov dx, %2
    call io_write_block
    jc .err_close
%endmacro

%macro LOAD_COUNT 2
    ; %1 = count variable, %2 = its max legal value (safety clamp)
    mov cx, 1
    mov dx, %1
    call io_read_block
    jc .err_close
    mov al, [%1]
    cmp al, %2
    jbe %%okcount
    mov byte [%1], %2
%%okcount:
%endmacro

%macro LOAD_ARRAY 3
    mov al, [%1]
    mov ah, 0
%if %3 = 1
    mov cx, ax
%else
    mov cx, %3
    mul cx
    mov cx, ax
%endif
    mov dx, %2
    call io_read_block
    jc .err_close
%endmacro

know_filename:   db "TINYMIND.DAT",0
msg_saved:       db "Saved.",13,10,0
msg_save_fail:   db "Could not save.",13,10,0
msg_loaded:      db "Loaded.",13,10,0
msg_load_fail:   db "Could not read the save file.",13,10,0
msg_none_saved:  db "No saved data yet.",13,10,0

; storage_save : write TINYMIND.DAT with everything learned so far.
storage_save:
    push ax
    push bx
    push cx
    push dx

    mov ah, 0x3c
    xor cx, cx
    mov dx, know_filename
    int 0x21
    jc .err

    mov bx, ax

    SAVE_COUNT chat_count
    SAVE_ARRAY chat_count, chat_pat1, PATTERN_LEN
    SAVE_ARRAY chat_count, chat_pat2, PATTERN_LEN
    SAVE_ARRAY chat_count, chat_resp, RESPONSE_LEN

    SAVE_COUNT fact_count
    SAVE_ARRAY fact_count, facts, FACT_LEN

    SAVE_COUNT rule_count
    SAVE_ARRAY rule_count, rule_a, FACT_LEN
    SAVE_ARRAY rule_count, rule_b, FACT_LEN
    SAVE_ARRAY rule_count, rule_c, FACT_LEN

    SAVE_COUNT var_count
    SAVE_ARRAY var_count, var_names, VARNAME_LEN
    SAVE_ARRAY var_count, var_values, 2

    SAVE_COUNT mk_count_n
    SAVE_ARRAY mk_count_n, mk_word1, MKWORD_LEN
    SAVE_ARRAY mk_count_n, mk_word2, MKWORD_LEN
    SAVE_ARRAY mk_count_n, mk_count, 1

    SAVE_COUNT prog_count
    SAVE_ARRAY prog_count, prog_line_no, 2
    SAVE_ARRAY prog_count, prog_text, PROGLINE_LEN

    mov ah, 0x3e
    int 0x21

    mov si, msg_saved
    call io_print_str
    jmp .done

.err_close:
    mov ah, 0x3e
    int 0x21
.err:
    mov si, msg_save_fail
    call io_print_str
.done:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; storage_load : read TINYMIND.DAT back, if present, restoring
; everything it holds.
storage_load:
    push ax
    push bx
    push cx
    push dx

    mov ax, 0x3d00
    mov dx, know_filename
    int 0x21
    jc .notfound

    mov bx, ax

    LOAD_COUNT chat_count, MAX_PATTERNS
    LOAD_ARRAY chat_count, chat_pat1, PATTERN_LEN
    LOAD_ARRAY chat_count, chat_pat2, PATTERN_LEN
    LOAD_ARRAY chat_count, chat_resp, RESPONSE_LEN

    LOAD_COUNT fact_count, MAX_FACTS
    LOAD_ARRAY fact_count, facts, FACT_LEN

    LOAD_COUNT rule_count, MAX_RULES
    LOAD_ARRAY rule_count, rule_a, FACT_LEN
    LOAD_ARRAY rule_count, rule_b, FACT_LEN
    LOAD_ARRAY rule_count, rule_c, FACT_LEN

    LOAD_COUNT var_count, MAX_VARS
    LOAD_ARRAY var_count, var_names, VARNAME_LEN
    LOAD_ARRAY var_count, var_values, 2

    LOAD_COUNT mk_count_n, MAX_MK
    LOAD_ARRAY mk_count_n, mk_word1, MKWORD_LEN
    LOAD_ARRAY mk_count_n, mk_word2, MKWORD_LEN
    LOAD_ARRAY mk_count_n, mk_count, 1

    LOAD_COUNT prog_count, MAX_PROG_LINES
    LOAD_ARRAY prog_count, prog_line_no, 2
    LOAD_ARRAY prog_count, prog_text, PROGLINE_LEN

    mov ah, 0x3e
    int 0x21

    mov si, msg_loaded
    call io_print_str
    jmp .done

.err_close:
    mov ah, 0x3e
    int 0x21
    mov si, msg_load_fail
    call io_print_str
    jmp .done

.notfound:
    mov si, msg_none_saved
    call io_print_str

.done:
    pop dx
    pop cx
    pop bx
    pop ax
    ret
