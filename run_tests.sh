#!/bin/sh
# TINYMIND test suite. Runs the assembled tinymind.com under emu2 with
# scripted input for every command, both branches of every conditional,
# and the table-full boundary for each fixed-size table. Not a thought
# experiment: this actually executes the .COM file each time.
#
# Usage: ./tests/run_tests.sh   (run from the project root)
# Requires: emu2 (https://github.com/dmsc/emu2) on PATH, or set EMU2=path

EMU2="${EMU2:-emu2}"
COM="$(cd "$(dirname "$0")/.." && pwd)/tinymind.com"
WORKDIR=$(mktemp -d)
cp "$COM" "$WORKDIR/tinymind.com"
cd "$WORKDIR"

section () { echo; echo "=== $1 ==="; }
run () { printf "%b" "$1" | "$EMU2" tinymind.com; }

section "1. Chatbot: every built-in pattern + fallback"
run 'HELLO\nMY NAME\nHOW ARE YOU\nTHANK YOU\nSORRY\nBYE\nASDFQWERTY\nEXIT\n'

section "2. Chatbot: TEACH, use it, usage error"
run 'TEACH PIZZA My favorite food is pizza, obviously.\nPIZZA\nTEACH ONLYONEWORD\nEXIT\n'

section "3. Persistence: TEACH+SAVE, then fresh process LOAD"
run 'TEACH ROBOT Beep boop.\nSAVE\nEXIT\n'
run 'LOAD\nROBOT\nEXIT\n'

section "4. Persistence: LOAD with no save file (separate clean dir)"
(mkdir -p "$WORKDIR/clean" && cp "$COM" "$WORKDIR/clean/tinymind.com" && cd "$WORKDIR/clean" && \
 printf 'LOAD\nEXIT\n' | "$EMU2" tinymind.com)

section "5. Expert system: FACT new/duplicate/usage-error"
run 'FACT RAINING\nFACT RAINING\nFACT\nEXIT\n'

section "6. Expert system: RULE (2-antecedent + wildcard), ASK true/false, LIST"
run 'FACT RAINING\nFACT COLD\nRULE RAINING COLD SNOWY\nASK SNOWY\nASK SUNNY\nFACT TIRED\nRULE TIRED - SLEEPY\nASK SLEEPY\nLIST\nRULE A B\nEXIT\n'

section "7. Expert system: multi-step forward chaining (A,B => C; C,D => E)"
run 'FACT A\nFACT B\nFACT D\nRULE A B C\nRULE C D E\nASK E\nEXIT\n'

section "8. Expert system: LIST with zero facts"
run 'LIST\nEXIT\n'

section "9. Interpreter: LET all four operators + PRINT"
run 'LET X = 10\nLET Y = 3\nLET Z = X + Y\nPRINT Z\nLET Z = X - Y\nPRINT Z\nLET Z = X * Y\nPRINT Z\nLET Z = X / Y\nPRINT Z\nEXIT\n'

section "10. Interpreter: divide by zero, bad variable, missing ="
run 'LET X = 5\nLET Y = 0\nLET Z = X / Y\nPRINT Z\nLET N2 = 1\nLET Q 5\nEXIT\n'

section "11. Interpreter: IF with = < > , each true AND false, both THEN forms"
run 'LET X = 5\nLET Y = 5\nIF X = Y THEN PRINT X\nLET Y = 9\nIF X = Y THEN PRINT X\nIF X < Y THEN PRINT X\nIF Y < X THEN PRINT Y\nIF Y > X THEN PRINT Y\nIF X > Y THEN PRINT X\nIF X < Y THEN LET W = 111\nPRINT W\nEXIT\n'

section "12. Interpreter: IF syntax error (missing THEN)"
run 'LET X = 5\nIF X = 5\nEXIT\n'

section "13. Edge cases: empty line, >12-token line, HELP, EXIT"
run '\none two three four five six seven eight nine ten eleven twelve thirteen fourteen\nHELP\nEXIT\n'

section "14. BOUNDARY: fill the chatbot pattern table (6 built-in + 34 taught = 40 = MAX_PATTERNS), 35th must fail"
{
  i=1
  while [ "$i" -le 34 ]; do echo "TEACH W$i reply number $i"; i=$((i+1)); done
  echo "TEACH ONEMORE this should fail, table full"
  echo "EXIT"
} | "$EMU2" tinymind.com

section "15. BOUNDARY: fill the fact table (32 = MAX_FACTS), 33rd must fail"
{
  i=1
  while [ "$i" -le 32 ]; do echo "FACT F$i"; i=$((i+1)); done
  echo "FACT ONEMORE"
  echo "EXIT"
} | "$EMU2" tinymind.com

section "16. BOUNDARY: fill the rule table (16 = MAX_RULES), 17th must fail"
{
  i=1
  while [ "$i" -le 16 ]; do echo "RULE F$i F$i F$i"; i=$((i+1)); done
  echo "RULE A B C"
  echo "EXIT"
} | "$EMU2" tinymind.com

section "17. v2: multi-character variables, incl. self-referential update"
run 'LET COUNTER = 1\nLET COUNTER = COUNTER + 1\nLET COUNTER = COUNTER + 1\nPRINT COUNTER\nEXIT\n'

section "18. v2: a real GOTO loop (line-numbered program), counting 1..5"
run '10 LET N = 1\n20 PRINT N\n30 LET N = N + 1\n40 IF N < 6 THEN GOTO 20\nRUN\nEXIT\n'

section "19. v2: PLIST, overwriting a line, deleting a line (bare number), NEW"
run '10 PRINT 1\n20 PRINT 2\nPLIST\n20 PRINT 99\n30 PRINT 3\nPLIST\n20\nPLIST\nNEW\nPLIST\nEXIT\n'

section "20. v2: END halts a running program early"
run '10 PRINT 1\n20 END\n30 PRINT 999\nRUN\nEXIT\n'

section "21. v2: GOTO to an undefined line, and GOTO outside of RUN"
run '10 PRINT 1\n20 GOTO 999\nRUN\nEXIT\n'
run 'GOTO 10\nEXIT\n'

section "22. v2: THINK before any learning, then after (Markov generation)"
run 'THINK\nEXIT\n'
run 'the quick brown fox jumps over the lazy dog\nthe cat sat on the mat and the dog ran away\nTHINK\nTHINK\nEXIT\n'

section "23. v2: ELIZA-style reflection (I/MY/ME -> YOU/YOUR)"
run 'I am feeling quite tired today\nmy brother is annoying me\nEXIT\n'

section "24. v2: best-match chatbot scoring -- a more recently TEACHed pattern wins"
run 'TEACH WEATHER Its just weather, nothing special.\nWEATHER TODAY\nTEACH TODAY Today is a fine day indeed!\nWEATHER TODAY\nEXIT\n'

section "25. v2: FULL persistence -- facts, rules, variables, program, chat patterns, AND the Markov model, all across a fresh process"
run 'FACT RAINING\nFACT COLD\nRULE RAINING COLD SNOWY\nLET SCORE = 42\n10 PRINT 7\n20 PRINT 8\nthe dog ran fast and the cat ran faster\nTEACH ROBOT Beep boop.\nSAVE\nEXIT\n'
run 'LOAD\nASK SNOWY\nPRINT SCORE\nPLIST\nROBOT\nTHINK\nEXIT\n'

section "26. v2 BOUNDARY: fill the variable table (40 = MAX_VARS), 41st must fail"
{
  i=1
  while [ "$i" -le 40 ]; do echo "LET V$i = $i"; i=$((i+1)); done
  echo "LET ONEMORE = 1"
  echo "PRINT V1"
  echo "EXIT"
} | "$EMU2" tinymind.com

section "27. v2 SAFETY: a genuine infinite GOTO loop must hit the step limit, not hang"
{
  printf '10 PRINT 1\n20 GOTO 10\nRUN\nEXIT\n' | "$EMU2" tinymind.com | tail -c 200
}

section "28. v3: signed numbers -- negative literal, arithmetic, signed IF"
run 'LET X = -5\nPRINT X\nLET Y = X + 10\nPRINT Y\nLET Z = 0 - 7\nPRINT Z\nIF X < 0 THEN PRINT 1\nEXIT\n'

section "29. v3: GOSUB/RETURN -- a subroutine called twice, and IF...THEN GOSUB"
run '10 LET N = 1\n20 GOSUB 100\n30 LET N = 2\n40 GOSUB 100\n50 END\n100 PRINT N\n110 RETURN\nRUN\nEXIT\n'
run '10 LET X = 5\n20 IF X = 5 THEN GOSUB 100\n30 END\n100 PRINT 999\n110 RETURN\nRUN\nEXIT\n'

section "30. v3: FOR/NEXT -- counting up, counting down with STEP -1, custom STEP, and nested loops"
run '10 FOR I = 1 TO 5\n20 PRINT I\n30 NEXT I\nRUN\nEXIT\n'
run '10 FOR I = 5 TO 1 STEP -1\n20 PRINT I\n30 NEXT I\nRUN\nEXIT\n'
run '10 FOR I = 0 TO 10 STEP 2\n20 PRINT I\n30 NEXT I\nRUN\nEXIT\n'
run '10 FOR I = 1 TO 3\n20 FOR J = 1 TO 2\n30 PRINT I\n40 PRINT J\n50 NEXT J\n60 NEXT I\nRUN\nEXIT\n'

section "31. v3: two-keyword TEACH -- a fully-satisfied 2-keyword pattern beats a 1-keyword one"
run 'TEACH RAINING+COLD Bundle up, its a rough one out there.\nTEACH RAINING Just some rain, no big deal.\nIT IS RAINING TODAY\nIT IS RAINING AND COLD\nEXIT\n'

section "32. v3 ERRORS: RETURN without GOSUB, NEXT without FOR, NEXT/FOR variable mismatch"
run '10 RETURN\nRUN\nEXIT\n'
run '10 NEXT I\nRUN\nEXIT\n'
run '10 FOR I = 1 TO 3\n20 NEXT J\nRUN\nEXIT\n'

section "33. v3 SAFETY: GOSUB stack overflow (infinite recursion) must fail cleanly, not hang"
{
  printf '10 GOSUB 20\n20 GOSUB 20\nRUN\nEXIT\n' | timeout 15 "$EMU2" tinymind.com | tail -c 150
}

section "34. v3: parsing rigor -- IF relop must be exactly one character (== is rejected, = still works)"
run 'LET X = 5\nIF X == 5 THEN PRINT 1\nIF X = 5 THEN PRINT 2\nEXIT\n'

cd /
rm -rf "$WORKDIR"


