import org.flashNight.hana.Gobang.GobangAI;
import org.flashNight.hana.Gobang.GobangBoard;
import org.flashNight.hana.Gobang.GobangEval;
import org.flashNight.hana.Gobang.GobangMinmax;
import org.flashNight.neur.Server.ServerManager;

class org.flashNight.hana.Gobang.GobangTrainer {

    private var _problems:Array;
    private var _results:Array;
    private var _currentIndex:Number;
    private var _running:Boolean;
    private var _onComplete:Function;
    private var _categoryStats:Object;
    private var _skipped:Number;

    public function GobangTrainer() {
        _problems = [];
        _results = [];
        _categoryStats = {};
        _currentIndex = 0;
        _running = false;
        _skipped = 0;
    }

    public function addProblem(p:Object):Void {
        _problems.push(p);
    }

    public function addProblems(arr:Array):Void {
        for (var i:Number = 0; i < arr.length; i++) {
            _problems.push(arr[i]);
        }
    }

    // ===== 内置题库 =====

    public function loadBuiltinProblems():Void {
        // pad: 边缘填充棋子，确保 histLen > 9 跳过开局库
        // 放在第 0 行偶数列 + 第 14 行偶数列，不影响中心区域战术
        var pad:Array = [
            [0,0,1],[0,2,-1],[0,4,1],[0,6,-1],[0,8,1],[0,10,-1],
            [0,12,1],[0,14,-1],[14,0,1],[14,2,-1]
        ];
        // pad2: 需要更多填充时（题目自带棋子 < 3 手）
        var pad2:Array = pad.concat([[14,4,1],[14,6,-1],[14,8,1],[14,10,-1]]);

        // ===== must_block: 必须堵四/堵五 =====

        addProblem({name: "mb_open_four_h", category: "must_block",
            moves: pad.concat([[7,5,1],[7,6,1],[7,7,1],[7,8,1],[8,5,-1]]),
            role: -1, difficulty: 100, frameBudget: 8,
            expectedMoves: [[7,4],[7,9]],
            description: "堵水平四连"});

        addProblem({name: "mb_open_four_diag", category: "must_block",
            moves: pad.concat([[4,4,1],[5,5,1],[6,6,1],[7,7,1],[8,5,-1]]),
            role: -1, difficulty: 100, frameBudget: 8,
            expectedMoves: [[3,3],[8,8]],
            description: "堵对角线四连"});

        addProblem({name: "mb_gap_five_diag", category: "must_block",
            moves: pad.concat([[5,9,1],[6,8,1],[7,7,1],[9,5,1],[8,5,-1]]),
            role: -1, difficulty: 100, frameBudget: 8,
            expectedMoves: [[8,6]],
            description: "P2堵对角线跳五(8,6)"});

        addProblem({name: "mb_dual_four_intersection", category: "must_block",
            moves: [[7,6,1],[7,9,-1],[6,7,1],[8,5,-1],[5,8,1],[0,0,-1],
                    [3,9,1],[0,14,-1],[5,9,1],[14,0,-1],[6,9,1],[14,14,-1],[3,10,1]],
            role: -1, difficulty: 100, frameBudget: 8,
            expectedMoves: [[4,9]],
            description: "堵双四交叉点(4,9)"});

        addProblem({name: "mb_vertical_open_three", category: "must_block",
            moves: [[4,7,1],[9,7,-1],[7,7,1],[6,5,-1],[6,7,1],[3,7,-1],
                    [7,6,1],[8,5,-1],[7,5,1],[14,14,-1]],
            role: -1, difficulty: 100, frameBudget: 8,
            expectedMoves: [[7,4],[7,8]],
            description: "P4a堵垂直活三(7,5-7,6-7,7)两端"});

        // ===== defense: 中盘防守 =====

        addProblem({name: "def_diagonal_three_center", category: "defense",
            moves: pad.concat([[5,9,1],[6,8,1],[7,7,1],[8,6,-1]]),
            role: -1, difficulty: 100, frameBudget: 8,
            expectedMoves: [[8,6],[4,10]],
            description: "堵对角线三连，靠近中心"});

        addProblem({name: "def_h_gap_four", category: "defense",
            moves: [[6,7,1],[9,7,-1],[7,7,1],[7,6,-1],[8,7,1],[7,8,-1],
                    [3,7,1],[0,0,-1],[5,9,1],[14,0,-1],[5,5,1],[0,14,-1]],
            role: -1, difficulty: 100, frameBudget: 8,
            expectedMoves: [[5,7],[4,7]],
            description: "堵水平跳四(3,7-gap-6,7-7,7-8,7)"});

        addProblem({name: "def_h_live_four_gap", category: "defense",
            moves: pad.concat([[4,7,1],[7,7,1],[6,7,1],[10,10,1],
                    [4,8,-1],[7,6,-1],[10,4,1]]),
            role: -1, difficulty: 100, frameBudget: 8,
            expectedMoves: [[5,7],[8,7]],
            description: "P4a堵水平活四跳(4,7-gap-6,7-7,7)"});

        addProblem({name: "def_diag_open_three_main", category: "defense",
            moves: pad.concat([[5,8,1],[4,7,1],[3,6,1],[8,5,-1]]),
            role: -1, difficulty: 100, frameBudget: 8,
            expectedMoves: [[2,5],[6,9]],
            description: "P4a堵主对角线活三(3,6-4,7-5,8)"});

        addProblem({name: "def_p4a_open_three_dual_four", category: "defense",
            moves: pad.concat([[4,5,1],[5,6,1],[6,7,1],[8,5,-1]]),
            role: -1, difficulty: 100, frameBudget: 8,
            expectedMoves: [[3,4],[7,8]],
            description: "P4a堵对角线活三，两端延伸均成四"});

        addProblem({name: "def_row5_gap_four_complex", category: "defense",
            moves: [[8,7,1],[10,8,-1],[9,3,1],[9,8,-1],[7,8,1],[11,5,-1],
                    [7,5,1],[7,9,-1],[5,7,1],[4,8,-1],[4,5,1],[8,9,-1],
                    [7,3,1],[7,7,-1],[5,5,1]],
            role: -1, difficulty: 100, frameBudget: 8,
            expectedMoves: [[6,5]],
            description: "复杂中盘堵跳四(4,5-5,5-gap-7,5)于(6,5)"});

        addProblem({name: "def_gap_five_vertical", category: "defense",
            moves: [[5,7,1],[7,8,-1],[5,4,1],[5,8,-1],[8,7,1],[4,7,-1],
                    [7,6,1],[4,2,-1],[4,8,1],[3,10,-1],[9,6,1],[7,4,-1],
                    [9,7,1],[6,7,-1],[9,8,1]],
            role: -1, difficulty: 100, frameBudget: 8,
            expectedMoves: [[6,5]],
            description: "P2堵对角跳五(5,4-7,6-8,7-9,8)于(6,5)"});

        addProblem({name: "def_opening_vertical_three", category: "defense",
            moves: pad.concat([[7,8,1],[6,8,1],[5,8,1],[7,7,-1],[8,7,-1]]),
            role: -1, difficulty: 100, frameBudget: 8,
            expectedMoves: [[4,8],[8,8]],
            description: "开局防守：堵col8垂直三连"});

        // ===== double_three: 双活三 =====

        addProblem({name: "dt_cross_center", category: "double_three",
            moves: pad.concat([[7,6,1],[7,8,1],[6,7,1],[8,7,1],[6,6,-1],[8,8,-1]]),
            role: 1, difficulty: 100, frameBudget: 8,
            expectedMoves: [[7,7]],
            description: "中心十字双活三(7,7)"});

        addProblem({name: "dt_block_opponent", category: "double_three",
            moves: [[7,6,1],[0,0,-1],[7,8,1],[14,0,-1],[6,7,1],[0,14,-1],
                    [8,7,1],[14,14,-1],[14,12,1],[14,10,-1]],
            role: -1, difficulty: 100, frameBudget: 8,
            expectedMoves: [[7,7]],
            description: "白棋必须堵黑棋双活三交叉点(7,7)"});

        // ===== vcf: 连续冲四胜 =====

        addProblem({name: "vcf_h_extend_five", category: "vcf",
            moves: pad.concat([[7,4,1],[7,5,1],[7,6,1],[7,3,1],
                    [6,4,-1],[6,5,-1],[6,6,-1],[8,4,-1]]),
            role: 1, difficulty: 100, frameBudget: 8,
            expectedMoves: [[7,7],[7,2]],
            description: "水平VCF：冲四连五"});

        addProblem({name: "vcf_vct_open_four", category: "vcf",
            moves: pad.concat([[7,5,1],[7,6,1],[7,7,1],[7,8,1],
                    [0,1,-1],[0,3,-1],[0,5,-1],[0,7,-1]]),
            role: 1, difficulty: 100, frameBudget: 8,
            expectedMoves: [[7,4],[7,9]],
            description: "VCT找胜：水平四连延伸成五"});

        // ===== mid_game: 中盘综合判断 =====

        addProblem({name: "mid_complex_diagonal", category: "mid_game",
            moves: [[6,8,1],[7,9,-1],[7,7,1],[7,11,-1],[9,8,1],[8,8,-1],
                    [6,6,1],[6,4,-1],[8,7,1],[5,4,-1],[9,4,1],[9,7,-1],
                    [8,6,1],[9,6,-1],[5,8,1]],
            role: -1, difficulty: 100, frameBudget: 8,
            expectedMoves: [],
            description: "复杂中盘：黑棋对角三连(6,8-7,7-8,6)，Rapfi判定最优防守"});

        addProblem({name: "mid_multi_threat_coverage", category: "mid_game",
            moves: [[7,5,1],[0,0,-1],[7,9,1],[0,14,-1],[5,7,1],[14,0,-1],
                    [9,7,1],[1,12,-1],[14,14,1],[12,1,-1],[14,13,1]],
            role: -1, difficulty: 100, frameBudget: 8,
            expectedMoves: [],
            description: "多威胁覆盖：Rapfi判定最优防守"});

        // ===== vcf_defense: VCF 防守 =====

        addProblem({name: "vcf_def_block_four_extend", category: "vcf_defense",
            moves: pad.concat([[7,4,1],[7,5,1],[7,6,1],[7,7,1],
                    [6,4,-1],[6,5,-1],[8,6,-1]]),
            role: -1, difficulty: 100, frameBudget: 8,
            expectedMoves: [[7,3],[7,8]],
            description: "防VCF：白棋必须堵黑棋水平四连两端"});

        addProblem({name: "vcf_def_diagonal_rush", category: "vcf_defense",
            moves: pad.concat([[4,4,1],[5,5,1],[6,6,1],[7,7,1],
                    [4,5,-1],[5,6,-1],[8,9,-1]]),
            role: -1, difficulty: 100, frameBudget: 8,
            expectedMoves: [[3,3],[8,8]],
            description: "防VCF：堵对角线四连"});

        // ===== gap_four: 跳四识别 =====

        addProblem({name: "gap_four_h_center", category: "gap_four",
            moves: pad.concat([[7,4,1],[7,5,1],[7,7,1],[7,8,1],
                    [6,4,-1],[6,5,-1],[8,7,-1]]),
            role: 1, difficulty: 100, frameBudget: 8,
            expectedMoves: [[7,6]],
            description: "黑棋补跳四缺口(7,6)成五"});

        addProblem({name: "gap_four_diag", category: "gap_four",
            moves: pad.concat([[3,3,1],[4,4,1],[6,6,1],[7,7,1],
                    [3,4,-1],[4,5,-1],[8,7,-1]]),
            role: 1, difficulty: 100, frameBudget: 8,
            expectedMoves: [[5,5]],
            description: "对角线跳四缺口(5,5)成五"});

        // ===== anti_diag: 反对角线 =====

        addProblem({name: "mb_anti_diag_four", category: "must_block",
            moves: pad.concat([[7,7,1],[8,6,1],[9,5,1],[10,4,1],[6,9,-1]]),
            role: -1, difficulty: 100, frameBudget: 8,
            expectedMoves: [[6,8],[11,3]],
            description: "堵反对角线四连"});

        // ===== tactical: 战术正确性 =====

        addProblem({name: "tac_never_drop_forced", category: "tactical",
            moves: pad.concat([[7,6,1],[7,8,1],[6,7,1],[8,7,1],[14,4,-1],[14,6,-1]]),
            role: -1, difficulty: 30, frameBudget: 8,
            expectedMoves: [[7,7]],
            description: "低难度也不能drop战术必走点(7,7)"});

        addProblem({name: "tac_five_over_defense", category: "tactical",
            moves: pad.concat([[7,5,1],[7,6,1],[7,7,1],[7,8,1],
                    [6,5,-1],[6,6,-1],[6,7,-1]]),
            role: 1, difficulty: 100, frameBudget: 8,
            expectedMoves: [[7,4],[7,9]],
            description: "有成五机会时必须走成五而非防守"});

        trace("[Trainer] Loaded " + _problems.length + " built-in problems");
    }

    // ===== 运行引擎 =====

    // 等待连接最大帧数（~10 秒 @30fps）
    private static var CONNECT_WAIT_MAX:Number = 300;
    private var _waitFrames:Number;
    private var _waitClip:MovieClip;

    public function run(onComplete:Function):Void {
        if (_running) return;
        _running = true;
        _currentIndex = 0;
        _results = [];
        _categoryStats = {};
        _skipped = 0;
        _onComplete = onComplete;

        // 如果 Socket 已连接，立即开始；否则等待连接
        if (ServerManager.getInstance().isSocketConnected) {
            _startRun();
        } else {
            trace("[Trainer] Waiting for XMLSocket connection...");
            _waitFrames = 0;
            var self:GobangTrainer = this;
            _waitClip = _root.createEmptyMovieClip("trainerWait", _root.getNextHighestDepth());
            _waitClip.onEnterFrame = function():Void {
                self._waitForConnection();
            };
        }
    }

    private function _waitForConnection():Void {
        _waitFrames++;
        if (ServerManager.getInstance().isSocketConnected) {
            _waitClip.removeMovieClip();
            _waitClip = null;
            trace("[Trainer] Socket connected after " + _waitFrames + " frames");
            _startRun();
        } else if (_waitFrames >= CONNECT_WAIT_MAX) {
            _waitClip.removeMovieClip();
            _waitClip = null;
            trace("[Trainer] Socket not connected after " + CONNECT_WAIT_MAX + " frames, running without Rapfi");
            _startRun();
        }
    }

    private function _startRun():Void {
        trace("==============================");
        trace("[Trainer] Starting tactical evaluation (" + _problems.length + " problems)");
        trace("==============================");
        runNext();
    }

    private function runNext():Void {
        if (_currentIndex >= _problems.length) {
            _running = false;
            printReport();
            if (_onComplete != undefined) {
                _onComplete(_results, _categoryStats);
            }
            return;
        }

        var problem:Object = _problems[_currentIndex];
        trace("[Trainer] (" + (_currentIndex + 1) + "/" + _problems.length + ") " + problem.name);

        // 设置局面
        var ai:GobangAI = new GobangAI(problem.role, problem.difficulty);
        var brd:GobangBoard = ai.getBoardRef();
        var ev:GobangEval = ai.getEvalRef();
        var moves:Array = problem.moves;
        for (var i:Number = 0; i < moves.length; i++) {
            var m:Array = moves[i];
            brd.put(m[0], m[1], m[2]);
            ev.move(m[0], m[1], m[2]);
        }
        // 修正 role：确保 board.role 与 problem.role 一致
        // GobangBoard.put 会自动翻转 role，所以 board.role 取决于落子总数奇偶
        // 如果不匹配，强制修正（board.role 是 public）
        if (brd.role !== problem.role) {
            brd.role = problem.role;
        }

        // async 模式：模拟真实对局帧预算
        var budget:Number = (problem.frameBudget != undefined) ? problem.frameBudget : 8;
        ai.aiMoveStart(budget);

        var maxFrames:Number = 200;
        var frames:Number = 0;
        var stepResult:Object = null;
        while (frames < maxFrames) {
            stepResult = ai.aiMoveStep(budget);
            frames++;
            if (stepResult.done) break;
        }

        var localX:Number = (stepResult != null && stepResult.done) ? stepResult.x : -1;
        var localY:Number = (stepResult != null && stepResult.done) ? stepResult.y : -1;
        var localScore:Number = (stepResult != null && stepResult.done) ? stepResult.score : 0;
        var localPhase:String = (stepResult != null && stepResult.done) ? stepResult.phaseLabel : "timeout";

        // 开局库命中 → 跳过
        if (localPhase === "opening") {
            trace("[Trainer] [SKIP] " + problem.name + " -- hit opening book");
            _skipped++;
            _currentIndex++;
            runNext();
            return;
        }

        // Rapfi 验证（始终用原题 moves 快照，不从 AI 落子后的棋盘反推）
        var payload:Object = {moves: problem.moves, timeLimit: 5000};

        var self:GobangTrainer = this;
        var idx:Number = _currentIndex;
        var prob:Object = problem;
        var lx:Number = localX;
        var ly:Number = localY;
        var ls:Number = localScore;
        var lp:String = localPhase;

        var cb:Function = function(response:Object):Void {
            self._onRapfiResponse(idx, prob, lx, ly, ls, lp, response);
        };

        _currentIndex++; // 必须在 sendTaskWithCallback 之前递增，因为 socket 未连接时 callback 会同步调用
        ServerManager.getInstance().sendTaskWithCallback("gomoku_eval", payload, null, cb);
    }

    private function _onRapfiResponse(idx:Number, problem:Object,
                                       localX:Number, localY:Number,
                                       localScore:Number, localPhase:String,
                                       response:Object):Void {
        var result:Object = {
            name: problem.name,
            category: problem.category,
            localMove: {x: localX, y: localY, score: localScore, phase: localPhase},
            rapfiMove: null,
            expectedMoves: problem.expectedMoves,
            localPass: false,
            rapfiPass: false,
            rapfiError: null
        };

        if (response.success && response.result != undefined) {
            var r:Object = response.result;
            result.rapfiMove = {x: r.x, y: r.y, score: r.score, depth: r.depth};
            if (problem.expectedMoves.length > 0) {
                result.rapfiPass = _isExpectedMove(r.x, r.y, problem.expectedMoves);
            } else {
                result.rapfiPass = true;
            }
        } else {
            result.rapfiError = (response.error != undefined) ? response.error : "Unknown error";
        }

        if (problem.expectedMoves.length > 0) {
            result.localPass = _isExpectedMove(localX, localY, problem.expectedMoves);
        } else {
            // 无预定义答案 → 与 Rapfi 一致则 pass
            if (result.rapfiMove != null) {
                result.localPass = (localX === result.rapfiMove.x && localY === result.rapfiMove.y);
            }
        }

        // 分类统计
        var cat:String = problem.category;
        if (_categoryStats[cat] == undefined) {
            _categoryStats[cat] = {total: 0, localPass: 0, rapfiPass: 0, rapfiError: 0};
        }
        _categoryStats[cat].total++;
        if (result.localPass) _categoryStats[cat].localPass++;
        if (result.rapfiPass) _categoryStats[cat].rapfiPass++;
        if (result.rapfiError != null) _categoryStats[cat].rapfiError++;

        // 日志
        var status:String = result.localPass ? "PASS" : "FAIL";
        var rapfiStr:String = result.rapfiMove
            ? "(" + result.rapfiMove.x + "," + result.rapfiMove.y + ")"
            : (result.rapfiError != null ? result.rapfiError : "?");
        var expectedStr:String = _movesToString(problem.expectedMoves);
        trace("[Trainer] [" + status + "] " + problem.name
            + " | Local:(" + localX + "," + localY + ") " + localPhase
            + " | Rapfi:" + rapfiStr
            + ((expectedStr.length > 0) ? " | Expected:" + expectedStr : ""));

        _results.push(result);
        runNext();
    }

    // ===== 工具方法 =====

    private function _isExpectedMove(x:Number, y:Number, expected:Array):Boolean {
        if (expected == undefined || expected.length == 0) return true;
        for (var i:Number = 0; i < expected.length; i++) {
            if (expected[i][0] == x && expected[i][1] == y) return true;
        }
        return false;
    }

    private function _movesToString(moves:Array):String {
        if (moves == undefined || moves.length == 0) return "";
        var s:String = "";
        for (var i:Number = 0; i < moves.length; i++) {
            if (i > 0) s += "|";
            s += "(" + moves[i][0] + "," + moves[i][1] + ")";
        }
        return s;
    }

    private function printReport():Void {
        var totalRun:Number = _results.length;
        var totalLocalPass:Number = 0;
        var totalRapfiPass:Number = 0;
        var totalRapfiError:Number = 0;
        for (var i:Number = 0; i < _results.length; i++) {
            if (_results[i].localPass) totalLocalPass++;
            if (_results[i].rapfiPass) totalRapfiPass++;
            if (_results[i].rapfiError != null) totalRapfiError++;
        }
        trace("==============================");
        trace("[Trainer] SUMMARY REPORT");
        trace("==============================");
        trace("Total: " + _problems.length + " | Run: " + totalRun
            + " | Skipped: " + _skipped + " (opening book)");
        if (totalRun > 0) {
            trace("Local AI accuracy: " + totalLocalPass + "/" + totalRun
                + " (" + Math.round(totalLocalPass / totalRun * 100) + "%)");
            if (totalRapfiError < totalRun) {
                var rapfiRun:Number = totalRun - totalRapfiError;
                trace("Rapfi accuracy:    " + totalRapfiPass + "/" + rapfiRun
                    + " (" + Math.round(totalRapfiPass / rapfiRun * 100) + "%)");
            }
            if (totalRapfiError > 0) {
                trace("Rapfi errors:      " + totalRapfiError + " (engine unavailable)");
            }
        }
        trace("--- Per-category ---");
        for (var cat:String in _categoryStats) {
            var s:Object = _categoryStats[cat];
            var line:String = "  " + cat + ": local " + s.localPass + "/" + s.total;
            if (s.rapfiError < s.total) {
                line += " | rapfi " + s.rapfiPass + "/" + (s.total - s.rapfiError);
            }
            trace(line);
        }
        trace("==============================");
    }
}
