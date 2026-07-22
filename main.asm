; =====================================================================
; TINYMIND -- main.asm (v2)
; Entry point for the whole program. Ties every module together
; through dispatch_handle. bss.asm is included LAST so no initialised
; data ever has to be placed after a block of reserved storage.
; =====================================================================

BITS 16
CPU 8086
ORG 0x100

%include "kernel_defs.inc"

start:
    cld
    call init_all
    call banner
    call main_loop
    mov ax, 0x4c00
    int 0x21

%include "io.asm"
%include "util.asm"
%include "rng.asm"
%include "lexer.asm"
%include "vars.asm"
%include "storage.asm"
%include "markov.asm"
%include "chatbot.asm"
%include "expert.asm"
%include "interp.asm"
%include "dispatch.asm"

; ---------------------------------------------------------------
; Kernel-level bits simple enough to live right here: startup,
; banner/help text, and the read -> tokenize -> dispatch loop.
; ---------------------------------------------------------------

prompt_str:  db "> ",0
msg_bye:     db "Goodbye.",13,10,0
msg_banner:  db "TINYMIND v2 -- chat, an expert system, a live-learning Markov",13,10
             db "language model, and a line-numbered BASIC, all in 8086 asm.",13,10
             db "Type HELP for commands, EXIT to quit.",13,10,13,10,0
msg_help:    db "Conversation:",13,10
             db "  <anything>                chat (best keyword match, reflection,",13,10
             db "                             or Markov generation, in that order)",13,10
             db "  TEACH <w>[+<w2>] <reply>   teach a pattern (2 keywords if w+w2)",13,10
             db "  THINK                      generate a sentence from what it's learned",13,10
             db "  SAVE / LOAD                persist / restore EVERYTHING below",13,10
             db "Expert system:",13,10
             db "  FACT <name>                assert a fact",13,10
             db "  RULE <a> <b> <c>           a AND b => c  (b = - if unneeded)",13,10
             db "  ASK <name>                 is <name> derivable? YES/NO",13,10
             db "  LIST                       show all known facts",13,10
             db "Programming (variables are any name, not just one letter):",13,10
             db "  LET <v> = <t> [<op> <t2>]  op is + - * /  (t may be negative, e.g. -5)",13,10
             db "  PRINT <t>                  print a value",13,10
             db "  IF <t><relop><t> THEN PRINT <t2>|LET <v>=<t2>|GOTO <n>|GOSUB <n>",13,10
             db "  GOTO <n> / GOSUB <n> / RETURN     (relop: = < >; need a RUNning program)",13,10
             db "  FOR <v>=<s> TO <e> [STEP <s2>]    loop; matching NEXT <v> closes it",13,10
             db "  NEXT <v>",13,10
             db "  <n> <statement>            store <statement> as program line <n>",13,10
             db "  <n>                        (alone) delete program line <n>",13,10
             db "  RUN / PLIST / NEW          run / list / clear the stored program",13,10
             db "  END or STOP                 halt a running program early",13,10
             db "  HELP / EXIT",13,10,0

init_all:
    push ax
    push cx
    push si
    push di

    call rng_init

    mov byte [fact_count], 0
    mov byte [rule_count], 0
    mov byte [var_count], 0
    mov byte [mk_count_n], 0
    mov byte [prog_count], 0
    mov byte [prog_running], 0
    mov byte [goto_requested], 0
    mov byte [gosub_sp], 0
    mov byte [for_sp], 0

    mov si, chat_seed_pat1
    mov di, chat_pat1
    mov cx, chat_seed_count*PATTERN_LEN
    rep movsb

    mov di, chat_pat2
    mov cx, chat_seed_count*PATTERN_LEN
    xor al, al
    rep stosb

    mov si, chat_seed_resp
    mov di, chat_resp
    mov cx, chat_seed_count*RESPONSE_LEN
    rep movsb

    mov byte [chat_count], chat_seed_count

    pop di
    pop si
    pop cx
    pop ax
    ret

banner:
    push si
    mov si, msg_banner
    call io_print_str
    pop si
    ret

cmd_help:
    push si
    mov si, msg_help
    call io_print_str
    pop si
    ret

cmd_exit:
    mov si, msg_bye
    call io_print_str
    mov ax, 0x4c00
    int 0x21

main_loop:
.top:
    mov si, prompt_str
    call io_print_str

    call io_read_line
    call lexer_tokenize

    mov al, [token_count]
    cmp al, 0
    je .top

    mov al, 0
    call util_tok_first_is_digit
    cmp al, 0
    je .not_progline
    call prog_store_line
    jmp .top

.not_progline:
    call dispatch_handle
    jmp .top

%include "bss.asm"
