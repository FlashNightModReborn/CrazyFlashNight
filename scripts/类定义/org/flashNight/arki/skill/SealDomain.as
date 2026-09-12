// 路径: org/flashNight/arki/skill/SealDomain.as
import org.flashNight.aven.Coordinator.*;
/**
 * SealDomain — 「天启大封印」的封印领域运行时
 *
 * 职责（全部在 AS2 侧，无需改动 flashswf 资产）：
 *   1. 在「落成那一刻的宿主坐标」上钉一个范围：X 左右各 300，Z 上下不对称 ——
 *      比中心更小的一侧纵深 200、更大的一侧只留 40 的容差（详见 范围半径Z /
 *      下方容差Z 的注释）。
 *      落成瞬间把范围内的敌方单位全部收押，之后每秒再补收一次新走进来的；
 *   2. 宿主**落成后不再移动**（吸附/跟随是「法阵」的活，法阵在落成前就撤掉了）；
 *   3. 封印期间把单位完全定住：短路其移动/状态/攻击等自有函数、冻结新版 AI、停时间轴、
 *      每帧把位置与朝向复位，并置 无敌 = true（不受任何伤害）；
 *   4. 放逐是**并集二选一**：① 带「凡俗」定位标签的，收押当帧直接放逐；② 没标签的
 *      按持续时间累积封印强度（每秒 5000），强度越过该单位的「额度」时放逐——
 *      达标后先放「驱逐白瀑」特效 + 播「黑闪.wav」音效，再走完整的正常死亡判定
 *      （计入清怪数、结算经验与掉落）后消失；不走血腥死动画、不贴尸体；
 *   5. 到达最大时长（50 秒）仍未达标的单位（不含①），毫发无伤地解除控制；
 *   6. 结束时把短路函数、AI 冻结位、无敌、位置、速度逐项还原，不留下"依然打不到/依然不能动"的残状态。
 *
 * ⚠ 强度是**逐单位独立累计**的：每个单位从自己被收押的那一刻开始攒，
 *   而不是共用领域的总强度。所以晚走进范围的敌人不会被"提前放逐"，
 *   它同样享有完整的 每秒强度 × 时间 过程。
 *
 * 单位额度公式（可调）：
 *   额度 = 血量上限 × 血量系数(1) + 防御力 × 防御系数(50) + 空手攻击力 × 攻击系数(100)
 *
 * 强度曲线（可调）：
 *   强度(t) = 每秒强度(5000) × 该单位已被封印的秒数     → 单个单位 50 秒最多累计 250000
 *   强度 >= 额度 时该单位被放逐；额度高于 250000 的单位必然存活。
 *
 * 用法（由「天启大封印」元件的帧脚本调用）：
 *   this.封印状态 = org.flashNight.arki.skill.SealDomain.封(this);
 *   // this 上需带：施术者(可选，缺省取 _root.控制目标)
 *
 * @author flashNight
 */
class org.flashNight.arki.skill.SealDomain {

    // ════════════════════════════════════════════════════════════════════
    // 可调数值 —— 只改这一段即可，其余逻辑不依赖具体取值
    // ════════════════════════════════════════════════════════════════════

    /** 封印总时长（秒）。到点后未达额度的单位原样放回。 */
    public static var 总时长秒:Number = 50;

    /** 每秒累积的封印强度。 */
    public static var 每秒强度:Number = 5000;

    /** 额度公式系数：额度 = 血量上限×血量系数 + 防御力×防御系数 + 空手攻击力×攻击系数 */
    public static var 血量系数:Number = 1;
    public static var 防御系数:Number = 50;
    public static var 攻击系数:Number = 100;

    /** X 轴判定半径（像素）：中心左右各 300。 */
    public static var 范围半径X:Number = 300;

    /**
     * Z 轴判定纵深（像素）：**单位比中心更小（视觉上更靠上）**时，小出去的幅度上限。
     *
     * 为什么上下不对称：宿主元件的原点被摆在参考点下方 `主动战技函数.长枪.天启大封印.法阵Y偏移`
     * （默认 +50）处，而封印的视觉中心仍在参考点脚下 —— 中心 Z 读的是宿主 `_y`，比被封印单位的
     * `Z轴坐标` 天然大那么多。所以「上方」给足纵深、「下方」只给一条贴边的容差（下方容差Z）。
     *
     * ⚠ 改这个值只影响纵深，不影响左右；法阵素材的高度若与判定不一致，
     *   需要在元件里调图形，不要反过来把判定改成对称。
     */
    public static var 范围半径Z:Number = 200;

    /**
     * Z 轴**下方**容差（像素）：单位比中心更大（视觉上更靠下）时，大出去多少还算命中。
     *
     * 元件整体又往下挪了一段（约 40），比中心略低的单位在画面上仍被法阵压住，
     * 所以这里留一条窄边；再往下就不是这个法阵罩的范围了。
     */
    public static var 下方容差Z:Number = 40;

    /**
     * 每隔多少帧补收一次新走进范围的敌人（1 = 每帧，越大越省）。
     *
     * 默认 30 = 每秒判定一次（30fps 下 30 帧 = 1 秒），即"封印领域落成后，
     * 每秒检查一次有没有新敌人走进范围，走进来就一并封印"。
     * 想更灵敏就调小（15 是半秒），想更省就调大；改这一个常量即可。
     */
    public static var 补收间隔帧:Number = 30;

    /**
     * 「立即放逐」定位标签：带这个标签的单位（挂在其 `魔法抗性` 表上，与
     * `UnitUtil.getEliteLevel` 读 `首领`/`精英` 同一套口径）不做数值筛选，
     * **收押当帧直接放逐**；没带的照旧走强度累积。
     *
     * ⚠ 千万别把 `凡俗` 写进 `MagicDamageTypes.magicDamageTypesHash` ——
     *   那份清单会被默认抗性补全灌给**每个**单位，等于给全场打标签、全屏秒杀。
     */
    public static var 立即放逐标签:String = "凡俗";

    /**
     * 被放逐瞬间播放的消失特效名（库链接名，挂在 gameworld 上，元件播完自己注销）。
     *
     * 现在填的就是「天启大封印驱逐白瀑」：从单位脚下窜起的白色瀑布状光幕。
     * 留空 = 只做消失不做特效。
     */
    public static var 消失特效名:String = "天启大封印驱逐白瀑";

    /**
     * 被放逐瞬间播放的音效（sounds/export 下的**文件名**，音效系统按文件名索引，
     * 不用带子目录）。留空 = 不播。
     */
    public static var 消失音效名:String = "黑闪.wav";

    /** 递归停时间轴的最大深度，防止遍历失控。 */
    private static var 停时间轴最大深度:Number = 3;

    // ════════════════════════════════════════════════════════════════════
    // 内部状态
    // ════════════════════════════════════════════════════════════════════

    /**
     * 封印期间需要短路的"单位自有函数"名单。
     * 敌人的战斗 AI 有一部分写在元件框的 onClipEvent(enterFrame) 里，靠调用
     * _parent.行走() / _parent.攻击() 之类驱动；这类调用最终都会落到单位自己的函数上，
     * 所以把它们换成空函数即可整段掐掉。只劫持单位上确实存在的函数，不凭空造字段。
     */
    private static var 短路函数名单:Array = [
        "行走", "移动", "被击移动", "强制移动",
        "方向改变", "状态改变", "攻击",
        "攻击时移动", "攻击时四向移动",
        "X轴追踪移动", "Z轴追踪移动", "固定角度移动"
    ];

    /** 共用空函数（惰性创建，避免类静态初始化顺序问题）。 */
    private static var 空操作:Function;

    private static function 取空操作():Function {
        if (SealDomain.空操作 == undefined) {
            SealDomain.空操作 = function():Void {
            };
        }
        return SealDomain.空操作;
    }

    private static function 取帧率():Number {
        var 率:Number = NaN;
        if (_root.帧计时器 != undefined && _root.帧计时器.帧率 != undefined) {
            率 = Number(_root.帧计时器.帧率);
        }
        if (isNaN(率) || 率 <= 0) {
            率 = 30;
        }
        return 率;
    }

    private static function 取数(值, 缺省:Number):Number {
        var 数:Number = Number(值);
        if (isNaN(数)) {
            return 缺省;
        }
        return 数;
    }

    // ════════════════════════════════════════════════════════════════════
    // 额度
    // ════════════════════════════════════════════════════════════════════

    /**
     * 计算单位的封印额度。血量取上限（hp满血值），避免残血单位被误判成弱小。
     */
    public static function 取额度(单位:MovieClip):Number {
        if (单位 == undefined) {
            return 0;
        }
        var 血:Number = 取数(单位.hp满血值, NaN);
        if (isNaN(血)) {
            // 极少数单位只挂 hp，没有上限字段
            血 = 取数(单位.hp, 0);
        }
        var 防:Number = 取数(单位.防御力, 0);
        var 攻:Number = 取数(单位.空手攻击力, 0);
        return 血 * SealDomain.血量系数
            + 防 * SealDomain.防御系数
            + 攻 * SealDomain.攻击系数;
    }

    // ════════════════════════════════════════════════════════════════════
    // 对外入口
    // ════════════════════════════════════════════════════════════════════

    /**
     * 落成一座封印领域。
     *
     * 中心 = 宿主**落成当帧**的坐标，之后不再改变（宿主也不移动）。
     * 调用方（落成 / 落成子弹）应保证宿主已经落在「法阵消失前所在位置」上。
     *
     * @param 宿主:MovieClip 承载封印视觉的元件（子弹元件），用作中心点与生命周期锚点
     * @return Object 封印状态对象，宿主被卸载时会自动终止
     */
    public static function 封(宿主:MovieClip):Object {
        if (宿主 == undefined) {
            return null;
        }

        var 状态:Object = {
            宿主: 宿主,
            施术者: 宿主.施术者,
            中心X: 取数(宿主._x, 0),
            中心Z: 取数(宿主._y, 0),
            已存续帧: 0,
            记录表: [],
            任务ID: null,
            已结束: false
        };

        if (状态.施术者 == undefined) {
            状态.施术者 = _root.gameworld[_root.控制目标];
        }

        // 宿主被卸载（换场景 / 元件移除）时必须还原现场，否则敌人会被永久冻结。
        // ⚠ 优先走 EventCoordinator 的卸载链：宿主一旦被 addUnloadCallback /
        //    addLifecycleTask 碰过，它的 onUnload 会被 EventCoordinator 换成 proxy
        //    并 watch 住，直接赋值写不进去（新函数会被塞进 __EC_userUnload__）。
        SealDomain.挂卸载回调(宿主, function():Void {
            org.flashNight.arki.skill.SealDomain.终止(状态);
        });

        // 停止的兜底：宿主元件自己的帧脚本若在循环里再次 stop()（或调了封印接口里的 _停播），
        // 把这个补丁重新装上。每帧只是给本级挂一个空 onEnterFrame，开销可忽略；
        // 一旦本级被停住就不再重复挂，避免和元件自身逻辑无谓拉扯。
        var 帧任务本体:Function = function():Void {
            org.flashNight.arki.skill.SealDomain.每帧(状态);
            SealDomain.确保播放(状态.宿主);
        };
        状态.任务ID = _root.帧计时器.添加循环任务(帧任务本体, 1);

        // 落成当帧立刻收押一批，避免出现一帧的控制空窗
        SealDomain.补收(状态);
        SealDomain.每帧(状态);
        return 状态;
    }

    /**
     * 确保宿主自身的播放头没被停住。
     *
     * 宿主元件（如 天启大封印）自己就是整条美术时间轴，靠帧脚本做
     * 「爆发 1~15 → 第 30 帧 gotoAndPlay(16) → 循环 16~30」的播放头控制。
     * 一旦宿主被本级 stop()（帧脚本里手写的 stop()、或误调了 _停播），
     * 它会卡死在第 1 帧：爆发段不播、也永远进不了循环 —— 表现就是「元件卡住不动」。
     *
     * 这里给宿主补一个空的 onEnterFrame 恢复自动推进。空的 onEnterFrame 在 AVM1 里
     * 就等于「每帧被访问一次」，足以打破 stop 冻结。**只挂空实现**，不写业务逻辑：
     * 这样既不与元件自身的 onEnterFrame 冲突（有的话会被本函数跳过），也不会递归干扰。
     *
     * 幂等：本级已在推进就不重复挂。
     */
    public static function 确保播放(宿主:MovieClip):Void {
        if (宿主 == undefined || 宿主._parent == undefined) {
            return;
        }
        if (宿主.onEnterFrame == undefined) {
            宿主.onEnterFrame = function():Void {};
        }
    }

    /**
     * 往宿主的「卸载」链上挂一个回调。
     *
     * 为什么不直接 `宿主.onUnload = …`：
     * EventCoordinator 的自动清理（addUnloadCallback / addLifecycleTask / 任何
     * addEventListener）会把 `target.onUnload` 换成自己的 proxy，再 `watch("onUnload")`；
     * watch 处理器一律 `return oldVal`，也就是**之后所有对 onUnload 的直接赋值都会被丢弃**。
     * 而宿主一旦被别的系统注册过生命周期任务（本项目的宿主在 gameworld 下很容易碰到），
     * 裸赋值就是静默失效 —— 换场景时封印不会被终止，敌人会被永久冻住。
     *
     * 所以这里优先走 EventCoordinator；拿不到再退化为裸赋值（保留旧行为兜底）。
     */
    public static function 挂卸载回调(目标:MovieClip, 回调:Function):Void {
        if (目标 == undefined || 回调 == undefined) {
            return;
        }
        if (EventCoordinator != undefined && EventCoordinator.addUnloadCallback != undefined) {
            EventCoordinator.addUnloadCallback(目标, 回调);
            return;
        }
        // 退化路径：没有 EventCoordinator 时（早期加载阶段）才用裸链式包装
        var 原卸载 = 目标.onUnload;
        目标.onUnload = function():Void {
            回调();
            if (typeof 原卸载 == "function") { 原卸载(); }
        };
    }

    /**
     * 结束封印：先放逐所有已达额度的单位，再把其余单位原样放回。
     * 幂等，可被 onUnload / 定时 / 手动重复调用。
     */
    public static function 终止(状态:Object):Void {
        if (状态 == undefined || 状态.已结束 === true) {
            return;
        }
        状态.已结束 = true;

        // 到点：所有仍在控制中的单位，先按额度做最后一轮结算，再原样放回。
        // ⚠ 判定用 记录.强度（各单位自己的累计），不是 状态.强度 ——
        //    否则到期那一刻，刚被抓进来没多久的敌人会被误放逐。
        var 记录表:Array = 状态.记录表;
        for (var i:Number = 0; i < 记录表.length; i++) {
            var 记录:Object = 记录表[i];
            var 单位:MovieClip = 记录.单位;
            if (单位 == undefined || 单位._parent == undefined) {
                continue;
            }
            if (单位.hp > 0 && 记录.强度 >= 记录.额度) {
                SealDomain.放逐(状态, 记录);
            } else {
                SealDomain.解除单位(记录);
            }
        }
        记录表.length = 0;

        状态.宿主 = null;
        状态.施术者 = null;

        if (状态.任务ID != null) {
            _root.帧计时器.移除任务(状态.任务ID);
            状态.任务ID = null;
        }
    }

    /**
     * 解除单个单位的一切封印副作用，使其"毫发无伤"地恢复行动。
     * 顺序很重要：先还函数，再还状态，最后才动位置/速度。
     */
    private static function 解除单位(记录:Object):Void {
        var 单位:MovieClip = 记录.单位;
        if (单位 == undefined || 单位._parent == undefined) {
            return;
        }

        // 1) 还原被短路的函数
        for (var 名:String in 记录.短路表) {
            单位[名] = 记录.短路表[名];
        }
        记录.短路表 = null;

        // 2) 还原 AI 冻结位与无敌
        单位._封印冻结 = 记录.AI冻结原;
        单位.无敌 = 记录.无敌原;

        // 3) 位置与速度复位
        单位._x = 记录.X;
        单位._y = 记录.Y;
        单位.Z轴坐标 = 记录.Z;
        if (记录.行走X速度原 != undefined) {
            单位.行走X速度 = 记录.行走X速度原;
        }

        // 4) 清掉方向输入，让 AI 下一帧自行重新决策
        单位.左行 = false;
        单位.右行 = false;
        单位.上行 = false;
        单位.下行 = false;

        // 5) 恢复时间轴（与 _root.敌人函数.硬直 的 stop/play 约定保持一致）
        //    时间轴恢复后，元件框上的 onClipEvent 会重新驱动 行走/状态改变，单位即可行动
        SealDomain.恢复时间轴(记录);

        单位.__封印领域 = null;
    }

    // ════════════════════════════════════════════════════════════════════
    // 每帧驱动
    // ════════════════════════════════════════════════════════════════════

    private static function 每帧(状态:Object):Void {
        if (状态 == undefined || 状态.已结束 === true) {
            return;
        }

        var 宿主:MovieClip = 状态.宿主;
        if (宿主 == undefined || 宿主._parent == undefined) {
            SealDomain.终止(状态);
            return;
        }

        var 率:Number = 取帧率();
        状态.已存续帧++;

        // 宿主落成后**静止不动**：中心就是落成那一刻的坐标（= 法阵消失前所在位置）。
        // 吸附敌人是「法阵」的职责，法阵在落成时已经被撤掉 / 转交；
        // 封印领域本身是一根钉在地上的光柱，不再追人。
        // 强度不是领域级的 —— 每个单位各自累计（见下方循环里的 记录.强度）。

        // 周期性补收新走进范围的敌人（每帧全量扫 gameworld 太浪费，改抽样）
        if (状态.已存续帧 % SealDomain.补收间隔帧 == 0) {
            SealDomain.补收(状态);
        }

        // 逐帧复位 + 额度判定（倒序遍历，便于就地剔除）
        var 记录表:Array = 状态.记录表;
        for (var i:Number = 记录表.length - 1; i >= 0; i--) {
            var 记录:Object = 记录表[i];
            var 单位:MovieClip = 记录.单位;
            if (单位 == undefined || 单位._parent == undefined) {
                记录表.splice(i, 1);
                continue;
            }
            if (单位.hp <= 0) {
                // 已被别处结算掉（理论上不会，封印期间无敌），直接摘除记录
                SealDomain.解除单位(记录);
                记录表.splice(i, 1);
                continue;
            }
            SealDomain.复位单位(记录);

            // ⚠ 强度按「单位各自被封印那一刻」起算，而不是全领域统一从技能开始累计。
            //    所以累加与判定都必须落在 记录 上：晚进来的敌人只能从它的 0 开始攒。
            记录.已存续帧++;
            记录.强度 += SealDomain.每秒强度 / 率;
            // 并集二选一：带 立即放逐标签 的（补收发生在本循环之前，所以当帧就到这）
            // 与强度达标的一律放逐；没标签且没达标的继续攒。
            if (记录.立即放逐 || 记录.强度 >= 记录.额度) {
                SealDomain.放逐(状态, 记录);
                记录表.splice(i, 1);
            }
        }

        // 到点收工
        if (状态.已存续帧 >= Math.round(SealDomain.总时长秒 * 率)) {
            SealDomain.终止(状态);
        }
    }

    /** 每帧把单位钉回原位。 */
    private static function 复位单位(记录:Object):Void {
        var 单位:MovieClip = 记录.单位;
        单位._x = 记录.X;
        单位._y = 记录.Y;
        单位.Z轴坐标 = 记录.Z;
        单位.无敌 = true;
        单位.左行 = false;
        单位.右行 = false;
        单位.上行 = false;
        单位.下行 = false;
        if (记录.行走X速度原 != undefined) {
            单位.行走X速度 = 0;
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // 收押 / 放逐
    // ════════════════════════════════════════════════════════════════════

    /**
     * 这个单位是不是「可以被封印的目标」。
     *
     * 阵营口径与 `UnitUtil.isEnemy` / `FactionManager.getFactionFromUnit` 一致：
     * `是否为敌人` 只有明确的 `false` / `"false"`（友方）才排除；
     * `true` / `"true"` 是敌人，**`null` / `undefined` / `"null"` 是中立，一并收押**。
     * （游戏里中立单位死掉同样计经验，一直就是按敌对处理的。）
     *
     * ⚠ 但 `_root.gameworld` 下还挂着法阵、特效、子弹这些**不是单位**的元件，
     *   它们的 `是否为敌人` 同样是 undefined —— 照纯阵营口径会被全当成"中立"收进来，
     *   连宿主自己都会被自己封住。所以额外要求具备单位特征：
     *   有 `死亡检测` 函数或 `hp满血值` 字段（两者都没有就不是单位）。
     *   宿主与施术者本身也直接排除。
     */
    private static function 是可封印目标(单位:MovieClip, 状态:Object):Boolean {
        if (单位 == undefined || 单位 == null || 单位._parent == undefined) {
            return false;
        }
        if (状态 != undefined && 状态 != null) {
            if (单位 === 状态.宿主 || 单位 === 状态.施术者) {
                return false;
            }
        }
        var 像单位:Boolean = (typeof 单位.死亡检测 == "function") || (单位.hp满血值 != undefined);
        if (!像单位) {
            return false;
        }
        var 是敌 = 单位.是否为敌人;
        if (是敌 === false || 是敌 === "false") {
            return false;                 // 明确的友方：不收
        }
        return true;                      // true / "true" / null / undefined（中立）都收
    }

    /** 扫描 gameworld，把椭圆范围内尚未被封印的敌人收押进来。 */
    private static function 补收(状态:Object):Void {
        var 世界:MovieClip = _root.gameworld;
        if (世界 == undefined) {
            return;
        }
        var 半径Xsq:Number = SealDomain.范围半径X * SealDomain.范围半径X;

        for (var 名:String in 世界) {
            var 单位:MovieClip = 世界[名];
            if (单位 == undefined || 单位._parent == undefined) {
                continue;
            }
            // 只封"敌对 / 中立"的单位（含中立的判定见 是可封印目标）
            if (!SealDomain.是可封印目标(单位, 状态)) {
                continue;
            }
            if (单位.__封印领域 != undefined && 单位.__封印领域 != null) {
                continue;
            }
            if (单位.hp <= 0) {
                continue;
            }
            if (单位.斗兽标定隔离 === true) {
                continue;
            }
            var dx:Number = 单位._x - 状态.中心X;
            // 不对称纵深：中心 Z 读宿主 _y，比参考点低 法阵Y偏移、而元件又整体下挪了一段，
            // 所以「单位在中心上方」给整套 范围半径Z，「单位在中心下方」只给 下方容差Z。
            var dz:Number = 状态.中心Z - 单位.Z轴坐标;   // >0 = 单位比中心更靠上
            if (dz > SealDomain.范围半径Z || -dz > SealDomain.下方容差Z) {
                continue;
            }
            // X 走椭圆口径：上下各按自己那半的 Z 半径收窄
            var 本侧半径Z:Number = (dz >= 0) ? SealDomain.范围半径Z : SealDomain.下方容差Z;
            if (dx * dx / 半径Xsq + dz * dz / (本侧半径Z * 本侧半径Z) > 1) {
                continue;
            }
            SealDomain.收押(状态, 单位);
        }
    }

    /**
     * 单位是否带 立即放逐标签（如「凡俗」）。
     *
     * 定位标签的真身是 `单位.魔法抗性` 表里的一个键
     * （来源：enemy_properties XML 的 `<魔法抗性>` 节点，敌人模板逐键拷到单位上）。
     * 用 `isNaN(取数(...))` 而非 `!= undefined`：XML 读出来的值常是字符串，
     * `Number("0") == 0` 走 isNaN 正好能识别「键存在且有数值/可转数值」。
     */
    private static function 有立即放逐标签(单位:MovieClip):Boolean {
        var 抗性表:Object = 单位.魔法抗性;
        if (抗性表 == undefined || 抗性表 == null) {
            return false;
        }
        return !isNaN(SealDomain.取数(抗性表[SealDomain.立即放逐标签], NaN));
    }

    /** 把单个单位纳入封印。 */
    private static function 收押(状态:Object, 单位:MovieClip):Boolean {
        if (单位 == undefined || 单位._parent == undefined || 单位.hp <= 0) {
            return false;
        }

        var 记录:Object = {
            单位: 单位,
            X: 取数(单位._x, 0),
            Y: 取数(单位._y, 0),
            Z: 取数(单位.Z轴坐标, 取数(单位._y, 0)),
            无敌原: 单位.无敌 === true,
            AI冻结原: 单位._封印冻结,
            行走X速度原: 单位.行走X速度,
            记录表_停过的: [],
            短路表: new Object(),
            额度: SealDomain.取额度(单位),
            // 放逐是并集二选一：带 立即放逐标签 的不攒强度，收押当帧直接放逐；
            // 没带的照旧 —— 只有强度攒过额度才放逐。判定见 每帧 里的分支。
            立即放逐: SealDomain.有立即放逐标签(单位),
            // ⚠ 强度是**逐单位独立累计**的：每个单位从自己被抓进来的那一刻开始攒，
            //    而不是共用 状态.强度（那样晚进来的敌人会"白嫖"前面攒的进度）。
            强度: 0,
            已存续帧: 0
        };

        // 1) 短路单位自有函数：元件框 onClipEvent 里的 _parent.行走() 之类到此为止
        var 名单:Array = SealDomain.短路函数名单;
        for (var i:Number = 0; i < 名单.length; i++) {
            var 函数名:String = 名单[i];
            if (typeof 单位[函数名] == "function") {
                记录.短路表[函数名] = 单位[函数名];
                单位[函数名] = SealDomain.取空操作();
            }
        }

        // 2) 冻结新版 AI（配合 UpdateEventComponent 里的 _封印冻结 守卫）
        单位._封印冻结 = true;

        // 3) 停时间轴：把帧脚本（思考/攻击/寻找目标）与动画一起冻住
        SealDomain.停时间轴(单位, 0, 记录);

        // 4) 无敌 + 钉位 + 清掉方向输入
        单位.无敌 = true;
        单位.左行 = false;
        单位.右行 = false;
        单位.上行 = false;
        单位.下行 = false;
        单位.行走X速度 = 0;
        单位._x = 记录.X;
        单位._y = 记录.Y;
        单位.Z轴坐标 = 记录.Z;

        单位.__封印领域 = 状态;
        状态.记录表.push(记录);
        return true;
    }

    /**
     * 放逐一个单位：**先**放驱逐特效 + 音效，再走完整的正常死亡判定
     * （计入清怪数、结算经验与掉落），但不播血腥死动画、不贴尸体。
     *
     * 效果元件的生命周期由它自己管（播完 removeMovieClip 注销），
     * 这里不挂帧计时器、不做延时任务 —— 单位照常在当帧被结算掉，
     * 白瀑特效继续留在原地播完，视觉上就是"被白光吞掉再消失"。
     */
    private static function 放逐(状态:Object, 记录:Object):Void {
        var 单位:MovieClip = 记录.单位;
        var 消失X:Number = 单位._x;
        var 消失Y:Number = 单位._y;

        // ① 特效：白色瀑布状白光从脚下窜起（forceTrigger = 无视数量上限/概率剔除）
        var 特效名:String = SealDomain.消失特效名;
        if (特效名 != undefined && 特效名 != "" && 特效名 != null) {
            if (typeof EffectSystem != "undefined" && EffectSystem.Effect != undefined) {
                EffectSystem.Effect(特效名, 消失X, 消失Y, 100, true);
            }
        }

        // ② 音效：黑闪.wav
        var 音效名:String = SealDomain.消失音效名;
        if (音效名 != undefined && 音效名 != "" && 音效名 != null) {
            if (typeof _root.播放音效 == "function") {
                _root.播放音效(音效名);
            }
        }

        // ③ 还原 + 死亡结算
        SealDomain.解除单位(记录);

        单位.hp = 0;
        if (typeof 单位.死亡检测 == "function") {
            // noCorpse：不留尸体（消失而非血腥死）；不传 noCount，让清怪数与过图目标正常结算
            单位.死亡检测({noCorpse: true, remainMovie: false});
        } else {
            单位.removeMovieClip();
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // 时间轴冻结 / 恢复
    // ════════════════════════════════════════════════════════════════════

    /** 停止单位及其子元件的时间轴（浅递归），并记录哪些元件被停过。 */
    private static function 停时间轴(节点, 深度:Number, 记录:Object):Void {
        if (深度 > SealDomain.停时间轴最大深度) {
            return;
        }
        if (typeof 节点 != "movieclip") {
            return;
        }
        记录.记录表_停过的.push(节点);
        节点.stop();

        for (var 子键:String in 节点) {
            var 子 = 节点[子键];
            // ⚠ 必须验证 _parent === 节点：for in 除了真子元件，还会枚举**引用型动态属性**。
            //   敌人身上只要存有指向其他单位的 MovieClip 引用（攻击/技能/特效元件运行时写的），
            //   typeof 就是 "movieclip"，裸递归会把**玩家**当成"子元件"停掉——
            //   封印期间玩家被冻结、封印结束又被 恢复时间轴 play 回来，
            //   即"有概率冻住玩家"的根源（旧 时间停止 元件的 for in stop 同病）。
            if (typeof 子 == "movieclip" && 子._parent === 节点) {
                SealDomain.停时间轴(子, 深度 + 1, 记录);
            }
        }
    }

    /** 恢复被停过的时间轴。用 play 续播，不重放当前帧脚本。 */
    private static function 恢复时间轴(记录:Object):Void {
        var 列表:Array = 记录.记录表_停过的;
        if (列表 == undefined) {
            return;
        }
        for (var i:Number = 0; i < 列表.length; i++) {
            var 节点 = 列表[i];
            if (节点 != undefined && typeof 节点 == "movieclip" && 节点._parent != undefined) {
                节点.play();
            }
        }
        记录.记录表_停过的 = null;
    }
}
