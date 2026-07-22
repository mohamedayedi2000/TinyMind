; =====================================================================
; TINYMIND -- rng.asm
; A small, real pseudo-random number generator (not a lookup table of
; "random-looking" constants). Seeded once from the BIOS tick count
; (INT 1Ah), then a classic 16-bit linear-congruential step:
;     seed = seed * 25173 + 13849   (mod 65536, via natural overflow)
; Good enough to vary chatbot replies and pick weighted Markov
; continuations; not a cryptographic RNG.
; =====================================================================

; rng_init : seed rng_seed from the BIOS timer tick count.
rng_init:
    push ax
    push cx
    push dx

    mov ah, 0x00
    int 0x1a                 ; cx:dx = tick count since midnight
    mov ax, cx
    xor ax, dx
    or ax, ax
    jnz .nonzero
    mov ax, 1                 ; never seed with exactly 0
.nonzero:
    mov [rng_seed], ax

    pop dx
    pop cx
    pop ax
    ret

; rng_next : advance and return the PRNG. Out: AX = next pseudo-random word.
rng_next:
    push dx
    push bx

    mov ax, [rng_seed]
    mov bx, 25173
    mul bx                    ; dx:ax = seed*25173 ; we keep ax, drop dx
    add ax, 13849
    mov [rng_seed], ax

    pop bx
    pop dx
    ret

; rng_range : a pseudo-random value in 0..(CX-1). Assumes CX >= 1.
; Out: AX = value.
rng_range:
    push dx
    push cx

    call rng_next
    xor dx, dx
    div cx                    ; ax=quotient (discarded), dx=remainder
    mov ax, dx

    pop cx
    pop dx
    ret
