; =====================================================================
; TINYMIND -- kernel_defs.inc
; Shared equates used by every module. No code, no data: just numbers,
; so this can be %included first, before anything else exists.
; =====================================================================

INPUT_MAX       equ 120     ; max characters DOS will accept on one line
MAX_TOKENS      equ 12      ; max words per line we bother splitting
SCRATCH_LEN     equ 24      ; size of the general-purpose token scratch buffer

MAX_FACTS       equ 32
FACT_LEN        equ 9       ; 8 chars + NUL

MAX_RULES       equ 16

MAX_PATTERNS    equ 40      ; built-in + TEACH-able chatbot patterns
PATTERN_LEN     equ 16
RESPONSE_LEN    equ 80

; -- v2 additions --
MAX_VARS        equ 40      ; multi-character interpreter variables
VARNAME_LEN     equ 12      ; 11 chars + NUL

MAX_PROG_LINES  equ 100     ; stored (line-numbered) program
PROGLINE_LEN    equ 56      ; text of one program line, incl NUL
RUN_STEP_LIMIT  equ 60000   ; safety cap on executed statements per RUN
                             ; (must fit in 16 bits -- this is a 16-bit machine)

MAX_MK          equ 220     ; Markov-chain (word1 -> word2, count) triples
MKWORD_LEN      equ 10      ; 9 chars + NUL
MK_GEN_MAXWORDS equ 14      ; longest sentence mk_generate will produce

; -- v3 additions --
GOSUB_STACK_SIZE equ 16     ; nested GOSUB depth
FOR_STACK_SIZE   equ 8      ; nested FOR depth
