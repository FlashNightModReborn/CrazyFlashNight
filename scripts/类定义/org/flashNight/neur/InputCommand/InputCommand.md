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
[PASS] Frame count limited to 3 (got: 3)
[PASS] Oldest events discarded, first is 3 (got: 3)
InputHistoryBuffer tests completed

--- Test: InputHistoryBuffer Advanced ---
[PASS] Event count limited to capacity (got: 7)
[PASS] getWindowStartByTime returns correct position (got: 1)
[PASS] getWindowStartByTime returns end for future timestamp (got: 3)
[PASS] getFrameRange start correct (got: 2)
[PASS] getFrameRange end correct (got: 4)
[PASS] getFrameRange empty when from==to
[PASS] getFrameRange empty when from>to
[PASS] Event count correct after multiple clear (got: 2)
[PASS] Frame count correct after multiple clear (got: 1)
[PASS] Sequence correct after multiple clear
InputHistoryBuffer Advanced tests completed

--- Test: InputSampler DoubleTap Basic ---
[PASS] Frame 1: No DOUBLE_TAP on first press
[PASS] Frame 1: FORWARD event present
[PASS] Frame 2: No DOUBLE_TAP while holding
[PASS] Frame 3: No DOUBLE_TAP while still holding
[PASS] Frame 4: No DOUBLE_TAP on release
[PASS] Frame 4: No FORWARD after release
[PASS] Frame 7: DOUBLE_TAP_FORWARD triggered on second press within window
[PASS] Frame 8: No repeated DOUBLE_TAP while holding
[PASS] Frame 9: No repeated DOUBLE_TAP while still holding
InputSampler DoubleTap Basic tests completed

--- Test: InputSampler DoubleTap Timeout ---
[PASS] No DOUBLE_TAP when exceeding window (13 frames gap)
[PASS] FORWARD event still present
InputSampler DoubleTap Timeout tests completed

--- Test: InputSampler DoubleTap Back ---
[PASS] Frame 1: BACK event present
[PASS] Frame 1: No DOUBLE_TAP_BACK on first press
[PASS] DOUBLE_TAP_BACK triggered within window
[PASS] DOUBLE_TAP_BACK works when facing left
InputSampler DoubleTap Back tests completed

--- Test: InputSampler DoubleTap Decoupled from doubleTapRunDirection ---
  Frame 1: DOUBLE_TAP_FORWARD detected
[PASS] Exactly 1 DOUBLE_TAP on edge (0→1), no repeated events during hold (got: 1)
  Frame 1: DOUBLE_TAP_BACK detected
[PASS] Exactly 1 DOUBLE_TAP_BACK on edge (0→-1), no repeated events during hold (got: 1)
[PASS] DoubleTap still works correctly with proper press-release-press sequence
InputSampler DoubleTap Decoupled tests completed

--- Test: InputSampler C Key Edge Detection ---
[PASS] Frame 1: No C_PRESS when C key is not pressed
[PASS] Frame 2: C_PRESS triggered on false→true edge
[PASS] Frame 3: No C_PRESS while holding (first hold frame)
[PASS] Frame 4: No C_PRESS while still holding
[PASS] Frame 5: No C_PRESS on extended hold
[PASS] Frame 6: No C_PRESS on release (true→false)
[PASS] Frame 7: No C_PRESS when key remains released
[PASS] Frame 8: C_PRESS triggered on second press
  C_PRESS detected at frame 1
  C_PRESS detected at frame 11
[PASS] Total C_PRESS count should be exactly 2 (got: 2)
InputSampler C Key Edge Detection tests completed

--- Test: CommandDFA.updateWithHistory ---
[PASS] No command after first input
[PASS] Command recognized after complete input
[PASS] Recognized command is 波动拳 (got: 波动拳)
[PASS] No repeated trigger on same match
[PASS] 诛杀步 recognized
[PASS] Recognized command is 诛杀步 (got: 诛杀步)
CommandDFA.updateWithHistory tests completed

--- Test: CommandDFA Prefix Conflict ---
[TrieDFA] Compiled: 2 patterns, 4 states, alphabet=18, maxPatternLen=3
[CommandDFA] Built with 2 commands, 4 states
  Prefix conflict DFA built with 2 commands
[PASS] Short pattern recognized
[PASS] Recognized 短招 when only short input (got: 短招)
[PASS] Long pattern recognized
[PASS] Recognized 长招 when full input (got: 长招)
[PASS] Long pattern endPos > short pattern endPos
[TrieDFA] Compiled: 2 patterns, 3 states, alphabet=18, maxPatternLen=2
[CommandDFA] Built with 2 commands, 3 states
[PASS] Duplicate pattern matched
  Matched command: 高优先级
CommandDFA Prefix Conflict tests completed

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

--- Test: CommandDFA Dynamic Timeout Long Pattern ---
[TrieDFA] Compiled: 1 patterns, 5 states, alphabet=18, maxPatternLen=4
[CommandDFA] Built with 1 commands, 5 states
  Depth progression: 1 -> 2 -> 3
[PASS] Long pattern state preserved with 8 empty frames at depth 3
[PASS] Long pattern completed after long pause
[PASS] Recognized 长招 (got: 长招)
[PASS] State reset after exceeding dynamic timeout for depth 3
CommandDFA Dynamic Timeout Long Pattern tests completed

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

--- Test: InputReplayAnalyzer Filters ---
  High priority (>=8) matches: 1
[PASS] minPriority filter works correctly
  '移动' tag matches: 1
[PASS] filterTags finds 诛杀步 with '移动' tag
  移动类 mask: 0xc
  filterMask matches: 1
[PASS] filterMask works correctly
  Combined filter (空手 + priority>=6) matches: 2
[PASS] Combined filter returns results
[PASS] No matches with impossible filter
InputReplayAnalyzer Filters tests completed

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
[PASS] findMatchesInWindow found at least 1 match
[PASS] Window match found 波动拳 in constructed history
[PASS] Window match correctly identified 波动拳
[PASS] History cleared successfully
Integration tests completed

=== INPUT COMMAND TEST FINAL REPORT ===
Tests Passed: 104
Tests Failed: 0
Success Rate: 100%
ALL INPUT COMMAND TESTS PASSED!
========================================

