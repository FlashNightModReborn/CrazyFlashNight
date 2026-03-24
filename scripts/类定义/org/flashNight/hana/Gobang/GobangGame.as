import org.flashNight.hana.Gobang.GobangAI;
import org.flashNight.hana.Gobang.GobangConfig;
import org.flashNight.hana.Gobang.GobangShape;

class org.flashNight.hana.Gobang.GobangGame {

    private var CELL:Number;
    private var BOARD_SIZE:Number;
    private var MARGIN:Number;
    private var FRAME_BUDGET:Number;
    private var LINE_COLOR:Number;
    private var BG_COLOR:Number;
    private var BLACK_COLOR:Number;
    private var WHITE_COLOR:Number;
    private var HOVER_COLOR:Number;
    private var LAST_MOVE_COLOR:Number;
    private var CANDIDATE_COLOR:Number;

    private var _host:MovieClip;
    private var _rootMc:MovieClip;
    private var _boardMc:MovieClip;
    private var _piecesMc:MovieClip;
    private var _candidateMc:MovieClip;
    private var _hoverMc:MovieClip;
    private var _statusMc:MovieClip;
    private var _hitMc:MovieClip;

    private var _ai:GobangAI;
    private var _difficulty:Number;
    private var _aiRole:Number;
    private var _lastMoveX:Number;
    private var _lastMoveY:Number;
    private var _gameOver:Boolean;
    private var _aiThinking:Boolean;
    private var _inputLocked:Boolean;

    private var _aiStartTime:Number;
    private var _frameCount:Number;
    private var _lastStepResult:Object;

    private static var _counter:Number = 0;
    private var _instId:Number;

    // 阶段中文名映射
    private static var PHASE_NAMES:Object = null;

    private static function _initPhaseNames():Void {
        if (PHASE_NAMES !== null) return;
        PHASE_NAMES = {};
        PHASE_NAMES["vct"] = "\u7B97\u6740\u641C\u7D22";
        PHASE_NAMES["vct_win"] = "\u627E\u5230\u7B97\u6740!";
        PHASE_NAMES["minmax_win"] = "\u5FC5\u80DC!";
        PHASE_NAMES["counter"] = "\u53CD\u6740\u68C0\u6D4B";
        PHASE_NAMES["done"] = "\u5B8C\u6210";
        PHASE_NAMES["no_move"] = "\u65E0\u53EF\u7528\u8D70\u6CD5";
        PHASE_NAMES["opening"] = "\u5F00\u5C40\u5E93";
    }

    private static function phaseName(label:String):String {
        _initPhaseNames();
        // minmax_d2, minmax_d4 等动态标签
        if (label.indexOf("minmax_d") === 0) {
            var d:String = label.substr(8);
            return "\u641C\u7D22\u6DF1\u5EA6" + d;
        }
        var name:String = PHASE_NAMES[label];
        if (name !== undefined) return name;
        return label;
    }

    function GobangGame(host:MovieClip, config:Object) {
        _counter++;
        _instId = _counter;
        _host = host;

        CELL = (config != null && config.cell > 0) ? config.cell : 28;
        BOARD_SIZE = 15;
        MARGIN = (config != null && config.margin != undefined) ? config.margin : 20;
        FRAME_BUDGET = (config != null && config.frameBudget > 0) ? config.frameBudget : 16;
        LINE_COLOR = 0x333333;
        BG_COLOR = 0xDEB887;
        BLACK_COLOR = 0x111111;
        WHITE_COLOR = 0xEEEEEE;
        HOVER_COLOR = 0x66CC66;
        LAST_MOVE_COLOR = 0xFF3333;
        CANDIDATE_COLOR = 0x3399FF;

        _difficulty = (config != null && config.difficulty != undefined) ? config.difficulty : 80;
        _aiRole = (config != null && config.aiRole != undefined) ? config.aiRole : -1;

        _lastMoveX = -1;
        _lastMoveY = -1;
        _gameOver = false;
        _aiThinking = false;
        _inputLocked = false;
        _lastStepResult = null;

        _buildUI();
        _newGame();
    }

    private function _buildUI():Void {
        var depth:Number = _host.getNextHighestDepth();
        _rootMc = _host.createEmptyMovieClip("gobang_" + _instId, depth);

        var boardPixel:Number = (BOARD_SIZE - 1) * CELL;

        _boardMc = _rootMc.createEmptyMovieClip("board", 1);
        _drawBoard(_boardMc, boardPixel);

        _piecesMc = _rootMc.createEmptyMovieClip("pieces", 2);
        _candidateMc = _rootMc.createEmptyMovieClip("candidate", 3);
        _hoverMc = _rootMc.createEmptyMovieClip("hover", 4);

        _hitMc = _rootMc.createEmptyMovieClip("hit", 5);
        _hitMc.beginFill(0x000000, 0);
        _hitMc.moveTo(MARGIN - CELL / 2, MARGIN - CELL / 2);
        _hitMc.lineTo(MARGIN + boardPixel + CELL / 2, MARGIN - CELL / 2);
        _hitMc.lineTo(MARGIN + boardPixel + CELL / 2, MARGIN + boardPixel + CELL / 2);
        _hitMc.lineTo(MARGIN - CELL / 2, MARGIN + boardPixel + CELL / 2);
        _hitMc.endFill();

        // 状态栏：棋盘底部叠加半透明条
        _statusMc = _rootMc.createEmptyMovieClip("status", 6);
        var barH:Number = 52;
        var barY:Number = MARGIN + boardPixel + CELL / 2 - barH;
        var barX:Number = MARGIN - CELL / 2;
        var barW:Number = boardPixel + CELL;
        // 半透明背景
        _statusMc.beginFill(0x000000, 60);
        _statusMc.moveTo(barX, barY);
        _statusMc.lineTo(barX + barW, barY);
        _statusMc.lineTo(barX + barW, barY + barH);
        _statusMc.lineTo(barX, barY + barH);
        _statusMc.endFill();
        _statusMc.createTextField("tf", 1, barX + 6, barY + 2, barW - 12, barH - 4);
        var tf:TextField = _statusMc["tf"];
        var fmt:TextFormat = new TextFormat();
        fmt.font = "SimHei";
        fmt.size = 11;
        fmt.color = 0xFFFFFF;
        fmt.leading = 1;
        tf.setNewTextFormat(fmt);
        tf.selectable = false;
        tf.multiline = true;
        tf.wordWrap = true;

        var self:GobangGame = this;
        _createButton("btnNew", MARGIN + boardPixel + 15, MARGIN, 60, self, "_newGame");
        _createButton("btnUndo", MARGIN + boardPixel + 15, MARGIN + 35, 60, self, "_undoMove");

        _hitMc.onPress = function() { self._onBoardClick(); };
        _hitMc.onMouseMove = function() { self._onBoardHover(); };
    }

    private function _createButton(name:String, x:Number, y:Number, w:Number, scope:GobangGame, method:String):Void {
        var btn:MovieClip = _rootMc.createEmptyMovieClip(name, _rootMc.getNextHighestDepth());
        btn._x = x;
        btn._y = y;
        btn.beginFill(0x444444, 100);
        btn.moveTo(0, 0);
        btn.lineTo(w, 0);
        btn.lineTo(w, 25);
        btn.lineTo(0, 25);
        btn.endFill();
        btn.createTextField("lbl", 1, 2, 2, w - 4, 20);
        var tf:TextField = btn["lbl"];
        var fmt:TextFormat = new TextFormat();
        fmt.font = "SimHei";
        fmt.size = 12;
        fmt.color = 0xFFFFFF;
        fmt.align = "center";
        tf.setNewTextFormat(fmt);
        tf.selectable = false;
        if (name === "btnNew") {
            tf.text = "\u65B0\u6E38\u620F";
        } else {
            tf.text = "\u6094\u68CB";
        }
        btn.onPress = function() { scope[method](); };
    }

    private function _drawBoard(mc:MovieClip, boardPixel:Number):Void {
        mc.beginFill(BG_COLOR, 100);
        mc.moveTo(MARGIN - CELL / 2, MARGIN - CELL / 2);
        mc.lineTo(MARGIN + boardPixel + CELL / 2, MARGIN - CELL / 2);
        mc.lineTo(MARGIN + boardPixel + CELL / 2, MARGIN + boardPixel + CELL / 2);
        mc.lineTo(MARGIN - CELL / 2, MARGIN + boardPixel + CELL / 2);
        mc.endFill();

        mc.lineStyle(1, LINE_COLOR, 80);
        for (var i:Number = 0; i < BOARD_SIZE; i++) {
            mc.moveTo(MARGIN, MARGIN + i * CELL);
            mc.lineTo(MARGIN + (BOARD_SIZE - 1) * CELL, MARGIN + i * CELL);
            mc.moveTo(MARGIN + i * CELL, MARGIN);
            mc.lineTo(MARGIN + i * CELL, MARGIN + (BOARD_SIZE - 1) * CELL);
        }

        mc.lineStyle(0, 0, 0);
        var stars:Array = [3, 7, 11];
        for (var si:Number = 0; si < 3; si++) {
            for (var sj:Number = 0; sj < 3; sj++) {
                var sx:Number = MARGIN + stars[si] * CELL;
                var sy:Number = MARGIN + stars[sj] * CELL;
                mc.beginFill(LINE_COLOR, 100);
                _drawCircle(mc, sx, sy, 3);
                mc.endFill();
            }
        }
    }

    private function _drawCircle(mc:MovieClip, cx:Number, cy:Number, r:Number):Void {
        var k:Number = 0.41421356;
        var s:Number = 0.70710678;
        mc.moveTo(cx + r, cy);
        mc.curveTo(cx + r, cy + r * k, cx + r * s, cy + r * s);
        mc.curveTo(cx + r * k, cy + r, cx, cy + r);
        mc.curveTo(cx - r * k, cy + r, cx - r * s, cy + r * s);
        mc.curveTo(cx - r, cy + r * k, cx - r, cy);
        mc.curveTo(cx - r, cy - r * k, cx - r * s, cy - r * s);
        mc.curveTo(cx - r * k, cy - r, cx, cy - r);
        mc.curveTo(cx + r * k, cy - r, cx + r * s, cy - r * s);
        mc.curveTo(cx + r, cy - r * k, cx + r, cy);
    }

    // ===== 游戏流程 =====

    private function _newGame():Void {
        // 强制停止可能正在进行的 AI 思考
        delete _rootMc.onEnterFrame;
        _ai = new GobangAI(_aiRole, _difficulty);
        _lastMoveX = -1;
        _lastMoveY = -1;
        _gameOver = false;
        _aiThinking = false;
        _inputLocked = false;
        _lastStepResult = null;
        _candidateMc.clear();
        _renderAll();
        _updateStatus("\u9ED1\u68CB\u5148\u884C\uFF0C\u8BF7\u843D\u5B50");

        if (_aiRole === 1) {
            _startAIThink();
        }
    }

    private function _onBoardClick():Void {
        // 硬锁：AI 思考期间完全吞掉点击
        if (_inputLocked || _gameOver || _aiThinking) return;
        if (_ai.getCurrentRole() === _aiRole) return;

        var pos:Object = _mouseToGrid();
        if (pos === null) return;

        // 立即锁定输入，防止连点
        _inputLocked = true;

        var ok:Boolean = _ai.playerMove(pos.x, pos.y);
        if (!ok) {
            _inputLocked = false;
            return;
        }

        _lastMoveX = pos.x;
        _lastMoveY = pos.y;
        _hoverMc.clear();
        _renderAll();

        if (_ai.isGameOver()) {
            _inputLocked = false;
            _onGameOver();
            return;
        }

        _startAIThink();
    }

    private function _startAIThink():Void {
        _aiThinking = true;
        _inputLocked = true;
        _aiStartTime = getTimer();
        _frameCount = 0;
        _lastStepResult = null;
        _candidateMc.clear();
        _ai.aiMoveStart();
        _updateStatus("AI \u601D\u8003\u4E2D...");
        var self:GobangGame = this;
        _rootMc.onEnterFrame = function() {
            self._aiThinkFrame();
        };
    }

    private function _aiThinkFrame():Void {
        _frameCount++;
        var stepResult:Object = _ai.aiMoveStep(FRAME_BUDGET);
        _lastStepResult = stepResult;

        // 更新候选点可视化
        _drawCandidate(stepResult.x, stepResult.y);

        // 计算进度百分比和预估时间
        var elapsed:Number = getTimer() - _aiStartTime;
        var elapsedSec:Number = Math.floor(elapsed / 100) / 10;
        var phaseStr:String = phaseName(stepResult.phaseLabel);
        var coordStr:String = (stepResult.x >= 0) ? "(" + _numToLetter(stepResult.y) + String(stepResult.x + 1) + ")" : "--";

        // 进度估算：基于根层走法遍历比例 + 阶段权重
        var pct:Number = 0;
        var rt:Number = (stepResult.rootTotal > 0) ? stepResult.rootTotal : 1;
        var ri:Number = (stepResult.rootIdx > 0) ? stepResult.rootIdx : 0;
        var moveProgress:Number = ri / rt; // 0~1
        if (stepResult.phase === 1) {
            // VCT 阶段占 0~15%
            pct = Math.floor(moveProgress * 15);
        } else if (stepResult.phase === 2) {
            // MINMAX 阶段占 15~90%
            pct = 15 + Math.floor(moveProgress * 75);
        } else {
            pct = 90 + Math.floor(moveProgress * 10);
        }
        if (pct > 99) pct = 99;

        // 预估剩余时间
        var etaStr:String = "";
        if (pct > 3 && elapsed > 500) {
            var totalEstMs:Number = elapsed * 100 / pct;
            var remainMs:Number = totalEstMs - elapsed;
            var remainSec:Number = Math.ceil(remainMs / 1000);
            if (remainSec > 0) {
                etaStr = " ~" + remainSec + "s";
            }
        }

        var line1:String = "AI \u601D\u8003\u4E2D " + elapsedSec + "s " + pct + "%" + etaStr;
        var line2:String = phaseStr + " " + ri + "/" + rt + " | " + stepResult.nodes + "\u70B9";
        var line3:String = "\u5019\u9009: " + coordStr;
        _updateStatusRaw(line1 + "\n" + line2 + "\n" + line3);

        if (!stepResult.done) return;

        // 搜索完成
        delete _rootMc.onEnterFrame;
        _aiThinking = false;
        _inputLocked = false;
        _candidateMc.clear();
        _lastStepResult = null;

        if (stepResult.x < 0) return;
        _lastMoveX = stepResult.x;
        _lastMoveY = stepResult.y;
        _renderAll();

        if (_ai.isGameOver()) {
            _onGameOver();
            return;
        }

        var totalMs:Number = getTimer() - _aiStartTime;
        var roleStr:String = (_ai.getCurrentRole() === 1) ? "\u9ED1\u68CB" : "\u767D\u68CB";
        _updateStatus(roleStr + "\u8BF7\u843D\u5B50\nAI\u843D\u5B50(" + _numToLetter(stepResult.y) + String(stepResult.x + 1) + ") " + totalMs + "ms " + stepResult.nodes + "\u8282\u70B9");
    }

    // 绘制 AI 候选点标记（半透明闪烁棋子 + 十字准星）
    private function _drawCandidate(cx:Number, cy:Number):Void {
        _candidateMc.clear();
        if (cx < 0 || cy < 0) return;
        var px:Number = MARGIN + cy * CELL;
        var py:Number = MARGIN + cx * CELL;
        var r:Number = CELL * 0.38;

        // 半透明棋子预览
        var alpha:Number = 30 + Math.floor((_frameCount % 20) * 2);
        if (_aiRole === 1) {
            _candidateMc.beginFill(BLACK_COLOR, alpha);
        } else {
            _candidateMc.beginFill(WHITE_COLOR, alpha);
        }
        _drawCircle(_candidateMc, px, py, r);
        _candidateMc.endFill();

        // 十字准星
        _candidateMc.lineStyle(2, CANDIDATE_COLOR, 70);
        var cr:Number = CELL * 0.5;
        _candidateMc.moveTo(px - cr, py);
        _candidateMc.lineTo(px - cr * 0.3, py);
        _candidateMc.moveTo(px + cr * 0.3, py);
        _candidateMc.lineTo(px + cr, py);
        _candidateMc.moveTo(px, py - cr);
        _candidateMc.lineTo(px, py - cr * 0.3);
        _candidateMc.moveTo(px, py + cr * 0.3);
        _candidateMc.lineTo(px, py + cr);
        _candidateMc.lineStyle(0, 0, 0);
    }

    private function _undoMove():Void {
        if (_aiThinking) {
            // AI 思考中按悔棋：中断思考
            delete _rootMc.onEnterFrame;
            _aiThinking = false;
            _inputLocked = false;
            _candidateMc.clear();
        }
        if (_gameOver) {
            _ai.undo();
            _ai.undo();
            _gameOver = false;
        } else {
            _ai.undo();
            _ai.undo();
        }
        _lastMoveX = -1;
        _lastMoveY = -1;
        _renderAll();
        _updateStatus("\u5DF2\u6094\u68CB\uFF0C\u8BF7\u843D\u5B50");
    }

    private function _onGameOver():Void {
        _gameOver = true;
        _inputLocked = false;
        var w:Number = _ai.getWinner();
        var msg:String;
        if (w === 1) {
            msg = "\u9ED1\u68CB\u83B7\u80DC\uFF01";
        } else if (w === -1) {
            msg = "\u767D\u68CB\u83B7\u80DC\uFF01";
        } else {
            msg = "\u5E73\u5C40\uFF01";
        }
        _updateStatus(msg + "\n\u70B9\u51FB\"\u65B0\u6E38\u620F\"\u91CD\u6765");
    }

    private function _onBoardHover():Void {
        _hoverMc.clear();
        if (_inputLocked || _gameOver || _aiThinking) return;
        if (_ai.getCurrentRole() === _aiRole) return;

        var pos:Object = _mouseToGrid();
        if (pos === null) return;

        var bd:Array = _ai.getBoard();
        if (bd[pos.x][pos.y] !== 0) return;

        var px:Number = MARGIN + pos.y * CELL;
        var py:Number = MARGIN + pos.x * CELL;
        var r:Number = CELL * 0.38;
        _hoverMc.beginFill(HOVER_COLOR, 40);
        _drawCircle(_hoverMc, px, py, r);
        _hoverMc.endFill();
    }

    private function _mouseToGrid():Object {
        var mx:Number = _rootMc._xmouse;
        var my:Number = _rootMc._ymouse;
        var col:Number = Math.round((mx - MARGIN) / CELL);
        var row:Number = Math.round((my - MARGIN) / CELL);
        if (row < 0 || row >= BOARD_SIZE || col < 0 || col >= BOARD_SIZE) return null;
        return {x: row, y: col};
    }

    // ===== 渲染 =====

    private function _renderAll():Void {
        _piecesMc.clear();
        var bd:Array = _ai.getBoard();
        var r:Number = CELL * 0.42;

        for (var i:Number = 0; i < BOARD_SIZE; i++) {
            for (var j:Number = 0; j < BOARD_SIZE; j++) {
                if (bd[i][j] === 0) continue;
                var px:Number = MARGIN + j * CELL;
                var py:Number = MARGIN + i * CELL;
                var isBlack:Boolean = (bd[i][j] === 1);

                _piecesMc.beginFill(0x000000, 20);
                _drawCircle(_piecesMc, px + 2, py + 2, r);
                _piecesMc.endFill();

                if (isBlack) {
                    _piecesMc.beginFill(BLACK_COLOR, 100);
                    _drawCircle(_piecesMc, px, py, r);
                    _piecesMc.endFill();
                    _piecesMc.beginFill(0x666666, 40);
                    _drawCircle(_piecesMc, px - r * 0.25, py - r * 0.25, r * 0.3);
                    _piecesMc.endFill();
                } else {
                    _piecesMc.lineStyle(1, 0x999999, 60);
                    _piecesMc.beginFill(WHITE_COLOR, 100);
                    _drawCircle(_piecesMc, px, py, r);
                    _piecesMc.endFill();
                    _piecesMc.lineStyle(0, 0, 0);
                    _piecesMc.beginFill(0xFFFFFF, 50);
                    _drawCircle(_piecesMc, px - r * 0.25, py - r * 0.25, r * 0.3);
                    _piecesMc.endFill();
                }

                if (i === _lastMoveX && j === _lastMoveY) {
                    _piecesMc.beginFill(LAST_MOVE_COLOR, 100);
                    _drawCircle(_piecesMc, px, py, 3);
                    _piecesMc.endFill();
                }
            }
        }
    }

    // ===== 状态栏 =====

    private function _updateStatus(msg:String):Void {
        _updateStatusRaw(msg + "\n\u96BE\u5EA6:" + _difficulty + " AI:" + (_aiRole === 1 ? "\u9ED1" : "\u767D") + " \u9884\u7B97:" + FRAME_BUDGET + "ms/\u5E27");
    }

    private function _updateStatusRaw(msg:String):Void {
        var tf:TextField = _statusMc["tf"];
        tf.text = msg;
    }

    // 列号转字母 (0→A, 1→B, ...)
    private function _numToLetter(n:Number):String {
        return String.fromCharCode(65 + n);
    }

    public function destroy():Void {
        delete _rootMc.onEnterFrame;
        _rootMc.removeMovieClip();
    }
}
