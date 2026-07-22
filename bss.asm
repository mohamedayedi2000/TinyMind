; =====================================================================
; TINYMIND -- bss.asm
; Every piece of mutable state the program touches lives here, as bare
; reserved space (resb/resw). Nothing here has a value baked into the
; .COM file -- init_all (in main.asm) sets it all to a known state when
; the program starts. Keep this %included LAST in main.asm so no
; initialised data ever has to be placed after a reserved block.
; =====================================================================

; ---- line input ----
input_buf:      db INPUT_MAX        ; DOS wants the max length here
                db 0                ; DOS fills in the actual length here
                resb INPUT_MAX+1    ; the characters DOS reads

; ---- tokens (offset+length pairs into input_buf; line is NOT mangled,
;      so "everything from token N onward" is still a valid string) ----
token_ptr:      resw MAX_TOKENS
token_len:      resb MAX_TOKENS
token_count:    resb 1

scratch:        resb SCRATCH_LEN    ; scratch copy of a single token
scratch2:       resb SCRATCH_LEN    ; a second one, for two-token lookups

; ---- interpreter: multi-character variable symbol table ----
var_names:      resb MAX_VARS*VARNAME_LEN
var_values:     resw MAX_VARS
var_count:      resb 1

; ---- interpreter: stored, line-numbered program (for RUN/GOTO) ----
prog_line_no:   resw MAX_PROG_LINES
prog_text:      resb MAX_PROG_LINES*PROGLINE_LEN
prog_count:     resb 1
prog_running:   resb 1      ; 1 while RUN's execution loop is active
goto_requested: resb 1      ; set by GOTO/GOSUB/RETURN while prog_running
goto_target:    resw 1      ; the requested line number
run_steps:      resw 1      ; RUN's own step counter (memory, not a register --
                             ; several statement types call mul while executing)
current_line:   resw 1      ; the line RUN is currently executing (for GOSUB)

; ---- interpreter: GOSUB/RETURN call stack ----
gosub_stack:    resw GOSUB_STACK_SIZE
gosub_sp:       resb 1

; ---- interpreter: FOR/NEXT loop stack ----
for_var_name:   resb FOR_STACK_SIZE*VARNAME_LEN
for_end:        resw FOR_STACK_SIZE
for_step:       resw FOR_STACK_SIZE
for_line:       resw FOR_STACK_SIZE
for_sp:         resb 1

; ---- expert system: facts and rules ----
facts:          resb MAX_FACTS*FACT_LEN
fact_count:     resb 1

rule_a:         resb MAX_RULES*FACT_LEN
rule_b:         resb MAX_RULES*FACT_LEN
rule_c:         resb MAX_RULES*FACT_LEN
rule_count:     resb 1
fc_changed:     resb 1

; ---- chatbot: patterns (now up to two keywords each) and responses
;      (seeded from chat_seed_* at boot) ----
chat_pat1:      resb MAX_PATTERNS*PATTERN_LEN
chat_pat2:      resb MAX_PATTERNS*PATTERN_LEN   ; empty string = single-keyword
chat_resp:      resb MAX_PATTERNS*RESPONSE_LEN
chat_count:     resb 1
best_pat_idx:   resw 1              ; scratch "best match so far" for chatbot scoring
best_pat_score: resw 1              ; scratch "best specificity so far"

; ---- chatbot: Markov word-pair model, learned live from conversation ----
mk_word1:       resb MAX_MK*MKWORD_LEN
mk_word2:       resb MAX_MK*MKWORD_LEN
mk_count:       resb MAX_MK
mk_count_n:     resb 1
gen_buf:        resb 176            ; assembled Markov-generated sentence
reflect_buf:    resb INPUT_MAX+8    ; reflected ("I"<->"YOU" etc) text
mk_sum:         resw 1              ; scratch accumulator for weighted pick
mk_pick:        resw 1              ; scratch "remaining pick" for weighted pick

; ---- shared PRNG state ----
rng_seed:       resw 1
