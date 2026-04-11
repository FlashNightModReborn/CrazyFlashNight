import org.flashNight.neur.StateMachine.FSM_Status;
import org.flashNight.neur.StateMachine.FSM_StateMachine;
import org.flashNight.neur.Navigation.AStarGrid;
import org.flashNight.naki.RandomNumberEngine.*;
import org.flashNight.arki.unit.UnitAI.BaseUnitBehavior;
import org.flashNight.arki.unit.UnitAI.UnitAIData;
import org.flashNight.arki.spatial.move.*;
import org.flashNight.sara.util.*;
import org.flashNight.arki.render.*;
import org.flashNight.arki.bullet.BulletComponent.Collider.*;

// 场景中佣兵与可雇佣敌人NPC的状态机，继承单位状态机基类
//
// 寻路模拟器：tools/mercenary-ai-sim/
//   Python 外部模拟环境，精确复刻本类 FSM 与 Mover.isReachable 的 L-path 逻辑，
//   用于离线测试寻路改进方案。详见 tools/mercenary-ai-sim/README.md
//
// 寻路策略（已通过模拟器 10 种对抗性地图验证，全线正向零退化）：
//   1. 优先 L-path（Mover.isReachable，快，O(1)）
//   2. L-path 全部失败时懒加载 AStarGrid → find() → waypoint 缓存
//   3. Walking 沿 waypoint 逐点移动；Thinking 复用未走完的 waypoint
//   4. Wandering 保留 target 不清除，缩短 wander 时间后快速 repath

class org.flashNight.arki.unit.UnitAI.MecenaryBehavior extends BaseUnitBehavior {

    public static var IDLE_MIN_TIME:Number = 10;
    public static var IDLE_MAX_TIME:Number = 40;
    public static var WALK_MIN_TIME:Number = 8;
    public static var WALK_MAX_TIME:Number = 40;
    public static var WANDER_MIN_TIME:Number = 15;
    public static var WANDER_MAX_TIME:Number = 50;
    public static var ALIVE_MAX_TIME:Number = 30 * 30; // 900 帧 = 30s @30fps
    public static var STUCK_COUNT_MAX:Number = 3;

    // A* 网格参数
    private static var NAV_CELL_SIZE:Number = 15; // 格子大小（像素）

    public function MecenaryBehavior(_data:UnitAIData) {
        super(_data);

        // 状态列表（已存在基类的睡眠状态为默认状态）
        this.AddStatus("Thinking", new FSM_Status(null, this.think, null));
        this.AddStatus("Idle", new FSM_Status(null, this.idle_enter, null));
        this.AddStatus("Walking", new FSM_Status(this.walk, this.walk_enter, null));
        this.AddStatus("Wandering", new FSM_Status(null, this.wander_enter, null));

        // 过渡线
        this.pushGateTransition("Idle", "Thinking", function() {
            return this.actionCount >= data.think_threshold;
        });
        this.pushGateTransition("Walking", "Thinking", function() {
            // 有未走完的 waypoint 时延长 Walking，不回 Thinking
            if (data.waypoints != null && data.waypointIndex < data.waypoints.length) {
                return false;
            }
            return this.actionCount >= data.think_threshold;
        });
        this.pushGateTransition("Wandering", "Thinking", function() {
            return this.actionCount >= data.think_threshold;
        });

        // 检测到思考标签时结束睡眠状态进入思考状态
        this.pushGateTransition("Sleeping", "Thinking", this.wakeupCheck);
    }

    // ═══════════════════════════════════════════
    //  A* 导航网格懒加载
    // ═══════════════════════════════════════════

    /**
     * 获取或构建当前场景的 A* 导航网格（懒加载）。
     * 网格挂在 _root.gameworld._mercNavGrid 上，场景切换时随 gameworld 自动释放。
     * 只在首次 L-path 全部失败时调用，大多数简单地图不会触发。
     */
    private static function getNavGrid():AStarGrid {
        var gw:MovieClip = _root.gameworld;
        if (gw._mercNavGrid != undefined) {
            return AStarGrid(gw._mercNavGrid);
        }

        // 构建网格
        var cs:Number = NAV_CELL_SIZE;
        var xmin:Number = _root.Xmin;
        var xmax:Number = _root.Xmax;
        var ymin:Number = _root.Ymin;
        var ymax:Number = _root.Ymax;
        var cols:Number = Math.ceil((xmax - xmin) / cs);
        var rows:Number = Math.ceil((ymax - ymin) / cs);

        if (cols < 1)
            cols = 1;
        if (rows < 1)
            rows = 1;

        var nav:AStarGrid = new AStarGrid(cols, rows, true, false);

        // 对 collisionLayer 做 hitTest 采样，构建可走性矩阵
        var collisionLayer:MovieClip = _root.collisionLayer;
        var r:Number = 0;
        while (r < rows) {
            var c:Number = 0;
            while (c < cols) {
                // 格子中心的世界坐标
                var wx:Number = xmin + (c + 0.5) * cs;
                var wy:Number = ymin + (r + 0.5) * cs;
                // hitTest(x, y, true) 检查像素级碰撞
                if (collisionLayer.hitTest(wx, wy, true)) {
                    nav.setWalkable(c, r, false);
                }
                c++;
            }
            r++;
        }

        // 挂到 gameworld 上，设为不可枚举（不影响 for..in 遍历）
        gw._mercNavGrid = nav;
        _global.ASSetPropFlags(gw, ["_mercNavGrid"], 1, false);

        // 保存坐标转换参数
        gw._mercNavCellSize = cs;
        gw._mercNavXmin = xmin;
        gw._mercNavYmin = ymin;
        _global.ASSetPropFlags(gw, ["_mercNavCellSize", "_mercNavXmin", "_mercNavYmin"], 1, false);

        // _root.服务器.发布服务器消息("[佣兵AI] NavGrid构建: " + cols + "x" + rows + "=" + (cols * rows) + "格 bounds=(" + xmin + "," + ymin + ")-(" + xmax + "," + ymax + ")");

        return nav;
    }

    /** 世界坐标 → 格子坐标（双向钳制） */
    private static function worldToCell(worldVal:Number, origin:Number, cellSize:Number, maxCell:Number):Number {
        var c:Number = Math.floor((worldVal - origin) / cellSize);
        if (c < 0)
            return 0;
        if (c >= maxCell)
            return maxCell - 1;
        return c;
    }

    /**
     * 用 A* 搜索从 (sx,sy) 到 (ex,ey) 的路径，返回世界坐标 waypoint 数组。
     * 返回 null 表示不可达。
     */
    private static function findPathAStar(sx:Number, sy:Number, ex:Number, ey:Number):Array {
        var nav:AStarGrid = getNavGrid();
        var gw:MovieClip = _root.gameworld;
        var cs:Number = gw._mercNavCellSize;
        var ox:Number = gw._mercNavXmin;
        var oy:Number = gw._mercNavYmin;

        var navW:Number = nav.getWidth();
        var navH:Number = nav.getHeight();
        var sc:Number = worldToCell(sx, ox, cs, navW);
        var sr:Number = worldToCell(sy, oy, cs, navH);
        var ec:Number = worldToCell(ex, ox, cs, navW);
        var er:Number = worldToCell(ey, oy, cs, navH);

        // A* 搜索（限制展开节点数，避免极端卡帧）
        var gridPath:Array = nav.find(sc, sr, ec, er, nav.getWidth() * nav.getHeight());
        if (gridPath == null) {
            return null;
        }

        // 格子坐标 → 世界坐标
        var worldPath:Array = new Array(gridPath.length);
        var i:Number = 0;
        while (i < gridPath.length) {
            worldPath[i] = {x: ox + (gridPath[i].x + 0.5) * cs,
                    y: oy + (gridPath[i].y + 0.5) * cs};
            i++;
        }

        // 轴对齐路径平滑：只保留方向变化的拐点
        // 格栅路径中连续同方向的点（如一直向右走 10 格）合并为一步
        if (worldPath.length > 2) {
            var smoothed:Array = [worldPath[0]];
            var j:Number = 1;
            while (j < worldPath.length - 1) {
                var pdx:Number = worldPath[j].x - worldPath[j - 1].x;
                var pdy:Number = worldPath[j].y - worldPath[j - 1].y;
                var ndx:Number = worldPath[j + 1].x - worldPath[j].x;
                var ndy:Number = worldPath[j + 1].y - worldPath[j].y;
                // 方向变化 → 保留为拐点
                if (pdx != ndx || pdy != ndy) {
                    smoothed.push(worldPath[j]);
                }
                j++;
            }
            smoothed.push(worldPath[worldPath.length - 1]);
            worldPath = smoothed;
        }

        return worldPath;
    }


    // ═══════════════════════════════════════════
    //  状态实现
    // ═══════════════════════════════════════════

    // 思考
    public function think():Void {
        var self:MovieClip = data.self;

        var aliveFrames:Number = _root.帧计时器.当前帧数 - data.createdFrame;
        if (aliveFrames > ALIVE_MAX_TIME) {
            // _root.服务器.发布服务器消息("[佣兵AI] " + self._name + " 超时删除 alive=" + aliveFrames);
            self.删除可雇用单位();
            return;
        }
        data.updateSelf();

        // ── 如果已有未走完的 A* waypoint，直接继续 Walking ──
        if (data.waypoints != null && data.waypointIndex < data.waypoints.length && data.target != null) {
            // _root.服务器.发布服务器消息("[佣兵AI] " + self._name + " wp续行 " + data.waypointIndex + "/" + data.waypoints.length);
            this.superMachine.ChangeState("Walking");
            return;
        }

        var newstate:String = null;
        var engine:LinearCongruentialEngine = LinearCongruentialEngine.instance;

        // waypoint 复用已在上面 early-return，到这里需要重新搜索
        // 清除旧状态确保搜索逻辑执行（Bug2 修复：卡死恢复后必须 repath）
        data.target = null;
        data.waypoints = null;
        data.waypointIndex = 0;
        data.wpStallCount = 0;
        data.wpPrevDecisionIdx = -1;

        if (true) { // 始终执行门搜索（原条件 data.target==null 已由上面保证）
            // ── Phase 1: L-path 搜索可达的门 ──
            var 出生点列表:Array = [];
            var 全部门:Array = [];
            for (var 单位:String in _root.gameworld) {
                var 出生点:MovieClip = _root.gameworld[单位];
                if (出生点.是否从门加载主角 && 单位 != "出生地") {
                    全部门.push(出生点);
                    if (Mover.isReachable(self, 出生点, 50, _root.调试模式)) {
                        出生点列表.push(出生点);
                    }
                }
            }

            // _root.服务器.发布服务器消息("[佣兵AI] " + self._name + " 门搜索: 全部=" + 全部门.length + " L可达=" + 出生点列表.length + " pos=(" + Math.round(data.x) + "," + Math.round(data.z) + ")");

            if (出生点列表.length > 0) {
                // L-path 找到可达门
                data.target = engine.getRandomArrayElement(出生点列表);
                data.waypoints = null; // L-path 可达，不需要 waypoint
                data.waypointIndex = 0;
                data.wpStallCount = 0;
                data.wpPrevDecisionIdx = -1;
                data.updateTarget();
                // _root.服务器.发布服务器消息("[佣兵AI] " + self._name + " L-path→" + data.target._name + " dist=(" + Math.round(data.absdiff_x) + "," + Math.round(data.absdiff_z) + ")");

                if (_root.调试模式) {
                    var aabb:AABB = AABB.fromMovieClip(data.target, 0);
                    AABBRenderer.renderAABB(AABBCollider.fromAABB(aabb), 0, "filled");
                }

                if (data.absdiff_x < 100 && data.absdiff_z < 50) {
                    // 已靠近门——基于存活时间的体验优化
                    var aliveTime:Number = _root.帧计时器.当前帧数 - data.createdFrame;
                    if (aliveTime <= 100) {
                        newstate = engine.randomCheckThird() ? "Wandering" : "Idle";
                    } else if (aliveTime <= 200) {
                        var wanderingProbability:Number = 33 * (200 - aliveTime) / 100;
                        newstate = engine.successRate(wanderingProbability) ? "Wandering" : "Idle";
                    } else if (aliveTime <= 300) {
                        newstate = "Idle";
                    } else {
                        newstate = "Walking";
                    }
                } else {
                    newstate = engine.randomCheckHalf() ? "Idle" : "Walking";
                }

            } else if (全部门.length > 0) {
                // ── Phase 2: L-path 全部失败 → A* 回退 ──
                var bestDoor:MovieClip = null;
                var bestPath:Array = null;
                var i:Number = 0;
                while (i < 全部门.length) {
                    var door:MovieClip = 全部门[i];
                    var doorZ:Number = isNaN(door.Z轴坐标) ? door._y : door.Z轴坐标;
                    var path:Array = findPathAStar(data.x, data.z, door._x, doorZ);
                    if (path != null) {
                        bestDoor = door;
                        bestPath = path;
                        break;
                    }
                    i++;
                }

                if (bestDoor != null) {
                    data.target = bestDoor;
                    data.waypoints = bestPath;
                    data.waypointIndex = 0;
                    data.wpStallCount = 0;
                    data.wpPrevDecisionIdx = -1;
                    data.updateTarget();
                    newstate = "Walking";
                    // _root.服务器.发布服务器消息("[佣兵AI] " + self._name + " A*→" + bestDoor._name + " wp=" + bestPath.length);
                    // 按路径长度给足 walk 时长
                    var pathLen:Number = 0;
                    var j:Number = 1;
                    while (j < bestPath.length) {
                        var ddx:Number = bestPath[j].x - bestPath[j - 1].x;
                        var ddy:Number = bestPath[j].y - bestPath[j - 1].y;
                        pathLen += Math.sqrt(ddx * ddx + ddy * ddy);
                        j++;
                    }
                    var speed:Number = self.行走X速度;
                    if (isNaN(speed) || speed <= 0)
                        speed = 4;
                    data.think_threshold = Math.max(WALK_MAX_TIME, Math.ceil(pathLen / speed) + 10);

                    if (_root.调试模式) {
                        _root.发布消息("A* path: " + bestPath.length + " waypoints, " + Math.round(pathLen) + "px");
                    }
                } else {
                    // _root.服务器.发布服务器消息("[佣兵AI] " + self._name + " A*也无路! 门=" + 全部门.length);
                    newstate = "Wandering";
                }

            } else {
                // _root.服务器.发布服务器消息("[佣兵AI] " + self._name + " 场景无门");
                newstate = "Wandering";
            }
        }

        if (newstate == null) {
            newstate = engine.randomCheckHalf() ? "Idle" : "Walking";
        }

        // _root.服务器.发布服务器消息("[佣兵AI] " + self._name + " think→" + newstate + " alive=" + aliveFrames);
        this.superMachine.ChangeState(newstate);
    }

    // 移动
    public function walk():Void {
        var sm = this.superMachine;
        var self:MovieClip = data.self;
        var onDecisionTick:Boolean = ((sm.actionCount & 3) == 0);

        // ── 每 tick 都执行：waypoint 到达检查与推进 ──
        // 移动速度 ×4帧/action = 单次 action 的最大位移，作为到达半径
        // 确保 agent 不会因为速度过快而反复越过 waypoint
        if (data.waypoints != null && data.waypointIndex < data.waypoints.length) {
            data.updateSelf();
            var speed:Number = self.行走X速度;
            if (isNaN(speed) || speed <= 0)
                speed = 4;
            // 到达半径 = 单次 action 最大位移（speed × 4帧），至少 cell_size
            var WP_ARRIVE_SQ:Number = speed * 4;
            if (WP_ARRIVE_SQ < NAV_CELL_SIZE)
                WP_ARRIVE_SQ = NAV_CELL_SIZE;
            WP_ARRIVE_SQ = WP_ARRIVE_SQ * WP_ARRIVE_SQ;

            // 连续推进：可能一个 action 跨过了多个 waypoint
            while (data.waypointIndex < data.waypoints.length) {
                var wp:Object = data.waypoints[data.waypointIndex];
                var wpDx:Number = wp.x - data.x;
                var wpDz:Number = wp.y - data.z;
                if (wpDx * wpDx + wpDz * wpDz < WP_ARRIVE_SQ) {
                    data.waypointIndex++;
                    data.wpStallCount = 0;
                    data.wpPrevDecisionIdx = -1;
                } else {
                    break;
                }
            }
        }

        if (onDecisionTick) {
            // 1) 卡死检测
            var isStuck:Boolean = data.stuckProbeByDiffChange(true, 8, 3);
            if (isStuck) {
                // _root.服务器.发布服务器消息("[佣兵AI] " + self._name + " 卡死! pos=(" + Math.round(data.x) + "," + Math.round(data.z) + ") wp=" + (data.waypoints != null ? data.waypointIndex + "/" + data.waypoints.length : "null"));
                data.waypoints = null;
                data.waypointIndex = 0;
                data.wpStallCount = 0;
                data.wpPrevDecisionIdx = -1;
                this.superMachine.ChangeState("Wandering");
                // think() 会清除 target 并重新搜索（Bug2 修复）
                return;
            }

            // 2) 设置移动方向
            self.左行 = false;
            self.右行 = false;
            self.上行 = false;
            self.下行 = false;

            if (data.waypoints != null && data.waypointIndex < data.waypoints.length) {
                // ── A* waypoint 方向设定 ──
                var curWp:Object = data.waypoints[data.waypointIndex];
                var curDx:Number = curWp.x - data.x;
                var curDz:Number = curWp.y - data.z;

                // 停滞检测：比较跨 decision tick 的 waypointIndex
                if (data.waypointIndex == data.wpPrevDecisionIdx) {
                    // 与上个 decision tick 相同 → 累计停滞
                    data.wpStallCount++;
                    if (data.wpStallCount >= 3) {
                        data.waypointIndex++;
                        data.wpStallCount = 0;
                        data.wpPrevDecisionIdx = -1;
                        if (data.waypointIndex >= data.waypoints.length) {
                            data.waypoints = null;
                            data.waypointIndex = 0;
                            data.wpStallCount = 0;
                            data.wpPrevDecisionIdx = -1;
                        } else {
                            curWp = data.waypoints[data.waypointIndex];
                            curDx = curWp.x - data.x;
                            curDz = curWp.y - data.z;
                        }
                    }
                } else {
                    // 有推进 → 归零
                    data.wpStallCount = 0;
                    data.wpPrevDecisionIdx = -1;
                }
                data.wpPrevDecisionIdx = data.waypointIndex;

                if (data.waypoints != null && data.waypointIndex < data.waypoints.length) {
                    self.左行 = curDx < -10;
                    self.右行 = curDx > 10;
                    self.上行 = curDz < -5;
                    self.下行 = curDz > 5;
                }

            } else if (data.waypoints != null && data.waypointIndex >= data.waypoints.length) {
                // 所有 waypoint 走完 → 清路径，直奔目标
                data.waypoints = null;
                data.waypointIndex = 0;
                data.wpStallCount = 0;
                data.wpPrevDecisionIdx = -1;
                data.updateTarget();
                if (data.absdiff_x > 20) {
                    self.左行 = (data.diff_x < 0);
                    self.右行 = (data.diff_x > 0);
                }
                if (data.absdiff_z > 10) {
                    self.上行 = (data.diff_z < 0);
                    self.下行 = (data.diff_z > 0);
                }

            } else {
                // ── 原版直线移动（L-path 可达时）──
                data.updateTarget();
                if (data.absdiff_x > 20) {
                    self.左行 = (data.diff_x < 0);
                    self.右行 = (data.diff_x > 0);
                }
                if (data.absdiff_z > 10) {
                    self.上行 = (data.diff_z < 0);
                    self.下行 = (data.diff_z > 0);
                }
            }
        } else {
            // 非判定帧：只更新目标坐标
            data.updateTarget();
        }

        // 到达判定
        if (data.absdiff_x < 50 && data.absdiff_z < 25) {
            // _root.服务器.发布服务器消息("[佣兵AI] " + data.self._name + " 到达门! alive=" + (_root.帧计时器.当前帧数 - data.createdFrame) + " 方式=" + (data.waypoints != null ? "A*" : "L-path"));
            data.self.删除可雇用单位();
            return;
        }
    }

    // 进入移动状态
    public function walk_enter():Void {
        // 如果有 A* waypoint，think() 中已设置 think_threshold，不覆盖
        if (data.waypoints == null || data.waypointIndex >= data.waypoints.length) {
            data.think_threshold = LinearCongruentialEngine.instance.randomIntegerStrict(WALK_MIN_TIME, WALK_MAX_TIME);
        }
    }

    // 进入停止状态
    public function idle_enter():Void {
        data.self.左行 = false;
        data.self.右行 = false;
        data.self.上行 = false;
        data.self.下行 = false;
        data.think_threshold = LinearCongruentialEngine.instance.randomIntegerStrict(IDLE_MIN_TIME, IDLE_MAX_TIME);
    }

    // 进入漫游状态
    public function wander_enter():Void {
        data.target = null;
        data.updateSelf();

        var self:MovieClip = data.self;
        var engine:LinearCongruentialEngine = LinearCongruentialEngine.instance;

        data.think_threshold = engine.randomIntegerStrict(WANDER_MIN_TIME, WANDER_MAX_TIME);

        if (data.standby) {
            self.左行 = false;
            self.右行 = false;
            self.上行 = false;
            self.下行 = false;
            return;
        }

        var maxAttempts:Number = 10;
        var foundTarget:Boolean = false;
        var randx:Number;
        var randy:Number;

        for (var i:Number = 0; i < maxAttempts; i++) {
            randx = engine.randomIntegerStrict(_root.Xmin, _root.Xmax);
            randy = engine.randomIntegerStrict(_root.Ymin, _root.Ymax);
            if (Mover.isReachableToPoint(self, randx, randy, 30, false)) {
                foundTarget = true;
                break;
            }
        }

        if (!foundTarget) {
            randx = engine.randomIntegerStrict(_root.Xmin, _root.Xmax);
            randy = engine.randomIntegerStrict(_root.Ymin, _root.Ymax);
        }

        self.左行 = randx < data.x;
        self.右行 = !self.左行;
        self.上行 = randy < data.z;
        self.下行 = randy > data.z;
    }
}
