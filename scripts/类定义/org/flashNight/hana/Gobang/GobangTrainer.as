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
            expectedMoves: [[8,6],[4,10],[5,8]],
            description: "堵对角线三连，靠近中心(Rapfi:5,8 d35)"});

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
            expectedMoves: [[6,6],[3,14],[12,4]],
            description: "多威胁覆盖：开放局面多种合理走法"});

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

        // ===== mid_game_adv: 中盘进阶判断（2026-03-26 对局提取） =====

        // 黑棋中心+对角线扩展，白棋需要正确阻断发展方向
        addProblem({name: "mid_center_expand_block", category: "mid_game",
            moves: [[7,7,1],[8,8,-1],[6,6,1],[8,6,-1],[5,5,1],[9,5,-1],
                    [7,8,1],[0,0,-1],[6,8,1],[0,14,-1],[8,7,1],[14,0,-1]],
            role: -1, difficulty: 100, frameBudget: 8,
            expectedMoves: [],
            description: "中盘判断：黑棋双线发展(对角+横向)，Rapfi参考"});

        // 白棋需要主动进攻而非被动防守
        addProblem({name: "mid_active_offense", category: "mid_game",
            moves: [[7,7,1],[8,8,-1],[7,6,1],[8,7,-1],[6,5,1],[9,9,-1],
                    [5,4,1],[7,8,-1],[8,6,1],[6,7,-1],[9,5,1],[14,14,-1]],
            role: -1, difficulty: 100, frameBudget: 8,
            expectedMoves: [],
            description: "中盘判断：黑棋对角三连有双四潜力，Rapfi参考"});

        // 交叉威胁覆盖：多个方向同时有TWO+
        addProblem({name: "mid_cross_threat_coverage", category: "mid_game",
            moves: [[7,7,1],[8,8,-1],[7,5,1],[6,6,-1],[5,7,1],[8,6,-1],
                    [9,7,1],[6,8,-1],[7,9,1],[14,0,-1],[8,5,1],[14,14,-1]],
            role: -1, difficulty: 100, frameBudget: 8,
            expectedMoves: [[7,6],[6,7]],
            description: "交叉威胁覆盖(Rapfi:7,6 d31, AI:6,7 亦可接受)"});

        // P3优先级测试：有己方冲四但不应该走（全局更优手存在）
        addProblem({name: "mid_p3_should_not_rush", category: "mid_game",
            moves: [[7,7,1],[8,8,-1],[6,7,1],[8,7,-1],[5,7,1],[7,8,-1],
                    [7,6,1],[9,6,-1],[7,5,1],[6,6,-1],[9,7,1],[6,5,-1],
                    [8,6,1]],
            role: -1, difficulty: 100, frameBudget: 8,
            expectedMoves: [],
            description: "P3冲四非最优：白棋有冲四但Rapfi可能走防守"});

        // 对局提取 2026-03-26: AI给高分(97860)但随后被Rapfi压制至连续P4a
        addProblem({name: "mid_game_overeval_pivot", category: "mid_game",
            moves: [[7,7,1],[8,8,-1],[9,8,1],[9,7,-1],[7,9,1],[7,8,-1],
                    [6,8,1],[8,6,-1],[6,9,1]],
            role: -1, difficulty: 100, frameBudget: 8,
            expectedMoves: [],
            description: "对局转折点：AI过高评估后陷入被动，Rapfi参考"});

        // 对局提取: AI被迫连续堵五说明上一步(8,9)方向错误
        addProblem({name: "mid_game_avoid_trap", category: "mid_game",
            moves: [[7,7,1],[8,8,-1],[9,8,1],[9,7,-1],[7,9,1],[7,8,-1],
                    [6,8,1],[8,6,-1],[6,9,1],[8,9,-1],[8,10,1]],
            role: -1, difficulty: 100, frameBudget: 8,
            expectedMoves: [],
            description: "对局陷阱：AI走(8,9)后被(8,10)进攻，Rapfi参考"});

        // ===== defense_adv: 进阶防守（确定性可解） =====

        // 对角线双活三前驱：需要在交叉点防守
        addProblem({name: "def_diag_two_two_block", category: "defense",
            moves: pad.concat([[5,5,1],[6,6,1],[5,7,1],[6,8,1],[7,9,-1],[8,10,-1]]),
            role: -1, difficulty: 100, frameBudget: 8,
            expectedMoves: [[6,7],[7,7]],
            description: "防对角线TWO_TWO扩展(Rapfi:6,7 d35)"});

        // 水平+垂直交叉三连：必须堵交叉点
        addProblem({name: "def_cross_three_intersection", category: "defense",
            moves: pad.concat([[7,5,1],[7,6,1],[7,7,1],[5,7,1],[6,7,1],[8,8,-1],[9,9,-1]]),
            role: -1, difficulty: 100, frameBudget: 8,
            expectedMoves: [[7,4],[7,8]],
            description: "堵水平三连(7,5-7,6-7,7)两端"});

        // 反对角线活三+跳连
        addProblem({name: "def_anti_diag_three_jump", category: "defense",
            moves: pad.concat([[9,5,1],[8,6,1],[7,7,1],[5,9,1],[6,10,-1]]),
            role: -1, difficulty: 100, frameBudget: 8,
            expectedMoves: [[6,8],[10,4]],
            description: "堵反对角三连+跳连"});

        // ===== opening: 开局判断 =====

        // 中心开局后对手占角，选择最佳扩展方向
        addProblem({name: "open_center_then_expand", category: "opening",
            moves: [[7,7,1],[8,8,-1],[6,6,1],[8,6,-1]],
            role: 1, difficulty: 100, frameBudget: 8,
            expectedMoves: [],
            description: "开局扩展：黑棋对角后选最佳方向，Rapfi参考"});

        // 经典星-月开局应手
        addProblem({name: "open_star_moon_response", category: "opening",
            moves: [[7,7,1],[8,8,-1],[6,8,1]],
            role: -1, difficulty: 100, frameBudget: 8,
            expectedMoves: [],
            description: "星月开局白棋最佳应手，Rapfi参考"});

        // ===== R12: 更多确定性题目 =====

        // 必须走己方冲四成五（不是活四，是冲四补缺）
        addProblem({name: "tac_complete_block_four", category: "tactical",
            moves: pad.concat([[7,4,1],[7,5,1],[7,6,1],[7,8,1],
                    [6,4,-1],[6,5,-1],[8,7,-1]]),
            role: 1, difficulty: 100, frameBudget: 8,
            expectedMoves: [[7,7]],
            description: "补冲四缺口(7,7)成五"});

        // 双堵四：对手有两个冲四点，唯一的交叉堵点
        addProblem({name: "def_dual_block_four_only", category: "defense",
            moves: pad.concat([[7,5,1],[7,6,1],[7,7,1],[6,6,1],[5,5,1],
                    [8,8,-1],[9,9,-1]]),
            role: -1, difficulty: 100, frameBudget: 8,
            expectedMoves: [[7,4],[7,8],[4,4],[6,9]],
            description: "多方向活三，需堵最紧急端点"});

        // 对手在边缘区域的活三 — 不应忽略
        addProblem({name: "def_edge_three_block", category: "defense",
            moves: pad.concat([[3,7,1],[4,7,1],[5,7,1],[7,7,-1],[8,8,-1]]),
            role: -1, difficulty: 100, frameBudget: 8,
            expectedMoves: [[2,7],[6,7]],
            description: "堵边缘区域col7垂直三连两端"});

        // ===== R14: 批量确定性题目 — 增强健壮性测试 =====

        // 对角线五连检测
        addProblem({name: "mb_diag_five_complete", category: "must_block",
            moves: pad.concat([[4,4,1],[5,5,1],[6,6,1],[8,8,1],[7,6,-1]]),
            role: -1, difficulty: 100, frameBudget: 8,
            expectedMoves: [[7,7]],
            description: "堵对角线五连缺口(7,7)"});

        // 白棋利用己方三连发动进攻
        addProblem({name: "tac_use_own_three", category: "tactical",
            moves: pad.concat([[7,7,-1],[7,8,-1],[7,9,-1],
                    [8,7,1],[8,8,1],[9,9,1]]),
            role: -1, difficulty: 100, frameBudget: 8,
            expectedMoves: [[7,6],[7,10]],
            description: "白棋利用己方水平三连两端扩展"});

        // 角落附近的防守
        addProblem({name: "def_corner_three", category: "defense",
            moves: pad2.concat([[3,3,1],[4,4,1],[5,5,1],[7,7,-1]]),
            role: -1, difficulty: 100, frameBudget: 8,
            expectedMoves: [[2,2],[6,6]],
            description: "堵角落对角线三连两端"});

        // 跳三识别（中间有空）
        addProblem({name: "def_jump_three_h", category: "defense",
            moves: pad.concat([[7,4,1],[7,5,1],[7,7,1],[8,8,-1]]),
            role: -1, difficulty: 100, frameBudget: 8,
            expectedMoves: [[7,6],[7,3],[7,8]],
            description: "堵水平跳三(7,4-7,5-gap-7,7)"});

        // 确认 AI 堵对手四连而非做无意义进攻
        addProblem({name: "tac_block_before_attack", category: "tactical",
            moves: pad.concat([[7,5,1],[7,6,1],[7,7,1],[7,8,1],
                    [6,5,-1],[6,6,-1],[8,7,-1]]),
            role: -1, difficulty: 100, frameBudget: 8,
            expectedMoves: [[7,4],[7,9]],
            description: "对手有水平四连时必须堵两端"});

        // 双跳四：同时有两个跳四机会
        addProblem({name: "tac_double_gap_five", category: "tactical",
            moves: pad.concat([[7,3,1],[7,4,1],[7,6,1],[7,7,1],
                    [6,3,-1],[6,4,-1],[8,6,-1],[8,7,-1]]),
            role: 1, difficulty: 100, frameBudget: 8,
            expectedMoves: [[7,5]],
            description: "补跳四缺口(7,5)同时成五"});

        // ===== R18: 对局提取防守题 =====

        // 对角+横向双线交叉，防守方需要堵交叉点
        addProblem({name: "def_diag_cross_two_line", category: "defense",
            moves: pad.concat([[7,5,1],[7,6,1],[6,6,1],[5,7,1],[8,8,-1]]),
            role: -1, difficulty: 100, frameBudget: 8,
            expectedMoves: [[7,7],[7,4],[4,8]],
            description: "对角+横向双线交叉防守"});

        // 黑棋纵向三连+横向二连形成T型，白必须防纵向
        addProblem({name: "def_t_shape_vertical", category: "defense",
            moves: pad.concat([[7,7,1],[6,7,1],[5,7,1],[7,6,1],[8,8,-1],[9,9,-1]]),
            role: -1, difficulty: 100, frameBudget: 8,
            expectedMoves: [[4,7],[8,7]],
            description: "T型纵向三连(5-6-7,7)+横向二连"});

        // 黑棋斜向准活四(3子+两端空)，白必须在接近中心端堵截
        addProblem({name: "def_diag_near_four", category: "defense",
            moves: pad.concat([[5,5,1],[6,6,1],[7,7,1],[9,9,-1],[10,10,-1]]),
            role: -1, difficulty: 100, frameBudget: 8,
            expectedMoves: [[4,4],[8,8]],
            description: "斜向活三(5,5-6,6-7,7)堵两端"});

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

    // ========================================================================
    // ===== 对弈模式: AI vs Rapfi 完整对局 + 诊断 =====
    // ========================================================================

    // 配置
    private var _gAI:GobangAI;          // 本地 AI
    private var _gMoves:Array;           // [[x,y,role], ...] 完整走子历史
    private var _gConfig:Object;         // {aiColor, difficulty, frameBudget, rapfiTime, maxMoves}
    private var _gState:String;          // 状态机当前状态
    private var _gOnComplete:Function;
    private var _gClip:MovieClip;        // enterFrame 驱动
    private var _gMoveLog:Array;         // 每手详细日志
    private var _gMismatchLog:Array;     // 分数不一致记录
    private var _gMoveNum:Number;        // 当前手数
    private var _gWinner:Number;         // 0=进行中, 1=黑赢, -1=白赢

    /**
     * 启动对弈模式
     * @param config {aiColor: 1/-1, difficulty: 100, frameBudget: 8, rapfiTime: 2000, maxMoves: 100}
     * @param onComplete function(report:Object):Void
     */
    public function runFullGame(config:Object, onComplete:Function):Void {
        _gConfig = config || {};
        if (_gConfig.aiColor == undefined) _gConfig.aiColor = -1; // AI 默认白
        if (_gConfig.difficulty == undefined) _gConfig.difficulty = 100;
        if (_gConfig.frameBudget == undefined) _gConfig.frameBudget = 8;
        if (_gConfig.rapfiTime == undefined) _gConfig.rapfiTime = 2000;
        if (_gConfig.maxMoves == undefined) _gConfig.maxMoves = 100;

        _gOnComplete = onComplete;
        _gMoves = [];
        _gMoveLog = [];
        _gMismatchLog = [];
        _gMoveNum = 0;
        _gWinner = 0;

        _gAI = new GobangAI(_gConfig.aiColor, _gConfig.difficulty);

        trace("==============================");
        trace("[Game] Starting AI vs Rapfi");
        trace("[Game] AI=" + (_gConfig.aiColor === 1 ? "Black" : "White")
            + " difficulty=" + _gConfig.difficulty
            + " budget=" + _gConfig.frameBudget + "ms"
            + " rapfiTime=" + _gConfig.rapfiTime + "ms");
        trace("==============================");

        // 等待 Socket（如果还没连接）
        if (ServerManager.getInstance().isSocketConnected) {
            _gStartGame();
        } else {
            var self:GobangTrainer = this;
            _waitFrames = 0;
            _gClip = _root.createEmptyMovieClip("gameWait", _root.getNextHighestDepth());
            _gClip.onEnterFrame = function():Void {
                self._waitFrames++;
                if (ServerManager.getInstance().isSocketConnected) {
                    self._gClip.removeMovieClip();
                    self._gClip = null;
                    self._gStartGame();
                } else if (self._waitFrames >= CONNECT_WAIT_MAX) {
                    self._gClip.removeMovieClip();
                    self._gClip = null;
                    trace("[Game] ERROR: Socket not connected, cannot play vs Rapfi");
                    if (self._gOnComplete != undefined) self._gOnComplete(null);
                }
            };
        }
    }

    private function _gStartGame():Void {
        _gState = "NEXT_TURN";
        var self:GobangTrainer = this;
        _gClip = _root.createEmptyMovieClip("gameLoop", _root.getNextHighestDepth());
        _gClip.onEnterFrame = function():Void {
            self._gFrame();
        };
    }

    private function _gFrame():Void {
        // 游戏结束检查
        if (_gWinner !== 0 || _gMoveNum >= _gConfig.maxMoves) {
            _gFinish();
            return;
        }

        if (_gState === "NEXT_TURN") {
            _gMoveNum++;
            var isBlackTurn:Boolean = (_gMoveNum % 2 === 1); // 奇数手=黑
            var turnRole:Number = isBlackTurn ? 1 : -1;

            if (turnRole === _gConfig.aiColor) {
                // AI 的回合
                _gAI.aiMoveStart(_gConfig.frameBudget);
                _gState = "AI_THINKING";
            } else {
                // Rapfi 的回合
                _gSendRapfiMove();
                _gState = "RAPFI_WAITING";
            }
        } else if (_gState === "AI_THINKING") {
            var step:Object = _gAI.aiMoveStep(_gConfig.frameBudget);
            if (step.done) {
                if (step.x < 0) {
                    trace("[Game] AI returned no move, ending");
                    _gFinish();
                    return;
                }
                _gApplyMove(step.x, step.y, _gConfig.aiColor, step);
                _gState = "NEXT_TURN";
            }
        }
        // RAPFI_WAITING: 由 callback 推进，不在 frame 中处理
    }

    private function _gApplyMove(x:Number, y:Number, role:Number, aiResult:Object):Void {
        _gMoves.push([x, y, role]);

        // 如果是 Rapfi 走的，也要同步 AI 的内部棋盘
        if (role !== _gConfig.aiColor) {
            _gAI.playerMove(x, y);
        }

        // 记录日志
        var entry:Object = {
            moveNum: _gMoveNum,
            x: x, y: y, role: role,
            source: (role === _gConfig.aiColor) ? "AI" : "Rapfi",
            aiScore: (aiResult != null) ? aiResult.score : undefined,
            aiPhase: (aiResult != null) ? aiResult.phaseLabel : undefined,
            aiNodes: (aiResult != null) ? aiResult.nodes : undefined
        };
        _gMoveLog.push(entry);

        var src:String = entry.source;
        var scoreStr:String = (entry.aiScore !== undefined) ? " s=" + entry.aiScore : "";
        var phaseStr:String = (entry.aiPhase !== undefined) ? " " + entry.aiPhase : "";
        trace("[Game] #" + _gMoveNum + " " + src + " (" + x + "," + y + ")" + scoreStr + phaseStr);

        // 检查胜负
        if (_gAI.isGameOver()) {
            _gWinner = _gAI.getWinner();
        }
    }

    private function _gSendRapfiMove():Void {
        var payload:Object = {moves: _gMoves, timeLimit: _gConfig.rapfiTime};
        var self:GobangTrainer = this;
        ServerManager.getInstance().sendTaskWithCallback("gomoku_eval", payload, null,
            function(response:Object):Void {
                self._gOnRapfiResponse(response);
            });
    }

    private function _gOnRapfiResponse(response:Object):Void {
        if (_gState !== "RAPFI_WAITING") return; // 防止重复

        if (!response.success || response.result == undefined) {
            var err:String = (response.error != undefined) ? response.error : "unknown";
            trace("[Game] Rapfi error: " + err + ", ending game");
            _gFinish();
            return;
        }

        var rx:Number = response.result.x;
        var ry:Number = response.result.y;
        var rapfiScore:Number = response.result.score;
        var rapfiDepth:Number = response.result.depth;

        // 应用 Rapfi 的手
        var rapfiRole:Number = -_gConfig.aiColor;
        _gApplyMove(rx, ry, rapfiRole, null);

        // 交叉验证: 让本地 AI 评估 Rapfi 走后的局面
        if (_gWinner === 0) {
            var localEval:Number = _gAI.getEvalRef().evaluate(_gConfig.aiColor);

            // 检测分数反转: 如果上一手 AI 认为在赢（>1M）但 Rapfi 走后局面变差
            if (_gMoveLog.length >= 2) {
                var prevEntry:Object = _gMoveLog[_gMoveLog.length - 2];
                if (prevEntry.source === "AI" && prevEntry.aiScore > 1000000) {
                    // AI 上一手声称必杀，但现在局面如何？
                    var mismatch:Object = {
                        moveNum: _gMoveNum,
                        aiClaimedScore: prevEntry.aiScore,
                        aiClaimedPhase: prevEntry.aiPhase,
                        afterRapfiEval: localEval,
                        rapfiMove: [rx, ry],
                        rapfiScore: rapfiScore,
                        rapfiDepth: rapfiDepth
                    };
                    _gMismatchLog.push(mismatch);
                    trace("[Game] [MISMATCH] AI claimed s=" + prevEntry.aiScore
                        + " at #" + (prevEntry.moveNum) + " but after Rapfi #" + _gMoveNum
                        + " eval=" + localEval + " (Rapfi score=" + rapfiScore + " d=" + rapfiDepth + ")");
                }
            }

            // 更新 Rapfi 日志条目
            var lastEntry:Object = _gMoveLog[_gMoveLog.length - 1];
            lastEntry.rapfiScore = rapfiScore;
            lastEntry.rapfiDepth = rapfiDepth;
            lastEntry.localEvalAfter = localEval;
        }

        _gState = "NEXT_TURN";
    }

    private function _gFinish():Void {
        _gClip.removeMovieClip();
        _gClip = null;
        _gState = "DONE";

        trace("==============================");
        trace("[Game] GAME OVER");
        trace("==============================");

        var winnerStr:String;
        if (_gWinner === 1) winnerStr = "Black wins";
        else if (_gWinner === -1) winnerStr = "White wins";
        else winnerStr = "Draw/Timeout (" + _gMoveNum + " moves)";

        var aiWon:Boolean = (_gWinner === _gConfig.aiColor);
        trace("[Game] Result: " + winnerStr
            + " | AI=" + (_gConfig.aiColor === 1 ? "Black" : "White")
            + " | AI " + (aiWon ? "WON" : (_gWinner === 0 ? "DRAW" : "LOST")));
        trace("[Game] Total moves: " + _gMoveNum);

        // 打印 AI 决策日志
        _gAI.dumpMoveLog();

        // 打印 TSS 误判摘要
        if (_gMismatchLog.length > 0) {
            trace("=== TSS Mismatch Report ===");
            for (var i:Number = 0; i < _gMismatchLog.length; i++) {
                var m:Object = _gMismatchLog[i];
                trace("  #" + m.moveNum + ": AI claimed s=" + m.aiClaimedScore
                    + " (" + m.aiClaimedPhase + ")"
                    + " | after Rapfi(" + m.rapfiMove[0] + "," + m.rapfiMove[1] + ")"
                    + " eval=" + m.afterRapfiEval
                    + " | Rapfi score=" + m.rapfiScore + " d=" + m.rapfiDepth);
            }
            trace("=== " + _gMismatchLog.length + " mismatches detected ===");
        } else {
            trace("[Game] No TSS mismatches detected");
        }

        // 构造报告
        var report:Object = {
            winner: _gWinner,
            aiColor: _gConfig.aiColor,
            aiWon: aiWon,
            totalMoves: _gMoveNum,
            moves: _gMoves,
            moveLog: _gMoveLog,
            mismatches: _gMismatchLog,
            mismatchCount: _gMismatchLog.length
        };

        if (_gOnComplete != undefined) {
            _gOnComplete(report);
        }
    }
}
