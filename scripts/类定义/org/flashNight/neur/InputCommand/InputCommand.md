import org.flashNight.neur.InputCommand.InputCommandTest;

var test:InputCommandTest = new InputCommandTest();
test.runTests();



=== Running InputCommand Optimization Tests ===

--- Setting up test environment ---
[TrieDFA] Compiled: 5 patterns, 9 states, alphabet=18, maxPatternLen=2
[CommandDFA] Built with 5 commands, 9 states
[CommandRegistry] Compiled: 5 commands
Registered commands: 5
===== CommandDFA Dump =====
Commands: 5
States: 9
  [1] 波动拳 = ↘A -> 波动拳 (priority: 10)
  [2] 诛杀步 = →→ -> 诛杀步 (priority: 5)
  [3] 后撤步 = Shift+← -> 后撤步 (priority: 5)
  [4] 燃烧指节 = →B -> 燃烧指节 (priority: 8)
  [5] 能量喷泉 = ↓B -> 能量喷泉1段 (priority: 7)
===========================

--- Test: InputHistoryBuffer ---
[PASS] Buffer created successfully
[PASS] New buffer is empty
[PASS] Event count is 0
[PASS] Frame count is 0
[PASS] Event count after first frame (got: 2)
[PASS] Frame count after first frame (got: 1)
[PASS] Event count after second frame (got: 3)
[PASS] Frame count after second frame (got: 2)
[PASS] Sequence length is 3 (got: 3)
[PASS] First event is DOWN
[PASS] Second event is FORWARD
[PASS] Third event is A_PRESS
[PASS] Window start for 1 frame (got: 2)
[PASS] Window start for 2 frames (got: 0)
[PASS] Buffer is empty after clear
[PASS] Event count is 0 after clear
[FAIL] Frame count limited to 3 (got: 4)
[FAIL] Oldest events discarded, first is 3 (got: 1)
InputHistoryBuffer tests completed

--- Test: CommandDFA.updateWithHistory ---
[PASS] No command after first input
[PASS] Command recognized after complete input
[PASS] Recognized command is 波动拳 (got: 波动拳)
[PASS] No repeated trigger on same match
[PASS] 诛杀步 recognized
[PASS] Recognized command is 诛杀步 (got: 诛杀步)
CommandDFA.updateWithHistory tests completed

--- Test: CommandDFA.updateFast ---
[PASS] State advanced after DOWN_FORWARD
[PASS] No command yet
[PASS] Command recognized with updateFast
[PASS] 波动拳 recognized with updateFast (got: 波动拳)
[PASS] State reset after timeout
CommandDFA.updateFast tests completed

--- Test: CommandDFA.updateWithDynamicTimeout ---
  Depth after FORWARD: 1
[PASS] State not reset within dynamic timeout
[PASS] State reset after dynamic timeout exceeded
CommandDFA.updateWithDynamicTimeout tests completed

--- Test: CommandDFA.getAvailableMoves ---
[PASS] Root state has available moves (got: 5)
  Available moves from root:
    → -> state 5
    ↓ -> state 7
    ↘ -> state 1
    →→ -> state 3 [ACCEPT]
    Shift+← -> state 4 [ACCEPT]
[PASS] Move has symbol
[PASS] Move has name
[PASS] Move has nextState
CommandDFA.getAvailableMoves tests completed

--- Test: InputReplayAnalyzer ---
  Sequence length: 4
  Total matches: 2
[PASS] Sequence length is 4
[PASS] At least 2 matches found (got: 2)
  Found: 波动拳 @ pos 0
  Found: 诛杀步 @ pos 3
[PASS] 波动拳 found in analysis
[PASS] 诛杀步 found in analysis
[PASS] Stats contain 波动拳
[PASS] Stats contain 诛杀步
[PASS] countMatches returns correct count
[PASS] findCommandPositions found 波动拳

===== Input Replay Analysis Report =====
Sequence length: 4 events
Total matches: 2

--- Command Statistics ---
  诛杀步: 1 times
  波动拳: 1 times

--- Timeline ---
  [0] 波动拳
  [3] 诛杀步

--- Detailed Commands ---
  0. 波动拳 @ pos 0-2 (↘A) priority=10
  1. 诛杀步 @ pos 3-4 (→→) priority=5
=========================================
InputReplayAnalyzer tests completed

--- Test: Integration ---
[PASS] History enabled
[PASS] History buffer created
  Sampled events: ↘A
[PASS] History info shows enabled
[PASS] History has events
[PASS] History has 1 frame
  History frames: 3
  History events: 3
  Matches in window: 1
Integration tests completed

=== INPUT COMMAND TEST FINAL REPORT ===
Tests Passed: 46
Tests Failed: 2
Success Rate: 96%
SOME TESTS FAILED!
========================================
