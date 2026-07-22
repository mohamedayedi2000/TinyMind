# TINYMIND v3

A small "AI-flavoured" system for a real Intel 8086, written entirely in
8086 assembly (NASM syntax) -- pushed about as far as that combination can
honestly go. Four things work together, each in its own module, wired
through one central dispatch table:

- **A chatbot** that scores every line against every known pattern --
  including patterns that need *two* keywords together, which correctly
  outrank a one-keyword match -- falls back to ELIZA-style pronoun
  reflection when nothing matches, and after that to a **from-scratch
  Markov-chain language model** that has genuinely learned from every
  conversation it's had. It now knows where sentences plausibly start and
  stop (learned, not hard-coded), so it generates naturally-sized
  original sentences instead of always running to a word cap.
- **An expert system** -- facts, `a AND b => c` rules, forward chaining,
  `ASK`/`LIST`.
- **A real line-numbered BASIC**, and now a fairly complete one:
  `GOTO`, `GOSUB`/`RETURN` (nested subroutines, a real call stack), and
  `FOR`/`NEXT` (including counting down with a negative `STEP`) all work,
  with variables that can be any name and can hold negative numbers.
- **Persistence covering all of the above** -- `SAVE`/`LOAD` round-trip
  chat patterns, facts, rules, variables, the stored program, and the
  Markov model itself.

To add a new capability: write its handler in its own file, add one line
to `src/dispatch.asm`. Nothing else has to change -- that's held up
through three rounds of adding real capability now.

## The one honest limit

A "professional AI" in the ChatGPT/transformer sense needs billions of
parameters and matrix math at a scale this chip cannot do -- a 1MB-of-
memory, no-hardware-float, 5-10MHz hardware ceiling, not something better
assembly fixes. Everything else in this README is real, running, and
tested; it's also all pre-deep-learning technique (pattern matching,
forward chaining, Markov chains, BASIC) pushed about as far as it can go
on this specific chip, not a scaled-down LLM.

## Build

Requires [NASM](https://www.nasm.us/).

```sh
./build.sh
# or directly:
cd src && nasm -f bin main.asm -o ../tinymind.com
```

Produces `tinymind.com`, a flat 16-bit DOS program (~26KB).

## Run

Install [DOSBox](https://www.dosbox.com/) and run `tinymind.com` inside
it. It also runs unmodified on real 8086/8088 PC-XT-class hardware or a
full PC emulator (86Box, PCem, QEMU with a DOS boot disk) -- only BIOS-era
DOS calls are used (character I/O, plain file open/read/write/close),
nothing DOS-version- or CPU-generation-specific. For quick command-line
testing without a full DOS environment, it also runs under
[emu2](https://github.com/dmsc/emu2), which is what was used for all
testing below.

## Commands

```
Conversation:
  <anything>                 chat: best keyword match, then reflection,
                              then Markov generation, in that order
  TEACH <w>[+<w2>] <reply>   teach a pattern (needs BOTH w and w2, if given)
  THINK                      generate a sentence from what it's learned
  SAVE / LOAD                persist / restore EVERYTHING below

Expert system:
  FACT <name>                assert a fact
  RULE <a> <b> <c>           a AND b => c   (b = "-" if only one antecedent)
  ASK <name>                 is <name> derivable? YES/NO
  LIST                       show every known fact (after forward chaining)

Programming (variables are any name, and may be negative, e.g. LET X = -5):
  LET <v> = <t> [<op> <t2>]  op is + - * /
  PRINT <t>                  print a value
  IF <t><relop><t> THEN PRINT <t2> | LET <v>=<t2> | GOTO <n> | GOSUB <n>
  GOTO <n> / GOSUB <n> / RETURN         (relop: = < >; need a RUNning program)
  FOR <v> = <s> TO <e> [STEP <s2>]      a matching NEXT <v> closes the loop
  NEXT <v>
  <n> <statement>            store <statement> as program line <n>
  <n>                        (alone) delete program line <n>
  RUN / PLIST / NEW          run / list / clear the stored program
  END or STOP                halt a running program early
  HELP / EXIT
```

Everything typed is folded to upper case.

### Example session

```
> TEACH RAINING+COLD Bundle up, it's a rough one out there.
OK, learned it.
> IT IS RAINING AND COLD
BUNDLE UP, IT'S A ROUGH ONE OUT THERE.
> 10 FOR I = 5 TO 1 STEP -1
> 20 PRINT I
> 30 GOSUB 100
> 40 NEXT I
> 50 END
> 100 IF I = 1 THEN PRINT 999
> 110 RETURN
> RUN
5
4
3
2
1
999
> LET SCORE = -3
> PRINT SCORE
-3
> the quick brown fox jumps over the lazy dog
I see. Tell me more.
> THINK
THE LAZY DOG
> SAVE
Saved.
> EXIT
Goodbye.
```

## Architecture

```
src/
  kernel_defs.inc   shared equates -- no code, no data
  main.asm          entry point, startup/banner, the read->tokenize->
                    dispatch loop, HELP/EXIT
  io.asm            console I/O (now signed-number-aware) + generic
                    block read/write (for SAVE/LOAD)
  util.asm          string compare, token->number parsing (now accepts
                    a leading '-'), token copying, the generic bounded-
                    copy used by every module
  rng.asm           a real 16-bit PRNG (seeded from the BIOS tick count)
  lexer.asm         splits a line into (offset, length) tokens WITHOUT
                    mangling the original text
  vars.asm          the interpreter's variable symbol table
  dispatch.asm      the module registry: keyword -> handler, directly
  chatbot.asm       one- or two-keyword pattern scoring, ELIZA-style
                    reflection (table-driven, see below), TEACH, and the
                    policy for when to use Markov generation
  markov.asm        the Markov word-pair model: learn (now including
                    sentence-boundary markers), and weighted-random
                    generate (now stops at a learned boundary)
  expert.asm        facts, rules, forward chaining, ASK/LIST
  interp.asm        LET/PRINT/IF, the stored-program engine (line
                    storage/insertion/deletion, RUN, GOTO, PLIST, NEW),
                    and now GOSUB/RETURN (a real call stack) and
                    FOR/NEXT (a real loop stack)
  storage.asm       SAVE/LOAD, via two small macros
  bss.asm           every mutable buffer/array, reserved space only --
                    included LAST in main.asm
```

**Reflection is now one vocabulary, not two.** In v2, the "does this line
need reflecting?" check used its own hard-coded word list, separate from
the table that actually does the reflecting -- so extending reflection
meant remembering to update both. `chat_has_reflect_trigger` now scans
`reflect_table` directly, the exact same table `reflect_lookup` uses.
Adding a word to reflection is one line, in one place, and both trigger
detection and rewriting see it immediately.

**How two-keyword patterns are scored.** Each pattern has two keyword
slots; the second is an empty string for an ordinary single-keyword
pattern. A pattern only counts as matching at all if every keyword it has
is found somewhere in the line (not necessarily adjacent); satisfying
both keywords of a two-keyword pattern scores 2, a single-keyword match
scores 1, and the highest score wins, with ties going to whichever
pattern was taught more recently.

**How the Markov model learned where sentences start and stop.** Rather
than a separate data structure, learning a line also learns two extra
pairs using two reserved single-byte "words" a person can never type:
`(<START>, first_word)` and `(last_word, <END>)`. Generation asks for a
weighted-random word that has actually followed `<START>` before (a real,
learned sentence-opener, not an arbitrary pick), and stops the moment
`<END>` is the weighted pick for what comes next -- so the output length
reflects what's actually been observed, not a fixed cap.

**How `GOSUB`/`RETURN` and `FOR`/`NEXT` share one mechanism.** Both are
built on the same `goto_target`/`goto_requested` flag pair that `GOTO`
already used -- `GOSUB` pushes the current line onto a small call stack
before jumping, `RETURN` pops it and asks "what's the next line after
that one", and `NEXT` does the same thing, looking up its matching `FOR`
frame instead. `RUN`'s main loop doesn't need to know anything special
happened.

## Testing

`tests/run_tests.sh` runs the real, assembled `tinymind.com` under
[emu2](https://github.com/dmsc/emu2) with real scripted input -- now 34
sections, reproducible on a clean rebuild:

```sh
./build.sh
EMU2=/path/to/emu2 ./tests/run_tests.sh
```

Sections 1-27 are the full v1/v2 regression suite (every chat pattern,
persistence, the expert system, all four `LET` operators, `IF` both ways,
divide-by-zero, every table filled to its exact limit, and the v2
`GOTO`/program-store feature set) -- all still pass unchanged. New in v3:

| # | Scenario | Result |
|---|----------|--------|
| 28 | Signed numbers: negative literal, arithmetic, signed `IF` | `-5`, `5`, `-7`, condition true |
| 29 | `GOSUB`/`RETURN` (called twice) and `IF...THEN GOSUB` | `1`, `2`; and `999` |
| 30 | `FOR`/`NEXT` up, down with `STEP -1`, custom `STEP`, and nested loops | `1 2 3 4 5`; `5 4 3 2 1`; `0 2 4 6 8 10`; correct nested sequence |
| 31 | Two-keyword `TEACH`: a satisfied 2-keyword pattern beats a 1-keyword one | the more specific reply wins |
| 32 | `RETURN` without `GOSUB`, `NEXT` without `FOR`, mismatched `NEXT`/`FOR` variable | three clean errors, no crash |
| 33 | SAFETY: `GOSUB` stack overflow via infinite recursion | fails cleanly, doesn't hang |
| 34 | Parsing rigor: `IF X == 5` (two-char relop) is rejected; `IF X = 5` still works | `?SYNTAX ERROR`, then `2` |

A real excerpt (section 30, the nested-loop case: `I` 1..3, inner `J` 1..2):

```
> > > > > > > 1
1
1
2
2
1
2
2
3
1
3
2
> Goodbye.
```

### Bugs this round actually found (and fixed)

Three real ones, all caught by running the new features, not by
re-reading them:

1. **`cmd_for`'s `=` check always failed.** The length was validated
   correctly, but the following `util_tok_eq` call needs `CX` loaded with
   that same length as an explicit input -- and that load was missing, so
   `CX` was left holding a stale value from an unrelated earlier step.
   Every `FOR` statement failed with `?SYNTAX ERROR` before it could do
   anything.
2. **`NEXT` looped back to the `FOR` line itself, not the line after
   it.** That made `FOR` re-execute every iteration, re-initialising the
   loop variable and pushing a *new* stack frame each time -- which
   surfaced as `?FOR nested too deep` after enough iterations, with the
   loop variable stuck at its start value the whole time. Fixed by
   routing `NEXT`'s jump through the same "smallest stored line number
   greater than X" lookup `RETURN` already used correctly.
3. A third potential instance of the `mul`-clobbers-a-register-you-still-
   need bug (this time in `cmd_next`, where `var_assign`'s own `DX`
   input parameter was about to silently overwrite a `STEP` value the
   increment-direction check still needed) was caught during design, by
   re-tracing the exact register contents at each step rather than
   trusting that it "looked right" -- before it was ever assembled. Worth
   naming even though it never became a runtime bug, since it's the same
   mistake as (1) and (2) in the v2 README, just prevented one step
   earlier this time.

## Known limitations / good next projects

The five items listed here in the previous README are now fixed:
`FOR`/`NEXT` and `GOSUB`/`RETURN` both work (tested above, including
nesting); `TEACH` supports two-keyword patterns with correct specificity
scoring; the reflection vocabulary is bigger and now single-sourced; the
`IF` relop is length-checked; and the Markov model has real sentence-
boundary awareness. What's left:

- **`FOR`/`NEXT` doesn't check that a program is actually `RUN`ning**,
  unlike `GOTO`/`GOSUB`/`RETURN`, which all give a friendly
  "only makes sense while RUNning" message. Typing `NEXT` at the
  interactive prompt just silently does nothing useful rather than
  explaining why. Small, easy fix; just hasn't been made yet.
- **Two-keyword patterns are still exactly two, and always "both
  required."** No three-keyword patterns, and no "either word" (OR)
  matching.
- **`FOR` always runs its body at least once**, even if the start value
  already fails the end condition (classic BASIC behaviour, but worth
  knowing rather than assuming).
- **The Markov model's word-count cap (`MK_GEN_MAXWORDS`) is still a
  hard backstop** even with boundary awareness -- a pathological chain
  that never happens to pick `<END>` will still be cut off rather than
  run forever.
- **Numbers are 16-bit two's complement** (-32768 to 32767) with no
  overflow detection -- arithmetic that goes out of that range wraps
  silently rather than erroring.
