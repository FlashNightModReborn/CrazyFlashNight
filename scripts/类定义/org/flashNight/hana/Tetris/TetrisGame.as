// scripts\类定义\org\flashNight\hana\Tetris\TetrisGame.as
class org.flashNight.hana.Tetris.TetrisGame {
    // —— 静态配置/常量 ——————————————————————————————————————
    static var CLASS_NAME:String = "org.flashNight.hana.Tetris.TetrisGame";
    static var _instanceCounter:Number = 0;

    // Pieces: 0 I, 1 O, 2 T, 3 S, 4 Z, 5 J, 6 L
    // 4个旋转，每个为4个方块坐标 [x,y]
    // 坐标基于piece原点(左上角)；旋转为0,1,2,3
    static var PIECES:Array = [
        // I
        [
            [[0,1],[1,1],[2,1],[3,1]],
            [[2,0],[2,1],[2,2],[2,3]],
            [[0,2],[1,2],[2,2],[3,2]],
            [[1,0],[1,1],[1,2],[1,3]]
        ],
        // O
        [
            [[1,0],[2,0],[1,1],[2,1]],
            [[1,0],[2,0],[1,1],[2,1]],
            [[1,0],[2,0],[1,1],[2,1]],
            [[1,0],[2,0],[1,1],[2,1]]
        ],
        // T
        [
            [[1,0],[0,1],[1,1],[2,1]],
            [[1,0],[1,1],[2,1],[1,2]],
            [[0,1],[1,1],[2,1],[1,2]],
            [[1,0],[0,1],[1,1],[1,2]]
        ],
        // S
        [
            [[1,0],[2,0],[0,1],[1,1]],
            [[1,0],[1,1],[2,1],[2,2]],
            [[1,1],[2,1],[0,2],[1,2]],
            [[0,0],[0,1],[1,1],[1,2]]
        ],
        // Z
        [
            [[0,0],[1,0],[1,1],[2,1]],
            [[2,0],[1,1],[2,1],[1,2]],
            [[0,1],[1,1],[1,2],[2,2]],
            [[1,0],[0,1],[1,1],[0,2]]
        ],
        // J
        [
            [[0,0],[0,1],[1,1],[2,1]],
            [[1,0],[2,0],[1,1],[1,2]],
            [[0,1],[1,1],[2,1],[2,2]],
            [[1,0],[1,1],[0,2],[1,2]]
        ],
        // L
        [
            [[2,0],[0,1],[1,1],[2,1]],
            [[1,0],[1,1],[1,2],[2,2]],
            [[0,1],[1,1],[2,1],[0,2]],
            [[0,0],[1,0],[1,1],[1,2]]
        ]
    ];

    // 简化墙踢偏移（依次尝试）
    static var KICK_OFFSETS:Array = [[0,0],[1,0],[-1,0],[0,-1],[2,0],[-2,0]];

    // 默认颜色（按类型索引 0..6）
    static var DEFAULT_COLORS:Array = [0x6DE8F5,0xF8E36C,0xC768EC,0x7DE07B,0xF17474,0x6E9AF6,0xF5B46D];
    static var GHOST_ALPHA:Number = 30; // 幽灵影透明度（百分比）
    static var GRID_COLOR:Number = 0x202020;

    // —— 实例字段 ————————————————————————————————————————
    // 宿主 & 画面
    private var _host:MovieClip;       // 容器（由外部传入）
    private var _rootMc:MovieClip;     // 本模块的根MC
    private var _boardMc:MovieClip;    // 棋盘
    private var _pieceMc:MovieClip;    // 当前活动方块
    private var _ghostMc:MovieClip;    // 幽灵影
    private var _uiMc:MovieClip;       // UI区域(Hold/Next/文字)

    // 游戏参数（可配置）
    private var CELL:Number;           // 单元格像素
    private var BW:Number;             // 宽（格）
    private var BH:Number;             // 高（格）
    private var showGrid:Boolean;
    private var enableHold:Boolean;
    private var enableGhost:Boolean;
    private var enableKeyboard:Boolean;
    private var colors:Array;
    private var gravityMs:Number;      // 重力间隔
    private var softdropFactor:Number; // 软降倍速（越小越快）
    private var minGravityMs:Number;   // 最小重力间隔
    private var panelGap:Number;       // UI间距
    private var margin:Number;         // 布局边距

    // 状态
    private var board:Array;           // 2D数组 [y][x]，值为0=空 或 1..7 颜色索引
    private var curType:Number;
    private var curRot:Number;
    private var curX:Number;
    private var curY:Number;
    private var holdType:Number;       // -1=无
    private var holdLocked:Boolean;    // 持有一次限制
    private var queue:Array;           // 预览队列
    private var running:Boolean;
    private var paused:Boolean;
    private var softdrop:Boolean;

    // 计分
    private var score:Number;
    private var lines:Number;
    private var level:Number;
    private var startTime:Number;
    private var lastTick:Number;       // 上次重力tick时间
    private var instId:Number;

    // 键盘监听代理
    private var _keyL:Object;

    // 事件监听器（外部可添加 { onTetrisEvent: function(e){} } ）
    private var _listeners:Array;

    // —— 构造 ————————————————————————————————————————————————
    function TetrisGame(host:MovieClip, config:Object) {
        org.flashNight.hana.Tetris.TetrisGame._instanceCounter++;
        this.instId = org.flashNight.hana.Tetris.TetrisGame._instanceCounter;
        this._host = host;
        this._listeners = [];

        // 默认配置
        this.BW = 10;
        this.BH = 20;
        this.CELL = (config != null && config.cell > 0) ? config.cell : 24;
        this.margin = (config != null && config.margin != undefined) ? config.margin : 12;
        this.panelGap = (config != null && config.panelGap != undefined) ? config.panelGap : 16;

        this.showGrid = (config != null && config.showGrid != undefined) ? Boolean(config.showGrid) : true;
        this.enableHold = (config != null && config.enableHold != undefined) ? Boolean(config.enableHold) : true;
        this.enableGhost = (config != null && config.enableGhost != undefined) ? Boolean(config.enableGhost) : true;
        this.enableKeyboard = (config != null && config.enableKeyboard != undefined) ? Boolean(config.enableKeyboard) : true;

        this.colors = (config != null && config.colors instanceof Array) ? config.colors : DEFAULT_COLORS.concat();

        // 重力/速度
        this.gravityMs = (config != null && config.gravityMs > 0) ? config.gravityMs : 1000;
        this.minGravityMs = (config != null && config.minGravityMs > 0) ? config.minGravityMs : 100;
        this.softdropFactor = (config != null && config.softdropFactor > 0) ? config.softdropFactor : 0.15; // 软降=重力*factor

        // 初始化渲染根
        var depth:Number = host.getNextHighestDepth();
        this._rootMc = host.createEmptyMovieClip("_tetrisRoot_" + this.instId, depth);
        // 布局
        var left:Number = this.margin;
        var top:Number = this.margin;
        // 容器
        this._boardMc = this._rootMc.createEmptyMovieClip("board", 1);
        this._pieceMc = this._rootMc.createEmptyMovieClip("piece", 2);
        this._ghostMc = this._rootMc.createEmptyMovieClip("ghost", 3);
        this._uiMc    = this._rootMc.createEmptyMovieClip("ui",    4);

        // UI: 文本
        this._uiMc.createTextField("txtScore", 10, left + this.BW*this.CELL + this.panelGap, top, 160, 20);
        this._uiMc.createTextField("txtLines", 11, left + this.BW*this.CELL + this.panelGap, top+22, 160, 20);
        this._uiMc.createTextField("txtLevel", 12, left + this.BW*this.CELL + this.panelGap, top+44, 160, 20);
        this._uiMc.createTextField("txtHint",  13, left + this.BW*this.CELL + this.panelGap, top+68, 180, 60);
        this._uiMc["txtScore"].text = "SCORE: 0";
        this._uiMc["txtLines"].text = "LINES: 0";
        this._uiMc["txtLevel"].text = "LEVEL: 1";
        this._uiMc["txtHint"].text  = "Z/↑/X 旋转  ←/→ 移动\n↓ 软降  Space 速降\nC 持有  P 暂停  R 重开";

        // 预览/持有框
        this._uiMc.createEmptyMovieClip("holdBox", 20);
        this._uiMc.createEmptyMovieClip("nextBox", 21);
        this._uiMc["holdBox"]._x = left + this.BW*this.CELL + this.panelGap;
        this._uiMc["holdBox"]._y = top + 140;
        this._uiMc["nextBox"]._x = left + this.BW*this.CELL + this.panelGap;
        this._uiMc["nextBox"]._y = top + 260;

        // 键盘（可选）
        if (this.enableKeyboard) {
            var self:TetrisGame = this;
            this._keyL = {
                owner: self,
                onKeyDown: function() { self._onKeyDown(Key.getCode()); },
                onKeyUp: function() { self._onKeyUp(Key.getCode()); }
            };
            Key.addListener(this._keyL);
        }

        // 初始棋盘
        this._allocBoard();
        this._drawBoardBase();

        // 帧循环
        var that:TetrisGame = this;
        this._rootMc.onEnterFrame = function() { that._update(); };
    }

    // —— 外部接口（宿主控制） ———————————————————————————————
    public function start(initial:Object):Void {
        // 可用 initial 覆盖游戏性
        if (initial != null) {
            if (initial.level > 0) { this.level = Number(initial.level); }
            if (initial.gravityMs > 0) { this.gravityMs = Number(initial.gravityMs); }
            if (initial.minGravityMs > 0) { this.minGravityMs = Number(initial.minGravityMs); }
        }
        this._resetGame();
        this.running = true;
        this.paused = false;
        this._emit("started", null);
    }

    public function stop():Object {
        // 主动退出：返回结算
        var result:Object = this._buildResult("quit");
        this.running = false;
        this.paused = true;
        this._emit("gameOver", result);
        return result;
    }

    public function pause():Void {
        if (!this.running) return;
        this.paused = true;
        this._emit("paused", null);
    }

    public function resume():Void {
        if (!this.running) return;
        this.paused = false;
        this._emit("resumed", null);
    }

    public function sendCommand(cmd:String, payload:Object):Void {
        if (cmd == "MOVE_LEFT") this._tryMove(-1,0);
        else if (cmd == "MOVE_RIGHT") this._tryMove(1,0);
        else if (cmd == "SOFT_DROP_ON") this.softdrop = true;
        else if (cmd == "SOFT_DROP_OFF") this.softdrop = false;
        else if (cmd == "HARD_DROP") this._hardDrop();
        else if (cmd == "ROTATE_CW") this._rotate(1);
        else if (cmd == "ROTATE_CCW") this._rotate(-1);
        else if (cmd == "HOLD") if (this.enableHold) this._hold();
        else if (cmd == "TOGGLE_PAUSE") { if (this.paused) this.resume(); else this.pause(); }
        else if (cmd == "RESTART") this.start(null);
    }

    public function setConfig(key:String, value:Object):Void {
        // 运行时部分可变参数
        if (key == "gravityMs") this.gravityMs = Number(value);
        else if (key == "minGravityMs") this.minGravityMs = Number(value);
        else if (key == "ghost") this.enableGhost = Boolean(value);
        else if (key == "hold") this.enableHold = Boolean(value);
        else if (key == "showGrid") { this.showGrid = Boolean(value); this._drawBoardBase(); }
        // 视觉变更可能需要刷新
    }

    public function getResult():Object {
        return this._buildResult("snapshot");
    }

    public function addListener(l:Object):Void {
        if (l == null) return;
        this._listeners.push(l);
    }
    public function removeListener(l:Object):Void {
        var i:Number = 0, n:Number = this._listeners.length;
        for (i=0; i<n; i++) {
            if (this._listeners[i] === l) {
                this._listeners.splice(i,1);
                return;
            }
        }
    }

    public function destroy():Void {
        // 清理一切引用/监听/MC
        if (this._keyL) Key.removeListener(this._keyL);
        this._rootMc.onEnterFrame = null;
        this._ghostMc.removeMovieClip();
        this._pieceMc.removeMovieClip();
        this._boardMc.removeMovieClip();
        this._uiMc.removeMovieClip();
        this._rootMc.removeMovieClip();
        this._emit("destroyed", null);
    }

    // —— 内部：游戏生命周期 ——————————————————————————————
    private function _resetGame():Void {
        this._allocBoard();
        this.queue = [];
        this._refillQueue();
        this.holdType = -1;
        this.holdLocked = false;
        this.score = 0;
        this.lines = 0;
        if (this.level <= 0) this.level = 1;
        this.startTime = getTimer();
        this.lastTick = getTimer();
        this.softdrop = false;
        this._spawn();
        this._renderAll();
        this._updateHUD();
    }

    private function _gameOver(reason:String):Void {
        var result:Object = this._buildResult(reason);
        this.running = false;
        this.paused = true;
        this._emit("gameOver", result);
    }

    private function _buildResult(reason:String):Object {
        var elapsed:Number = getTimer() - this.startTime;
        var r:Object = { score: this.score, lines: this.lines, level: this.level, timeMs: elapsed, reason: reason };
        return r;
    }

    // —— 内部：数据结构 ————————————————————————————————
    private function _allocBoard():Void {
        this.board = [];
        var y:Number, x:Number;
        for (y=0; y<this.BH; y++) {
            var row:Array = [];
            for (x=0; x<this.BW; x++) row.push(0);
            this.board.push(row);
        }
    }

    private function _refillQueue():Void {
        // 7袋随机
        var bag:Array = [0,1,2,3,4,5,6];
        var i:Number, j:Number, tmp:Number;
        for (i=bag.length-1; i>0; i--) {
            j = Math.floor(Math.random()*(i+1));
            tmp = bag[i]; bag[i] = bag[j]; bag[j] = tmp;
        }
        // 追加到队列
        for (i=0; i<bag.length; i++) this.queue.push(bag[i]);
    }

    private function _spawn():Void {
        if (this.queue.length < 7) this._refillQueue();
        this.curType = this.queue.shift();
        this.curRot = 0;
        // 初始位置
        this.curX = 3;
        this.curY = -1; // 允许顶部空间
        this.holdLocked = false;

        if (!this._valid(this.curX, this.curY, this.curRot, this.curType)) {
            // 顶出
            this._renderAll();
            this._gameOver("topout");
        }
    }

    private function _hold():Void {
        if (this.holdLocked) return;
        if (this.holdType == -1) {
            this.holdType = this.curType;
            this._spawn();
        } else {
            var t:Number = this.holdType;
            this.holdType = this.curType;
            this.curType = t;
            this.curRot = 0;
            this.curX = 3;
            this.curY = -1;
            if (!this._valid(this.curX, this.curY, this.curRot, this.curType)) {
                this._gameOver("topout");
                return;
            }
        }
        this.holdLocked = true;
        this._renderAll();
    }

    // —— 内部：输入/控制 ————————————————————————————————
    private function _onKeyDown(code:Number):Void {
        if (!this.running) return;
        if (code == 80) { // P
            if (this.paused) this.resume(); else this.pause();
            return;
        }
        if (this.paused) return;

        if (code == Key.LEFT) this._tryMove(-1,0);
        else if (code == Key.RIGHT) this._tryMove(1,0);
        else if (code == Key.DOWN) this.softdrop = true;
        else if (code == 32) this._hardDrop(); // Space
        else if (code == Key.UP || code == 88) this._rotate(1); // ↑ or X
        else if (code == 90) this._rotate(-1); // Z
        else if (code == 67) if (this.enableHold) this._hold(); // C
        else if (code == 82) this.start(null); // R
    }

    private function _onKeyUp(code:Number):Void {
        if (code == Key.DOWN) this.softdrop = false;
    }

    // —— 内部：运动与判定 ————————————————————————————————
    private function _tryMove(dx:Number, dy:Number):Void {
        var nx:Number = this.curX + dx;
        var ny:Number = this.curY + dy;
        if (this._valid(nx, ny, this.curRot, this.curType)) {
            this.curX = nx; this.curY = ny;
            this._renderAll();
        }
    }

    private function _rotate(dir:Number):Void {
        var newRot:Number = (this.curRot + (dir>0?1:3)) & 3;
        var i:Number, off:Array, nx:Number, ny:Number;
        for (i=0; i<KICK_OFFSETS.length; i++) {
            off = KICK_OFFSETS[i];
            nx = this.curX + off[0];
            ny = this.curY + off[1];
            if (this._valid(nx, ny, newRot, this.curType)) {
                this.curX = nx; this.curY = ny; this.curRot = newRot;
                this._renderAll();
                return;
            }
        }
    }

    private function _hardDrop():Void {
        var drop:Number = 0;
        while (this._valid(this.curX, this.curY+1, this.curRot, this.curType)) {
            this.curY++; drop++;
        }
        // 速降加分（+2/格）
        this.score += drop * 2;
        this._lockPiece();
    }

    private function _softStep():Boolean {
        // 软降或重力：向下移动一步；若失败则落地
        if (this._valid(this.curX, this.curY+1, this.curRot, this.curType)) {
            this.curY++;
            // 软降加分（+1/格）
            if (this.softdrop) this.score += 1;
            this._renderAll();
            return true;
        } else {
            this._lockPiece();
            return false;
        }
    }

    private function _valid(px:Number, py:Number, rot:Number, type:Number):Boolean {
        var cells:Array = PIECES[type][rot];
        var i:Number, x:Number, y:Number;
        for (i=0; i<4; i++) {
            x = px + cells[i][0];
            y = py + cells[i][1];
            if (x < 0 || x >= this.BW) return false;
            if (y >= this.BH) return false;
            if (y >= 0 && this.board[y][x] != 0) return false;
        }
        return true;
    }

    private function _lockPiece():Void {
        var cells:Array = PIECES[this.curType][this.curRot];
        var i:Number, x:Number, y:Number;
        for (i=0; i<4; i++) {
            x = this.curX + cells[i][0];
            y = this.curY + cells[i][1];
            if (y >= 0 && y < this.BH && x >= 0 && x < this.BW) {
                this.board[y][x] = this.curType + 1; // 1..7
            }
        }
        var cleared:Number = this._clearLines();
        if (cleared > 0) {
            // 简化计分：1=100,2=300,3=500,4=800，乘等级
            var base:Array = [0,100,300,500,800];
            this.score += base[cleared] * this.level;
            this.lines += cleared;
            // 每10行升一级；重力线性加快
            var newLevel:Number = Math.floor(this.lines/10)+1;
            if (newLevel > this.level) {
                this.level = newLevel;
                var target:Number = 1000 - (this.level-1)*80;
                if (target < this.minGravityMs) target = this.minGravityMs;
                this.gravityMs = target;
            }
            this._updateHUD();
        }
        this._spawn();
        this._renderAll();
    }

    private function _clearLines():Number {
        var y:Number, x:Number, writeY:Number = this.BH-1, readY:Number;
        var cleared:Number = 0;
        for (readY=this.BH-1; readY>=0; readY--) {
            var full:Boolean = true;
            for (x=0; x<this.BW; x++) {
                if (this.board[readY][x] == 0) { full = false; break; }
            }
            if (!full) {
                if (writeY != readY) {
                    // 行下移
                    for (x=0; x<this.BW; x++) this.board[writeY][x] = this.board[readY][x];
                }
                writeY--;
            } else {
                cleared++;
            }
        }
        // 上方补0
        for (y=writeY; y>=0; y--) {
            for (x=0; x<this.BW; x++) this.board[y][x] = 0;
        }
        return cleared;
    }

    // —— 内部：渲染 ————————————————————————————————————————
    private function _drawBoardBase():Void {
        // 背板与网格
        var left:Number = this.margin;
        var top:Number = this.margin;
        var w:Number = this.BW*this.CELL;
        var h:Number = this.BH*this.CELL;

        this._boardMc.clear();
        this._boardMc.lineStyle(1, 0x606060, 100);
        this._boardMc.beginFill(0x101010, 100);
        this._boardMc.moveTo(left, top);
        this._boardMc.lineTo(left+w, top);
        this._boardMc.lineTo(left+w, top+h);
        this._boardMc.lineTo(left, top+h);
        this._boardMc.lineTo(left, top);
        this._boardMc.endFill();

        if (this.showGrid) {
            this._boardMc.lineStyle(1, GRID_COLOR, 100);
            var x:Number, y:Number;
            for (x=1; x<this.BW; x++) {
                this._boardMc.moveTo(left + x*this.CELL, top);
                this._boardMc.lineTo(left + x*this.CELL, top + h);
            }
            for (y=1; y<this.BH; y++) {
                this._boardMc.moveTo(left, top + y*this.CELL);
                this._boardMc.lineTo(left + w, top + y*this.CELL);
            }
        }
    }

    private function _renderAll():Void {
        this._renderBoardCells();
        this._renderGhost();
        this._renderPiece();
        this._renderSideBoxes();
    }

    private function _renderBoardCells():Void {
        var left:Number = this.margin;
        var top:Number = this.margin;
        this._boardMc.beginFill(0x000000, 0); // 占位避免空状态
        this._boardMc.endFill();

        // 用单独层绘制方块（清除重画）
        // 为简洁起见，直接在 boardMc 上画（200格以内可接受）
        // 也可以拆成一个cellsMc层单独clear以减少基底重画
        // 这里直接清 piece/ghost 层，board 层仅画静态网格，所以我们重画到 piece/ghost 之外
        // 方案：创建或复用 boardCells 子MC
        if (this._boardMc["cells"] == undefined) {
            this._boardMc.createEmptyMovieClip("cells", 100);
            this._boardMc["cells"]._x = 0;
            this._boardMc["cells"]._y = 0;
        }
        var mc:MovieClip = this._boardMc["cells"];
        mc.clear();

        var y:Number, x:Number, v:Number, cx:Number, cy:Number, col:Number;
        for (y=0; y<this.BH; y++) {
            for (x=0; x<this.BW; x++) {
                v = this.board[y][x];
                if (v != 0) {
                    col = this.colors[v-1];
                    cx = this.margin + x*this.CELL;
                    cy = this.margin + y*this.CELL;
                    this._rect(mc, cx, cy, this.CELL, this.CELL, col);
                }
            }
        }
    }

    private function _renderPiece():Void {
        this._pieceMc.clear();
        if (this.paused || !this.running) return;
        var cells:Array = PIECES[this.curType][this.curRot];
        var i:Number, x:Number, y:Number, col:Number;
        col = this.colors[this.curType];
        for (i=0; i<4; i++) {
            x = this.curX + cells[i][0];
            y = this.curY + cells[i][1];
            if (y >= 0) {
                this._rect(this._pieceMc, this.margin + x*this.CELL, this.margin + y*this.CELL, this.CELL, this.CELL, col);
            }
        }
    }

    private function _renderGhost():Void {
        this._ghostMc.clear();
        if (!this.enableGhost || this.paused || !this.running) return;
        var gy:Number = this.curY;
        while (this._valid(this.curX, gy+1, this.curRot, this.curType)) gy++;
        if (gy == this.curY) return; // 紧贴不画

        var cells:Array = PIECES[this.curType][this.curRot];
        var i:Number, x:Number, y:Number;
        this._ghostMc.lineStyle(1, 0xFFFFFF, GHOST_ALPHA);
        this._ghostMc.beginFill(0xFFFFFF, GHOST_ALPHA);
        for (i=0; i<4; i++) {
            x = this.curX + cells[i][0];
            y = gy + cells[i][1];
            if (y >= 0) {
                var px:Number = this.margin + x*this.CELL;
                var py:Number = this.margin + y*this.CELL;
                this._ghostMc.moveTo(px, py);
                this._ghostMc.lineTo(px+this.CELL, py);
                this._ghostMc.lineTo(px+this.CELL, py+this.CELL);
                this._ghostMc.lineTo(px, py+this.CELL);
                this._ghostMc.lineTo(px, py);
            }
        }
        this._ghostMc.endFill();
    }

    private function _renderSideBoxes():Void {
        // Hold
        var hx:Number = this._uiMc["holdBox"]._x;
        var hy:Number = this._uiMc["holdBox"]._y;
        var nx:Number = this._uiMc["nextBox"]._x;
        var ny:Number = this._uiMc["nextBox"]._y;

        var size:Number = this.CELL*4;
        this._drawBox(this._uiMc["holdBox"], size, "HOLD");
        this._drawBox(this._uiMc["nextBox"], size, "NEXT");

        if (this.enableHold && this.holdType != -1) {
            this._drawMiniPiece(this._uiMc["holdBox"], this.holdType, 0, 0xFFFFFF);
        }
        // Next 显示前3个
        var i:Number, t:Number;
        for (i=0; i<3 && i<this.queue.length; i++) {
            t = this.queue[i];
            this._drawMiniPiece(this._uiMc["nextBox"], t, i, 0xFFFFFF);
        }
    }

    private function _drawBox(mc:MovieClip, size:Number, title:String):Void {
        mc.clear();
        mc.lineStyle(1, 0x909090, 100);
        mc.beginFill(0x0D0D0D, 100);
        mc.moveTo(0,0); mc.lineTo(size,0); mc.lineTo(size,size); mc.lineTo(0,size); mc.lineTo(0,0);
        mc.endFill();
        if (mc["title"] == undefined) mc.createTextField("title", 1, 4, 4, size-8, 16);
        mc["title"].text = title;
    }

    private function _drawMiniPiece(mc:MovieClip, type:Number, index:Number, color:Number):Void {
        // 放进 4x4 盒子，按 index 垂直偏移
        var offsetY:Number = 20 + index*44;
        var cells:Array = PIECES[type][0];
        var sz:Number = Math.floor(this.CELL*0.7);
        var ox:Number = 8;
        var oy:Number = offsetY;
        var i:Number, x:Number, y:Number;
        mc.lineStyle(1, 0xFFFFFF, 100);
        mc.beginFill(this.colors[type], 100);
        for (i=0; i<4; i++) {
            x = cells[i][0];
            y = cells[i][1];
            this._rect(mc, ox + x*sz, oy + y*sz, sz, sz, this.colors[type]);
        }
        mc.endFill();
    }

    private function _rect(mc:MovieClip, x:Number, y:Number, w:Number, h:Number, col:Number):Void {
        mc.lineStyle(1, 0x000000, 60);
        mc.beginFill(col, 100);
        mc.moveTo(x,y);
        mc.lineTo(x+w,y);
        mc.lineTo(x+w,y+h);
        mc.lineTo(x,y+h);
        mc.lineTo(x,y);
        mc.endFill();
    }

    private function _updateHUD():Void {
        this._uiMc["txtScore"].text = "SCORE: " + this.score;
        this._uiMc["txtLines"].text = "LINES: " + this.lines;
        this._uiMc["txtLevel"].text = "LEVEL: " + this.level;
    }

    // —— 内部：主循环 ————————————————————————————————————————
    private function _update():Void {
        if (!this.running || this.paused) return;

        var now:Number = getTimer();
        var g:Number = this.gravityMs;
        if (this.softdrop) g = Math.max(this.gravityMs * this.softdropFactor, 30);

        if (now - this.lastTick >= g) {
            this.lastTick = now;
            this._softStep();
        }
    }

    // —— 事件分发 ——————————————————————————————————————————
    private function _emit(type:String, data:Object):Void {
        var evt:Object = { type: type, data: data, target: this };
        var i:Number, n:Number = this._listeners.length, l:Object;
        for (i=0; i<n; i++) {
            l = this._listeners[i];
            if (l != null && l.onTetrisEvent) {
                l.onTetrisEvent(evt);
            }
        }
    }
}
