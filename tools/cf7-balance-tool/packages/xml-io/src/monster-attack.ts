/**
 * 怪物攻击结构实测 — 从 XFL 目录或 .fla 包量出每只怪的有效招式、前摇帧数、段数与倍率。
 *
 * 攻速系数 / 攻击倍率 / 段数系数是**观测值**，不由面板反推：面板只约束三者与速度系数的乘积，
 * 反推出来的拆分既不唯一也不代表设计意图。这里的量法以制作组口径为准：
 * - 段数 = 一次攻击里所有子弹实例的 霰弹值 之和（一颗子弹 霰弹值=3 算 3 段）；
 *   一颗子弹里多次 `霰弹值 = n` 取均值，`+=` 才算追加，没有 霰弹值 的子弹按 1 段算，`最小霰弹值` 不计。
 * - 段数窗口量子弹跨度：第一个子弹实例帧到最后一个子弹实例帧，不满一个窗口算 1 次，
 *   满窗口按 跨度/窗口 取小数次数（制作组 2026-10-04 口径，不再按整段动画长度 ceil 补成整数）。
 * - 段数只算**打得中玩家的子弹**（制作组 2026-10-04 口径）。近战类才管：`子弹种类` 含近战词
 *   （裸写 `子弹种类 = "近战子弹"` 与 `子弹属性.子弹种类 = "近战联弹"` 两种写法都认），
 *   没声明时退回子弹元件自己的名字；非近战是线状判定、不会同屏摆一堆无效子弹，一律不折。
 *   联弹的单元体铺开、霰弹值打不满，按 linkageFactor 折分量 —— 制作组 2026-10-06 改口：
 *   横向联弹（种类含 linkageHorizontalWords，`横向机枪联弹` 也算横向）无条件折，不看有没有传 `子弹属性.区域定位area`；
 *   纵向联弹（含 `纵向机枪联弹`，认 linkageVerticalWords）一律不折；近战联弹与其余联弹保持要传 area 才折。
 *   没传 area 的早期怪子弹只有一个小命中点，几帧内在屏幕各处摆一大把也只有一小部分中得上人，
 *   按"一拨"（clusterFrames 帧内，即同一帧或相邻帧）折成有效颗数：
 *   cap 法每拨最多算 clusterCap 颗；hitbox 法按玩家命中框（hitboxWidth×hitboxHeight）能框住的最大颗数算，
 *   颗与颗的距离量子弹实例的 centerPoint3DX/Y（动画本地坐标系，不含容器缩放）。
 *   两种取法都写进招式的 melee 复核块，取哪一种由配置 mode 定；这一层只改段数，不动子弹跨度与前摇/后摇。
 * - 攻速只看前摇：动画开始帧到第一个子弹实例的帧数，多招取平均。
 *   分档按制作组口径：小于 9 帧极快、9~16 快、16~26 中等、26~41 慢、41 帧以上极慢（门槛写在配置里，上界不含）。
 * - 有效招式 = 真正会打到的标签；被按名调度的文件里没人 goto 的标签算废弃动画。
 *   跳转常用变量拼状态名（`状态改变("a"+随机数)`、`_parent.近战招式 = "a2"`），所以同文件同前缀族的标签一起放行。
 *   攻击样状态段里的动画若没人按名挑它的招式，就是播放头顺播到底 —— 每一段都会打出来，全部放行
 *   （招式合集把 a0/a1/a2、1连招/2连招 写成变量拼名，静态搜不到字面量，顺播同样成立）。
 *   宿主只 goto 到 受创/站立 一类状态标签不算"按名挑招式"；往摆放链里层捞候选时不放顺播这条。
 * - 空手攻击状态本身也是一招，近战状态里可能有多招。
 * - 三个系数都取有效招式的平均值。
 * - 倍率以物理伤害为准，法伤×2、真伤×3 折算；固定值伤害按面板均值折算并标注待复核。
 *   威力写成静态读不出的变量（`子弹威力 = 基础伤害` 一类）时这一招不记倍率，只在表达式里标注，
 *   宁可留空交人工复核，也不拿缺省值填空。
 *   整条式子全是乘除时按乘积解析系数（`4 * _parent.空手攻击力`、`0.5 * 性能倍率 * _parent.空手攻击力`），
 *   闸门这类同文件数值声明先折成数字；带加减项的（`空手攻击力 * 2 + 150`）仍按老写法只取后置数字。
 * - 函数式发弹也计入段数与倍率（制作组 2026-10-06 口径）：不少怪把发弹代码写成帧脚本里的函数
 *   （`function 射击() { ...子弹属性.霰弹值...; _root.子弹区域shoot传递(子弹属性); }`），时间轴上只打一句调用。
 *   函数体给出这一颗子弹的 霰弹值、子弹威力 与 子弹种类，调用点给出有效帧内真实触发了几次：
 *   `onClipEvent (enterFrame)` 每帧一次（在台几帧就调几次），帧脚本与其它处理器只在进入关键帧时一次；
 *   `if((射击计数++ % 性能倍率) != 0) return;` 是节流闸门，每 N 次调用才发一颗，N 读不到数值时按 1 并在疑点里说明。
 *   调用点已经把自己当子弹摆出去（实例内联或子弹元件带 子弹威力）的，不再按函数重复计一次。
 *
 * 三条硬规则来自实跑翻车：
 * - 一次命中 = 时间轴上摆出去的子弹元件实例（脚本内联在实例上，或写在子弹元件里）。
 *   按"帧里出现过 子弹威力 文本"计数会把帧级脚本和特效元件也算成命中。
 * - 归属硬门：招式必须落在容器（敌人-xxx 导出元件）的摆放树里，最多吃到 4 层
 *   容器 → 动画 → 动画再摆的子元件。同一个库里住着好几只怪是常态，
 *   兄弟怪的动画、共享素材子树之外的元件都不许串进来；候选文件也按这棵树取，
 *   不再按"容器所在目录"划作用域（容器住在库根时，那一条会把 素材/ 子树整个丢掉）。
 * - 状态硬门：容器时间轴上的状态段决定"这段动画是干什么的"。只有挂在**攻击样状态**
 *   （近战、空手攻击、长枪攻击、出招、招式、技能…）上的元件才算招式来源；
 *   被击、击倒、倒地、被投、血腥死、消失、站立、行走 一类的状态段里就算摆了带参数的子弹也不算攻击
 *   （飞刀小子 的 兵器/手枪/双枪 是击倒姿势按兵器类型分档，独狼 的两条"招式"挂在血腥死上）。
 *   词表写在 data/monster-census.json 的 attackStateWords / nonAttackStateWords，人工可改口径不改代码。
 * 取源只认注册表的 `<asset>` 行；被记进 `<conflict>`/`<duplicate>` 的模板是扫描器留给人工定源的，
 *   要量就在 data/monster-census.json 的 attackSourceOverrides 里指定 swf/symbolName。
 *   不手改 data/items/asset_source_map.xml：它是 scan_linkage.py 的 DO-NOT-EDIT 生成物，图标/换装烘焙管线也读它。
 */
import fs from "node:fs";
import path from "node:path";
import { inflateRawSync } from "node:zlib";

import { snapMonsterCoefficient, superArmorDecimalFromTenacity } from "@cf7-balance-tool/core";

/**
 * 一次攻击的帧数换算窗口（30fps 下的帧口径，制作组现定 15 帧），由 data/monster-census.json 给出，代码不写死。
 * 量的是子弹跨度（第一个子弹实例帧到最后一个子弹实例帧），不是整段动画长度。
 */
export function attackCountOf(bulletSpanFrames: number, windowFrames: number): number {
  if (windowFrames <= 0) return 1;
  return bulletSpanFrames < windowFrames ? 1 : bulletSpanFrames / windowFrames;
}

/** 招式结束标志：出手动画打完了就通知容器切状态，正常写法是 `_parent.动画完毕();`。 */
const ATTACK_OVER = /动画完毕/;

/** 一个招式的量测结果。 */
export interface AttackSkillMeasure {
  /** 招式所在文件（相对 LIBRARY）。 */
  file: string;
  /** 招式标签；整段动画没有标签时用「元件名（整段）」。 */
  label: string;
  /** 招式在时间轴上占的帧数。 */
  frames: number;
  /** 按子弹跨度折出的攻击次数（允许小数）。 */
  attacks: number;
  /** 折算成一次攻击后的段数（霰弹值加总 / attacks）。 */
  segments: number;
  /** 单次攻击折算时长 = frames / attacks；只供人工复核长招式，攻速取档不吃这个值。 */
  tempoFrames: number;
  /** 前摇：招式起点到第一个子弹实例的帧数。 */
  windupFrames: number;
  /** 第一个子弹实例帧离招式起点的偏移（等于 windupFrames，列出来是为了让跨度可核对）。 */
  firstBulletOffset: number;
  /** 最后一个子弹实例帧离招式起点的偏移。 */
  lastBulletOffset: number;
  /** 子弹跨度 = 末子弹帧 − 首子弹帧。 */
  bulletSpanFrames: number;
  /** 后摇：末子弹帧到招式结束帧的帧数。 */
  tailFrames: number;
  /** 招式结束帧怎么认的：找到 动画完毕 调用，还是退回这一段动画的段尾。 */
  tailBasis: "动画完毕" | "段尾";
  /** 窗口内的子弹颗数（摆出去的实例＋函数式发弹折出的调用），用来核对段数是不是被霰弹值撑起来的。 */
  hits: number;
  /** 近战子弹有效颗数的复核块：三种取法并排列着；这一招没有近战类子弹时不出现。 */
  melee?: MeleeSegmentAudit;
  /** 穿刺口径的复核块：这一招里被认成穿刺/次级穿刺的子弹；一颗都没有时不出现。 */
  pierce?: PierceSegmentAudit;
  /** 函数式发弹的复核块：这一招里没有函数发弹时不出现。 */
  functionShots?: FunctionShotAudit[];
  /** 每次命中的倍率均值（法伤×2、真伤×3 折算后）。 */
  multiplier?: number;
  /** 招式里出现的原始倍率表达式，供人工复核拆法是否合理。 */
  expressions: string[];
  /** 这个招式所在的动画被容器摆在哪个状态段上（近战、空手攻击、被击、血腥死…）；摆不出状态名时为空。 */
  state?: string;
  /** 元件离容器的摆放层数：容器直接摆是 1 层。 */
  depth: number;
  /** 可以进平均值：元件挂在攻击样状态段上、在容器的摆放树里，且被跳转（含 状态改变("a"+随机数) 的同族拼名）引用或靠顺播打出，又不像移动/死亡一类的非攻击状态。 */
  usable: boolean;
  /** 观测疑点，人工复核看这一列就够。 */
  concerns: string[];
}

export interface MonsterAttackMeasure {
  spritename: string;
  /** 命中的动画包（swf 口径路径）。 */
  source?: string;
  kind?: "xfl" | "fla";
  /** 招式来源：容器直接摆在攻击样状态上的动画，还是沿摆放链往里找一层。 */
  scope?: "placed" | "widened";
  /** 容器元件里读到的 攻击欲望（逐帧掷骰分母）与闸门倍数。 */
  attackDesire?: number[];
  gates?: string[];
  skills: AttackSkillMeasure[];
  /** 霸体系数 的元件观测（击倒/倒地 的击飞逻辑 + 被击 的击退时长）；量到容器就有这一项。 */
  armor?: MonsterArmorMeasure;
  /** 未定位到容器或没有有效招式时的说明。 */
  note?: string;
}

interface SymbolFile {
  relPath: string;
  xml: string;
}

interface AnimationPackage {
  files: SymbolFile[];
  kind: "xfl" | "fla";
}

const FRAME = /<DOMFrame\s+([^>]*)>([\s\S]*?)(?=<DOMFrame\s|<\/frames>)/g;
const FRAME_INDEX = /index="(\d+)"/;
const FRAME_DURATION = /duration="(\d+)"/;
const FRAME_NAME = /name="([^"]+)"/;
const SCRIPT = /<script>\s*<!\[CDATA\[([\s\S]*?)\]\]>\s*<\/script>/g;
const INSTANCE_SPLIT = /(?=<DOMSymbolInstance\b)/;
const INSTANCE_HEAD = /^<DOMSymbolInstance\b([^>]*)>/;
const ITEM_NAME = /libraryItemName="([^"]+)"/;
const COORD_X = /centerPoint3DX="(-?[\d.]+)"/;
const COORD_Y = /centerPoint3DY="(-?[\d.]+)"/;
const POWER = /子弹威力\s*=\s*([^\r\n;]+)/g;
/** 段数只认 霰弹值 本身；`最小霰弹值`/`最大霰弹值` 是随机区间的另一端，不能算成一次射击的段数。 */
const PELLET = /(?<![\p{L}\p{N}_])霰弹值\s*=\s*([\d.]+)/gu;
/** `霰弹值 += n` 是在基础值上追加弹数（按波次/距离加弹），与 `=` 的分支写法不同。 */
const PELLET_ADD = /(?<![\p{L}\p{N}_])霰弹值\s*\+=\s*([\d.]+)/gu;
const DAMAGE_TYPE = /伤害类型\s*=\s*["']([^"']+)["']/g;
/** 子弹种类 的两种写法：旧式实例上裸写 `子弹种类 = "近战子弹"`，新式 `子弹属性.子弹种类 = "近战联弹"`。 */
const KIND = /(?<![\p{L}\p{N}_])子弹种类\s*=\s*["']([^"']+)["']/gu;
/**
 * 区域定位area 是被赋一个命中区域元件的引用：赋了就是区域判定（一屏子弹大多中得上），
 * 没赋就是点状判定 —— 旧式 `_root.子弹区域shoot(...)` 只传 16 个位置参数，area 那一位空着，
 * 新式 `子弹区域shoot传递(子弹属性)` 才把它写全。点状判定的子弹摆得散，就只有少数打得中人。
 */
const AREA = /(?<![\p{L}\p{N}_])区域定位area\s*=/u;
const JUMP = /(?:状态改变|gotoAndPlay|gotoAndStop|nextFrame)\s*\(\s*["']([^"']+)["']/g;
/** 函数声明头：`function 射击()` —— 函数式发弹的入口，声明通常打在容器的帧脚本上。 */
const FUNCTION_DECL = /function\s+([^\s(]+)\s*\(([^)]*)\)\s*\{/g;
/** onClipEvent 处理器名：只有 enterFrame 是"每帧跑一次"，load 一类跟着关键帧进入只跑一次。 */
const HANDLER = /onClipEvent\s*\(\s*(\w+)\s*\)\s*\{/g;
/**
 * 节流闸门：`if((射击计数++ % 性能倍率) != 0) { return; }` —— 每 N 次调用才真发一颗子弹。
 * 允许闸门变量是字面数字或同文件的数值声明。
 */
const THROTTLE = /if\s*\([^{}]*?%\s*([\p{L}\p{N}_]+)\s*\)[^{}]{0,24}\{[^{}]{0,24}return/su;
/** 同文件里的数值声明（`性能倍率 = 2;`）：把闸门与前置系数里的变量名折成数字。 */
const NUMBER_ASSIGN = /(?<![\w.$)=])([\p{L}\p{N}_]+)\s*=\s*(\d+(?:\.\d+)?)(?![\d.])/gu;

const SKILL_PUSH = /([^\s(；;]*技能库)\.push\(\s*["']([^"']+)["']/g;
const DESIRE = /攻击欲望\s*=\s*([\d.]+)/g;
const GATE = /random\(\s*_parent\.攻击欲望\s*(\*\s*[\d.]+)?\s*\)/g;
const FACTOR = /空手攻击力\s*(?:\*\s*([\d.]+))?/;
const CONSTANT = /\+\s*([\d.]+)/g;
const ASSET = /<asset\s+([^>]*?)\/>/g;
const ASSET_ID = /id="([^"]+)"/;
const ASSET_SWF = /swf="([^"]+)"/;
const ASSET_SYMBOL = /symbolName="([^"]+)"/;
/** 扫描器把"有副本但不替人选源"的记录写成这两个块，块里没有 <asset>，实测器按 <asset> 取源就一条都拿不到。 */
const UNRESOLVED_BLOCK = /<(conflict|duplicate)\s+id="([^"]+)">([\s\S]*?)<\/\1>/g;
const SOURCE_TAG = /<source\s+([^>]*?)\/>/g;

/** 明显不是攻击的招式标签名（跑步、死亡一类）；命中时该招式不进平均值。 */
const NON_ATTACK_LABEL = /跑步|走路|行走|站立|待机|死亡|受创|受伤|击倒|被击|出生|出现|消失|复活|变身|巡逻|后退|抓取|拖拽|框架/;

/**
 * 容器状态段的词表：只有攻击样状态段摆出来的动画才算招式来源。
 * 现网状态机层是固定的一套名字（空手站立/空手行走/空手跑/空手跳/近战/空手攻击/拾取/躲闪/被击/击倒/倒地/被投/血腥死/消失），
 * 持械怪会多出一档 长枪攻击 之类；词表写在配置里，人工加一档新攻击状态不用改代码。
 */
export interface AttackStateRules {
  /** 状态名含这些词才算出手动作。 */
  attack: string[];
  /** 状态名含这些词一律不算，即使同时也命中 attack。 */
  nonAttack: string[];
}

export const DEFAULT_ATTACK_STATE_RULES: AttackStateRules = {
  attack: ["攻击", "近战", "出招", "招式", "技能", "施法", "连招", "扑击", "喷吐", "吐舌"],
  nonAttack: [
    "站立", "行走", "跑", "跳", "待机", "死亡", "死", "受创", "被击", "击倒", "倒地", "被投",
    "拾取", "躲闪", "出生", "出现", "消失", "登场", "复活", "变身", "巡逻", "后退", "抓取", "拖拽",
    "逃跑", "无效", "结束", "-无",
  ],
};

/** 状态段是不是"出手动作"：先否掉移动/受创/死亡一类，再看是否命中攻击词表。 */
function isAttackState(label: string | undefined, rules: AttackStateRules): boolean {
  if (label === undefined) return false;
  if (rules.nonAttack.some((word) => label.includes(word))) return false;
  return rules.attack.some((word) => label.includes(word));
}

/**
 * 近战子弹的有效颗数口径：段数量的是打得中玩家的那部分子弹，不是同屏摆了颗数。
 * 词表与尺寸都写在 data/monster-census.json 的 meleeSegmentRules 里，人工改口径不改代码。
 */
export interface MeleeBulletRules {
  /**
   * 近战类词：子弹种类（没声明时看子弹元件名）含任一才进这条口径。
   * 只有近战类才做颗数判定（80×170 命中框），联弹本身不算近战类 —— 非近战子弹射出多少就算多少。
   * 联弹打折 霰弹值 是另一条口径，认 linkageWords，不看这里（制作组 2026-10-06 定）。
   */
  kindWords: string[];
  /** 联弹词：子弹种类含任一算联弹（近战联弹、横向联弹、纵向联弹、穿刺联弹都算）。 */
  linkageWords: string[];
  /** 横向联弹词：联弹里含任一（`横向机枪联弹` 也算横向）无条件折分量，不看有没有传 区域定位area。 */
  linkageHorizontalWords: string[];
  /** 纵向联弹词：联弹里含任一（`纵向机枪联弹` 也算纵向）一律不折分量。 */
  linkageVerticalWords: string[];
  /** 联弹给 霰弹值 折的分量：单元体铺开、打不满。 */
  linkageFactor: number;
  /** 一拨的帧窗口：与拨内首颗相距小于该帧数的算同一拨（2 就是"同一帧或相邻帧"）。 */
  clusterFrames: number;
  /** 简单法：一拨最多算几颗。 */
  clusterCap: number;
  /** 几何法：玩家命中框的宽与高（像素）。 */
  hitboxWidth: number;
  hitboxHeight: number;
  /** 段数取哪种有效颗数算法；off 就是回到"摆了就算"的旧口径。 */
  mode: "off" | "cap" | "hitbox";
}

export const DEFAULT_MELEE_BULLET_RULES: MeleeBulletRules = {
  kindWords: ["近战"],
  linkageWords: ["联弹"],
  linkageHorizontalWords: ["横向"],
  linkageVerticalWords: ["纵向"],
  linkageFactor: 0.6,
  clusterFrames: 2,
  clusterCap: 3,
  hitboxWidth: 80,
  hitboxHeight: 170,
  mode: "hitbox",
};

/**
 * 穿刺类子弹的段数放大（制作组 2026-10-06 口径）：穿刺子弹命中后不消失、能连着打到人，
 * 所以这种子弹自己的段数按 2 倍计；次级穿刺按 1.5 倍。词表与倍数写在 data/monster-census.json 的 pierceSegmentRules 里。
 */
export interface PierceSegmentRules {
  /** 穿刺词：子弹种类（没声明时看子弹元件名）含任一按 pierceFactor 放大这一颗的段数。 */
  pierceWords: string[];
  /** 次级穿刺词：**先认这一层**再认 pierceWords —— 「次级穿刺子弹」本身含「穿刺」，顺序反了会被误判成 2 倍。 */
  secondaryPierceWords: string[];
  pierceFactor: number;
  secondaryPierceFactor: number;
}

export const DEFAULT_PIERCE_SEGMENT_RULES: PierceSegmentRules = {
  pierceWords: ["穿刺"],
  secondaryPierceWords: ["次级穿刺"],
  pierceFactor: 2,
  secondaryPierceFactor: 1.5,
};

function readXml(file: string): string {
  return fs.readFileSync(file, "utf8").replace(/^/, "");
}

/** noUncheckedIndexedAccess 下正则捕获组是 string|undefined，取值统一走这里。 */
function cap(match: RegExpMatchArray | RegExpExecArray | null | undefined, index: number): string | undefined {
  return match?.[index];
}

/** 实例头里的坐标属性：没写或写成非数都算读不到。 */
function coordOf(head: string | undefined, pattern: RegExp): number | undefined {
  const value = head === undefined ? Number.NaN : Number(cap(pattern.exec(head), 1));
  return Number.isFinite(value) ? value : undefined;
}

function groups(text: string, pattern: RegExp, index = 1): string[] {
  return [...text.matchAll(pattern)].map((match) => cap(match, index) ?? "").filter(Boolean);
}

function walkLibrary(dir: string, base = ""): SymbolFile[] {
  const out: SymbolFile[] = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const rel = base === "" ? entry.name : `${base}/${entry.name}`;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) out.push(...walkLibrary(full, rel));
    else if (entry.name.endsWith(".xml")) out.push({ relPath: rel, xml: readXml(full) });
  }
  return out;
}

/**
 * CS6 的 .fla 是 zip，但中央目录记录的长度与实际不符，标准库会直接报错。
 * 这里按本地文件头顺序扫，流式写入的条目靠下一个头反推大小 —— 与 tools/linkage_scanner/scan_linkage.py 同一读法。
 */
function readFlaLibrary(file: string): SymbolFile[] {
  const data = fs.readFileSync(file);
  const out: SymbolFile[] = [];
  let offset = 0;
  while (offset < data.length - 4) {
    if (data.readUInt32LE(offset) !== 0x04034b50) {
      const next = data.indexOf("PK\x03\x04", offset + 1);
      if (next < 0) break;
      offset = next;
      continue;
    }
    const flags = data.readUInt16LE(offset + 6);
    const method = data.readUInt16LE(offset + 8);
    let compressedSize = data.readUInt32LE(offset + 18);
    const nameLength = data.readUInt16LE(offset + 26);
    const extraLength = data.readUInt16LE(offset + 28);
    const name = data.subarray(offset + 30, offset + 30 + nameLength).toString("utf8");
    const start = offset + 30 + nameLength + extraLength;
    if ((flags & 0x08) !== 0 || compressedSize === 0) {
      let next = data.indexOf("PK\x03\x04", start);
      const central = data.indexOf("PK\x01\x02", start);
      if (central >= 0 && (next < 0 || central < next)) next = central;
      if (next < 0) break;
      const descriptor = data.indexOf("PK\x07\x08", start);
      const bounded = descriptor >= 0 && descriptor < next;
      compressedSize = bounded ? descriptor - start : next - start;
      offset = bounded ? descriptor + 16 : next;
    } else {
      offset = start + compressedSize;
    }
    if (!name.startsWith("LIBRARY/") || !name.endsWith(".xml")) continue;
    const raw = data.subarray(start, start + compressedSize);
    try {
      const xml = (method === 8 ? inflateRawSync(raw) : Buffer.from(raw)).toString("utf8");
      out.push({ relPath: name.slice("LIBRARY/".length), xml });
    } catch {
      // 目录项或坏块：跳过，不让整只怪失败
    }
  }
  return out;
}

const packageCache = new Map<string, AnimationPackage | null>();

/** 按 swf 口径路径找动画包（XFL 目录优先，其次解 .fla）。 */
function packageFor(swfPath: string, repoRoot: string): AnimationPackage | null {
  // 键必须是解析到绝对路径的包目录：只按相对 swf 路径缓存会让两个仓库里的同名包互相顶掉
  const base = path.resolve(repoRoot, swfPath.replace(/\.swf$/, ""));
  const cached = packageCache.get(base);
  if (cached !== undefined) return cached;
  let found: AnimationPackage | null = null;
  if (fs.existsSync(path.join(base, "DOMDocument.xml"))) {
    const library = path.join(base, "LIBRARY");
    found = { kind: "xfl", files: fs.existsSync(library) ? walkLibrary(library) : [] };
  } else if (fs.existsSync(`${base}.fla`)) {
    found = { kind: "fla", files: readFlaLibrary(`${base}.fla`) };
  }
  packageCache.set(base, found);
  return found;
}

interface PlacedInstance {
  /** 实例引用的库元件名。 */
  item?: string;
  /** 挂在实例上的脚本（子弹属性一般写在这里）。 */
  scripts: string[];
  /** 实例在所在时间轴上的位置：几何法量子弹摆得多开用它，帧级脚本命中的没有。 */
  x?: number;
  y?: number;
}

interface ParsedFrame {
  index: number;
  /** duration 属性值：XFL 里招式标签自带段宽，.fla 里常缺席。 */
  duration: number;
  /** 图层分组，用于按"下一个标签"推算 .fla 的段宽。 */
  lane: number;
  label?: string;
  /** 这一帧摆出去的元件实例。 */
  placed: PlacedInstance[];
  /** 没挂在实例上的帧级脚本。 */
  frameScripts: string[];
}

function framesOf(xml: string): ParsedFrame[] {
  const out: ParsedFrame[] = [];
  let lane = 0;
  for (const match of xml.matchAll(FRAME)) {
    const attrs = cap(match, 1) ?? "";
    const index = Number(cap(FRAME_INDEX.exec(attrs), 1));
    if (!Number.isFinite(index)) continue;
    // 每个 <frames> 块是一层；块尾或 index 回绕都说明换层了
    if (match[0].includes("</frames>") || (out.at(-1)?.index ?? -1) >= index) lane += 1;
    const duration = Number(cap(FRAME_DURATION.exec(attrs), 1) ?? 1);
    const label = /labelType="name"/.test(attrs) ? cap(FRAME_NAME.exec(attrs), 1) : undefined;
    const body = cap(match, 2) ?? "";
    // 前瞻切分：每个实例自成一段，父实例的 own 文本自然停在子实例之前
    const chunks = body.split(INSTANCE_SPLIT);
    const placed: PlacedInstance[] = chunks.slice(1).map((chunk) => {
      const head = cap(INSTANCE_HEAD.exec(chunk), 1);
      const item = head === undefined ? undefined : cap(ITEM_NAME.exec(head), 1);
      const x = coordOf(head, COORD_X);
      const y = coordOf(head, COORD_Y);
      return {
        ...(item === undefined ? {} : { item }),
        ...(x === undefined ? {} : { x }),
        ...(y === undefined ? {} : { y }),
        scripts: groups(chunk, SCRIPT),
      };
    });
    out.push({
      index,
      duration: Number.isFinite(duration) ? duration : 1,
      lane,
      ...(label === undefined ? {} : { label }),
      placed,
      frameScripts: chunks.length > 1 ? groups(chunks[0]!, SCRIPT) : groups(body, SCRIPT),
    });
  }
  return out;
}

/**
 * 招式段宽：XFL 的标签帧自带 duration；.fla 的标签帧没有，就取到同层下一个标签（或时间轴末尾）。
 * 不按同层下一个关键帧收口，因为子弹实例通常摆在别的图层。
 */
function spanOf(frame: ParsedFrame, sameLane: ParsedFrame[], end: number): number {
  if (frame.duration > 1) return frame.duration;
  const next = sameLane
    .filter((other) => other.index > frame.index && other.label !== undefined)
    .reduce((min, other) => Math.min(min, other.index), Number.POSITIVE_INFINITY);
  return Math.max(1, (Number.isFinite(next) ? next : end) - frame.index);
}

function hasPower(scripts: string[]): boolean {
  return scripts.some((script) => script.includes("子弹威力"));
}

/** 这一帧有没有打 动画完毕（帧级脚本或挂在实例上的脚本都算）：招式结束帧就按它认。 */
function frameOverCall(frame: ParsedFrame): boolean {
  if (frame.frameScripts.some((script) => ATTACK_OVER.test(script))) return true;
  return frame.placed.some((instance) => instance.scripts.some((script) => ATTACK_OVER.test(script)));
}

/** 一次命中 = 一个子弹实例：内联脚本优先，否则取子弹元件自己的脚本。 */
interface PlacedHit {
  scripts: string[];
  /** 摆出这颗子弹的实例；只有帧级脚本时没有实例，元件名与坐标都读不到。 */
  instance?: PlacedInstance;
  /**
   * 函数式发弹挂在发射点实例上：那个实例只是开枪位置（常常是全隐形的锚点），
   * 真发出去的是函数体 子弹种类 点名的子弹，所以不许再拿锚点的元件名认近战/穿刺。
   */
  anchorNamed?: boolean;
}

function bulletMarks(frame: ParsedFrame, carrierOf: (item: string) => string[] | undefined): PlacedHit[] {
  const hits: PlacedHit[] = [];
  for (const instance of frame.placed) {
    if (hasPower(instance.scripts)) {
      hits.push({ scripts: instance.scripts, instance });
      continue;
    }
    const carrier = instance.item === undefined ? undefined : carrierOf(instance.item);
    if (carrier !== undefined) hits.push({ scripts: carrier, instance });
  }
  // 帧级脚本兜底：只看函数体外的那部分文本。整段都在声明发弹函数（`function 射击() {...子弹威力...}`）的
  // 代码帧不发弹，那颗子弹由函数式发弹通道按真实调用次数计。
  if (hits.length === 0) {
    const outside = frame.frameScripts.map((script) => functionDeclsOf(script).outside).join("\n");
    if (hasPower([outside])) hits.push({ scripts: [outside] });
  }
  return hits;
}

/** 节流闸门的数值是从哪来的：没闸门、字面数字、同文件数值声明、变量读不出数值。 */
export type ThrottleBasis = "无" | "字面" | "数值声明" | "读不出";

/** 声明在帧脚本函数里的发弹代码：函数体给这一颗子弹的段数与倍率，调用点给真实触发次数。 */
interface ShootingFunction {
  name: string;
  body: string;
  values: InstanceValues;
  throttle: number;
  throttleBasis: ThrottleBasis;
  /** 函数体声明在哪份文件（相对 LIBRARY）；子动画靠容器的函数发弹时要在疑点里标出来。 */
  declaredIn: string;
}

/** 一个调用点在这一帧折出来的发弹帧。 */
interface ShotSite {
  fn: ShootingFunction;
  /** 发弹所在的绝对帧。 */
  offsets: number[];
  /** 真实触发次数：enterFrame 按在台帧数累计，帧脚本按关键帧进入算一次。 */
  calls: number;
  /** 挂在哪个发射点实例上（读得到坐标就给几何法用）。 */
  anchor?: PlacedInstance;
}

/** 花括号配平：从声明头的 { 找到函数体收尾的 }，配不平就吃到文本末尾。 */
function bodyEndOf(text: string, openAt: number): number {
  let depth = 0;
  for (let index = openAt; index < text.length; index += 1) {
    const char = text[index];
    if (char === "{") depth += 1;
    else if (char === "}") {
      depth -= 1;
      if (depth === 0) return index;
    }
  }
  return text.length - 1;
}

/** 拆出函数声明体与体外文本：调用点只认体外的，免得把声明自身或递归当成一次发弹。 */
function functionDeclsOf(script: string): { decls: { name: string; body: string }[]; outside: string } {
  const decls: { name: string; body: string }[] = [];
  const outside: string[] = [];
  let cursor = 0;
  for (const match of script.matchAll(FUNCTION_DECL)) {
    const start = match.index ?? 0;
    const openAt = start + match[0].length - 1;
    const end = bodyEndOf(script, openAt);
    const name = match[1];
    if (name === undefined) continue;
    decls.push({ name, body: script.slice(openAt + 1, end) });
    outside.push(script.slice(cursor, start));
    cursor = end + 1;
  }
  outside.push(script.slice(cursor));
  return { decls, outside: outside.join("\n") };
}

/** 把脚本切成 enterFrame 处理器体与「只跑一次」的文本：帧脚本与 load 一类处理器都只在进入关键帧时跑一次。 */
function handlerSplit(script: string): { perFrame: string[]; once: string } {
  const perFrame: string[] = [];
  const once: string[] = [];
  let cursor = 0;
  for (const match of script.matchAll(HANDLER)) {
    const start = match.index ?? 0;
    const openAt = start + match[0].length - 1;
    const end = bodyEndOf(script, openAt);
    once.push(script.slice(cursor, start));
    if ((match[1] ?? "") === "enterFrame") perFrame.push(script.slice(openAt + 1, end));
    else once.push(script.slice(openAt + 1, end));
    cursor = end + 1;
  }
  once.push(script.slice(cursor));
  return { perFrame, once: once.join("\n") };
}

/** 一个函数在这段文本里被打了几次调用：允许带参数与 this./_parent. 前缀，但不把声明自身算进去。 */
function callCountOf(text: string, name: string): number {
  const identifier = name.replace(/[^\p{L}\p{N}_]/gu, "");
  if (identifier === "") return 0;
  const pattern = new RegExp(`(?<![\\p{L}\\p{N}_])(?:[\\w.$]+\\.)?${identifier}\\s*\\(`, "gu");
  return [...text.matchAll(pattern)].length;
}

/**
 * 调用点折成发弹帧：每 闸门 次调用发一颗。射击计数 从几起头静态读不出来，
 * 就按「从头数起、每 N 次一发」取，宁多算一帧也不猜奇偶。
 */
function emissionsOf(callsPerFrame: number, frames: number, throttle: number): number[] {
  if (callsPerFrame <= 0 || frames <= 0) return [];
  const step = Math.max(1, Math.round(throttle));
  const total = callsPerFrame * frames;
  const out: number[] = [];
  for (let index = 0; index < total; index += step) out.push(Math.floor(index / callsPerFrame));
  return out;
}

/** 同文件的数值声明（`性能倍率 = 2;` 一类）：把闸门与前置系数里的变量名折成数字。 */
function numericScalarsOf(text: string): Map<string, number> {
  const out = new Map<string, number>();
  for (const match of text.matchAll(NUMBER_ASSIGN)) {
    const name = match[1];
    const value = Number(match[2]);
    if (name === undefined || !Number.isFinite(value) || out.has(name)) continue;
    out.set(name, value);
  }
  return out;
}

/** 节流闸门：读得到数值就每 N 次调用发一颗，读不出数值时按 1 并在疑点里交代。 */
function throttleOf(body: string, scalars: Map<string, number>): { throttle: number; throttleBasis: ThrottleBasis } {
  const raw = cap(THROTTLE.exec(body), 1);
  if (raw === undefined) return { throttle: 1, throttleBasis: "无" };
  if (/^\d+(?:\.\d+)?$/.test(raw)) return { throttle: Math.max(1, Number(raw)), throttleBasis: "字面" };
  const value = scalars.get(raw);
  if (value === undefined || !(value >= 1)) return { throttle: 1, throttleBasis: "读不出" };
  return { throttle: Math.max(1, Math.round(value)), throttleBasis: "数值声明" };
}

/**
 * 读出一份文件里「函数体在发弹」的声明。同名以本文件为准；
 * 把容器一起传进来时，容器那份只在子动画写 `_parent.射击()` 这类调用时兜底。
 */
function shootingFunctionsOf(files: SymbolFile[], panelAtkMid: number): ShootingFunction[] {
  const out: ShootingFunction[] = [];
  const seen = new Set<string>();
  for (const file of files) {
    const scripts = groups(file.xml, SCRIPT);
    const scalars = numericScalarsOf(scripts.join("\n"));
    for (const script of scripts) {
      for (const decl of functionDeclsOf(script).decls) {
        if (seen.has(decl.name) || !decl.body.includes("子弹威力")) continue;
        const values = instanceValues([decl.body], panelAtkMid, scalars);
        if (values.segments === 0) continue;
        seen.add(decl.name);
        out.push({ name: decl.name, body: decl.body, values, declaredIn: file.relPath, ...throttleOf(decl.body, scalars) });
      }
    }
  }
  return out;
}

/** 这一帧里的函数式发弹调用点：enterFrame 锚点在台的每一帧都调，帧脚本只在这一个关键帧进入时调。 */
function shotSitesInFrame(
  frame: ParsedFrame,
  funcs: ShootingFunction[],
  windowEnd: number,
  consumed: Set<PlacedInstance>,
): ShotSite[] {
  if (funcs.length === 0) return [];
  const onStage = Math.max(1, Math.min(frame.index + frame.duration, windowEnd) - frame.index);
  const sites: ShotSite[] = [];
  const push = (fn: ShootingFunction, perFrame: number, once: number, anchor?: PlacedInstance): void => {
    const offsets: number[] = [];
    if (perFrame > 0) for (const step of emissionsOf(perFrame, onStage, fn.throttle)) offsets.push(frame.index + step);
    if (once > 0) for (const step of emissionsOf(once, 1, fn.throttle)) offsets.push(frame.index + step);
    if (offsets.length === 0) return;
    sites.push({
      fn,
      offsets,
      calls: perFrame * (perFrame > 0 ? onStage : 0) + once,
      ...(anchor === undefined ? {} : { anchor }),
    });
  };
  const frameText = frame.frameScripts.map((script) => functionDeclsOf(script).outside).join("\n");
  for (const fn of funcs) push(fn, 0, callCountOf(frameText, fn.name));
  for (const instance of frame.placed) {
    if (consumed.has(instance)) continue;
    const parts = instance.scripts.map((script) => handlerSplit(functionDeclsOf(script).outside));
    const perFrameText = parts.flatMap((part) => part.perFrame).join("\n");
    const onceText = parts.map((part) => part.once).join("\n");
    for (const fn of funcs) {
      push(fn, perFrameText === "" ? 0 : callCountOf(perFrameText, fn.name), callCountOf(onceText, fn.name), instance);
    }
  }
  return sites;
}

/** 元件路径分段：去掉 .xml 与 ../，按 / 拆开。 */
function segmentsOf(item: string): string[] {
  return item
    .replace(/\.xml$/, "")
    .split("/")
    .filter((segment) => segment !== "" && segment !== "..");
}

/**
 * 尾段匹配：两侧层级写全不全都认，但至少重合两级，
 * 避免 Symbol 1478 这种只有一级名字的元件互相误认。
 */
function tailMatches(item: string, relPath: string): boolean {
  const key = segmentsOf(relPath);
  const segments = segmentsOf(item);
  const depth = Math.min(key.length, segments.length);
  if (depth < 2) return key.length === segments.length && key[0] === segments[0];
  return segments.slice(-depth).every((segment, offset) => key.slice(-depth)[offset] === segment);
}

/** 库元件名 → 包内文件，结果按元件名缓存。 */
function itemResolver(files: SymbolFile[]): (item: string) => SymbolFile | undefined {
  const byPath = new Map<string, SymbolFile>();
  for (const file of files) byPath.set(segmentsOf(file.relPath).join("/"), file);
  const cache = new Map<string, SymbolFile | undefined>();
  return (item) => {
    if (cache.has(item)) return cache.get(item);
    let found = byPath.get(segmentsOf(item).join("/"));
    if (found === undefined) found = files.find((file) => tailMatches(item, file.relPath));
    cache.set(item, found);
    return found;
  };
}

/** 子弹元件自己的脚本：第一处带 子弹威力 的实例脚本，没有实例脚本时退到帧级脚本。 */
function carrierScripts(file: SymbolFile, cache: Map<string, string[] | null>): string[] | undefined {
  if (!file.xml.includes("子弹威力")) return undefined;
  const cached = cache.get(file.relPath);
  if (cached !== undefined) return cached ?? undefined;
  let picked: string[] | undefined;
  for (const frame of framesOf(file.xml)) {
    for (const instance of frame.placed) {
      if (hasPower(instance.scripts)) picked = instance.scripts;
    }
    if (picked === undefined) {
      // 只看函数体外的那部分：整段都在声明发弹函数的代码帧不代表「这颗子弹自带威力」，
      // 那种子弹由函数式发弹通道按真实调用次数计，摆出去一次就记一颗会凭空多算。
      const outside = frame.frameScripts.map((text) => functionDeclsOf(text).outside);
      if (hasPower(outside)) picked = outside;
    }
    if (picked !== undefined) break;
  }
  cache.set(file.relPath, picked ?? null);
  return picked;
}

interface InstanceValues {
  segments: number;
  multipliers: number[];
  relative: number;
  fixed: number;
  expressions: string[];
}

/** 一组子弹脚本 → 段数（霰弹值 均值 + `+=` 追加，缺省按 1 段）与倍率（物理 1、法伤×2、真伤×3）。 */
function instanceValues(scripts: string[], panelAtkMid: number, scalars?: Map<string, number>): InstanceValues {
  const text = scripts.join("\n");
  const powers = [...text.matchAll(POWER)];
  const multipliers: number[] = [];
  const expressions: string[] = [];
  if (powers.length === 0) return { segments: 0, multipliers, relative: 0, fixed: 0, expressions };
  const numbers = (matches: string[]) =>
    matches.map((value) => Number(value)).filter((value) => Number.isFinite(value) && value > 0);
  // 一颗子弹里多次 `霰弹值 = n` 是分支或跨帧的备选写法，取均值；`+=` 是累加，加在基础值上。
  // 运行时 霰弹值 默认 1（BulletAttributes 构造函数），所以只有 `+=` 时基础值按 1。
  const bases = numbers(groups(text, PELLET));
  const adds = numbers(groups(text, PELLET_ADD));
  const base = bases.length > 0 ? bases.reduce((sum, value) => sum + value, 0) / bases.length : 1;
  const segments = Math.max(1, base + adds.reduce((sum, value) => sum + value, 0));
  const types = groups(text, DAMAGE_TYPE);
  const typeScale = types.some((t) => t.includes("真")) ? 3 : types.some((t) => t.includes("魔") || t.includes("元素")) ? 2 : 1;
  let relative = 0;
  let fixed = 0;

  // 同一颗子弹里多次赋值通常是分支或按距离加伤，取均值代表"平均每次攻击倍率"
  const values: number[] = [];
  for (const power of powers) {
    const expr = (cap(power, 1) ?? "").trim().replace(/\s+/g, " ");
    let note = typeScale > 1 ? `（伤害类型折算×${typeScale}）` : "";
    let value: number | undefined;
    let isFixed = false;
    if (expr.includes("空手攻击力")) {
      const product = productCoefficient(expr, scalars);
      const factor = product?.coefficient ?? Number(cap(FACTOR.exec(expr), 1) ?? 1);
      // 附加固定值（空手攻击力 + 150）按面板均值折进倍率；技能等级项按 0 级忽略
      const constant = groups(expr, CONSTANT).reduce((sum, item) => sum + Number(item), 0);
      value = ((Number.isFinite(factor) ? factor : 1) + (panelAtkMid > 0 ? constant / panelAtkMid : 0)) * typeScale;
      if (product !== undefined && product.coefficient !== 1) note += `（乘积式系数 ×${round2(product.coefficient)}）`;
    } else if (/^[\d.]+$/.test(expr) && panelAtkMid > 0) {
      value = (Number(expr) / panelAtkMid) * typeScale;
      isFixed = true;
    } else {
      // 威力写在变量里（基础伤害一类），静态读不出倍数：这一招不记倍率，交人工复核而不是猜
      note += "（威力读不出，不进倍率均值）";
    }
    expressions.push(expr + note);
    if (value === undefined) continue;
    values.push(value);
    if (isFixed) fixed += 1;
    else relative += 1;
  }
  if (values.length > 0) multipliers.push(values.reduce((sum, value) => sum + value, 0) / values.length);
  return { segments, multipliers, relative, fixed, expressions };
}

/**
 * 纯乘除式里 空手攻击力 的系数：`4 * _parent.空手攻击力`、`0.5 * 性能倍率 * _parent.空手攻击力` 都读得出来。
 * 老写法只取 空手攻击力 右邻的数字（FACTOR），这类前置系数会被当成 ×1，
 * 火炮开火 的 20 倍、毒刺射击 的 4 倍就是这么丢的。
 * 只碰「整条式子全是乘法除法」的写法：带加减项或括号的（`空手攻击力 * 2 + 150`）照老通道走，
 * 变量名在同文件里折不出数值也退回老通道，不改已经对上的那批账。
 */
function productCoefficient(expr: string, scalars?: Map<string, number>): { coefficient: number } | undefined {
  if (cap(FACTOR.exec(expr), 1) !== undefined) return undefined;
  if (/[+\-()（）]/.test(expr)) return undefined;
  let value = 1;
  let divide = false;
  let sawAttack = false;
  for (const raw of expr.split(/\s*([*/])\s*/)) {
    const token = raw.trim();
    if (token === "" || token === "*") continue;
    if (token === "/") {
      divide = true;
      continue;
    }
    if (token.includes("空手攻击力")) {
      sawAttack = true;
      continue;
    }
    if (/^\d+(?:\.\d+)?$/.test(token)) {
      value = divide ? value / Number(token) : value * Number(token);
      continue;
    }
    const scalar = scalars?.get(token.replace(/^[\w.$]*\./, ""));
    if (scalar === undefined || !(scalar > 0)) return undefined;
    value = divide ? value / scalar : value * scalar;
  }
  if (!sawAttack || !Number.isFinite(value) || value <= 0) return undefined;
  return { coefficient: value };
}

/** 一颗子弹在口径里的身份：近战类才折有效颗数，联弹的方向族决定 霰弹值 打不打折，穿刺决定这一段数乘几。 */
interface BulletMark {
  values: InstanceValues;
  /** 离招式起点的帧偏移。 */
  offset: number;
  melee: boolean;
  linkage: boolean;
  /** 横向一类联弹（含 横向机枪联弹）：不传 区域定位area 也折分量。 */
  horizontalLinkage: boolean;
  /** 纵向一类联弹（含 纵向机枪联弹）：传不传 area 都不折分量。 */
  verticalLinkage: boolean;
  area: boolean;
  /** 靠子弹元件名（而不是 子弹种类 声明）认出近战类的：这条通道有多少量要人工复核看这一列。 */
  byName: boolean;
  /** 穿刺口径给这一颗的段数倍数：1 表示没命中穿刺词。 */
  pierceFactor: number;
  /** 命中的是穿刺还是次级穿刺；读的是种类声明还是元件名。 */
  pierce?: { tier: "pierce" | "次级穿刺"; text: string; byName: boolean };
  x: number | undefined;
  y: number | undefined;
}

/**
 * 穿刺判定：先认次级穿刺再认穿刺 —— 「次级穿刺子弹」里也含「穿刺」两字，顺序反了会全部按 2 倍算。
 * 与近战类同一套取法：有 子弹种类 声明就按声明认，没声明才退回子弹元件名。
 */
function pierceOf(
  kinds: string[],
  named: string,
  rules: PierceSegmentRules,
): { factor: number; tier: "pierce" | "次级穿刺"; text: string; byName: boolean } | undefined {
  const tiers = [
    { tier: "次级穿刺" as const, words: rules.secondaryPierceWords, factor: rules.secondaryPierceFactor },
    { tier: "pierce" as const, words: rules.pierceWords, factor: rules.pierceFactor },
  ];
  for (const text of kinds) {
    for (const level of tiers) if (level.words.some((word) => text.includes(word))) return { ...level, text, byName: false };
  }
  for (const level of tiers) if (level.words.some((word) => named.includes(word))) return { ...level, text: named, byName: true };
  return undefined;
}

function markOf(hit: PlacedHit, values: InstanceValues, offset: number, rules: MeleeBulletRules, pierce: PierceSegmentRules): BulletMark {
  const text = hit.scripts.join("\n");
  const kinds = groups(text, KIND);
  const area = AREA.test(text);
  // 函数式发弹挂的是发射点锚定实例，元件名（常见就叫 近战子弹）不代表真发出去的那颗子弹
  const named = hit.anchorNamed === true ? "" : hit.instance?.item ?? "";
  const byKind = kinds.some((kind) => rules.kindWords.some((word) => kind.includes(word)));
  const byName = !byKind && rules.kindWords.some((word) => named.includes(word));
  const matched = pierceOf(kinds, named, pierce);
  const linkage = kinds.some((kind) => rules.linkageWords.some((word) => kind.includes(word)));
  // 方向词只在认到 联弹 之后才看：横向/纵向 也出现在非联弹的种类名里，那条口径与打折无关
  const horizontalLinkage =
    linkage && kinds.some((kind) => rules.linkageHorizontalWords.some((word) => kind.includes(word)));
  const verticalLinkage = linkage && kinds.some((kind) => rules.linkageVerticalWords.some((word) => kind.includes(word)));
  return {
    values,
    offset,
    melee: byKind || byName,
    linkage,
    horizontalLinkage,
    verticalLinkage,
    area,
    byName,
    pierceFactor: matched?.factor ?? 1,
    ...(matched === undefined ? {} : { pierce: { tier: matched.tier, text: matched.text, byName: matched.byName } }),
    x: hit.instance?.x,
    y: hit.instance?.y,
  };
}

/**
 * 这颗的 霰弹值 打不打折：横向联弹无条件折，纵向联弹一律不折，
 * 近战联弹与其余联弹要传了 区域定位area 才折（制作组 2026-10-06 口径）。
 * 同名同时含 横向 与 纵向 时按纵向处理（宁可不折）。
 */
function linkageDiscounted(mark: BulletMark): boolean {
  if (!mark.linkage || mark.verticalLinkage) return false;
  return mark.horizontalLinkage || mark.area;
}

/** 联弹的三本账：横向无条件折／靠 area 折／纵向不折；既不沾折的条件、又不是纵向的记进 fullValue。 */
function linkageTally(marks: BulletMark[]): {
  discountedHorizontal: number;
  discountedByArea: number;
  vertical: number;
  fullValue: number;
} {
  const discounted = marks.filter((mark) => linkageDiscounted(mark));
  return {
    discountedHorizontal: discounted.filter((mark) => mark.horizontalLinkage).length,
    discountedByArea: discounted.filter((mark) => !mark.horizontalLinkage).length,
    vertical: marks.filter((mark) => mark.linkage && mark.verticalLinkage).length,
    fullValue: marks.filter((mark) => mark.linkage && !mark.verticalLinkage && !linkageDiscounted(mark)).length,
  };
}

/** 联弹给 霰弹值 折分量（横向必折、纵向不折、其余看 区域定位area），穿刺在这之上乘倍数。 */
function pelletsOf(mark: BulletMark, rules: MeleeBulletRules): number {
  const pellets = linkageDiscounted(mark) ? mark.values.segments * rules.linkageFactor : mark.values.segments;
  return pellets * mark.pierceFactor;
}


/** 一拨 = 与拨内首颗相距小于 clusterFrames 帧的一串子弹（2 即同一帧或相邻帧）。 */
function clustersOf(marks: BulletMark[], clusterFrames: number): BulletMark[][] {
  const sorted = [...marks].sort((a, b) => a.offset - b.offset);
  const out: BulletMark[][] = [];
  for (const mark of sorted) {
    const first = out.at(-1)?.[0];
    if (first !== undefined && mark.offset - first.offset < clusterFrames) out.at(-1)!.push(mark);
    else out.push([mark]);
  }
  return out;
}

type PositionedMark = BulletMark & { x: number; y: number };

/** 一拨里每颗都读得到坐标才能做几何法；有一颗读不到就整拨退回简单法，不猜位置。 */
function positioned(marks: BulletMark[]): PositionedMark[] | undefined {
  if (marks.length === 0) return [];
  const ready = marks.every((mark) => mark.x !== undefined && mark.y !== undefined);
  return ready ? (marks as PositionedMark[]) : undefined;
}

/** 固定尺寸的轴对齐框能框住的最多颗数：把框贴到某颗的左边与上边就够 —— 最优框总能这么滑到位。 */
function enclosureOf(marks: PositionedMark[], width: number, height: number): PositionedMark[] {
  let best: PositionedMark[] = [];
  let bestPellets = 0;
  for (const anchor of marks) {
    for (const row of marks) {
      const inside = marks.filter(
        (mark) =>
          mark.x >= anchor.x && mark.x <= anchor.x + width && mark.y >= row.y && mark.y <= row.y + height,
      );
      const pellets = inside.reduce((sum, mark) => sum + mark.values.segments, 0);
      if (inside.length > best.length || (inside.length === best.length && pellets > bestPellets)) {
        best = inside;
        bestPellets = pellets;
      }
    }
  }
  return best;
}

interface EffectiveBullets {
  /** 计入口径的子弹。 */
  kept: BulletMark[];
  /** 无区域近战子弹被分成的拨数。 */
  clusters: number;
  /** 几何法里退回简单法的拨数。 */
  unpositionedClusters: number;
}

/**
 * 有效子弹：非近战类与传了 area 的直接进；只有"近战类且没传 area"的那批按拨折颗数。
 * 联弹本身不算近战类 —— 非近战联弹射出多少颗就算多少颗（制作组 2026-10-06 定）。
 * mode 为 off 时不折，等于旧的"摆了颗数就算"。
 */
function effectiveMarks(marks: BulletMark[], rules: MeleeBulletRules, mode: MeleeBulletRules["mode"]): EffectiveBullets {
  const spread = mode === "off" ? [] : marks.filter((mark) => mark.melee && !mark.area);
  const kept = mode === "off" ? [...marks] : marks.filter((mark) => !(mark.melee && !mark.area));
  let clusters = 0;
  let unpositionedClusters = 0;
  for (const cluster of clustersOf(spread, rules.clusterFrames)) {
    clusters += 1;
    const ready = mode === "hitbox" ? positioned(cluster) : undefined;
    if (ready === undefined) {
      if (mode === "hitbox" && cluster.length > 0) unpositionedClusters += 1;
      kept.push(...cluster.slice(0, rules.clusterCap));
      continue;
    }
    kept.push(...enclosureOf(ready, rules.hitboxWidth, rules.hitboxHeight));
  }
  return { kept, clusters, unpositionedClusters };
}

function pelletSum(marks: BulletMark[], rules: MeleeBulletRules): number {
  return marks.reduce((sum, mark) => sum + pelletsOf(mark, rules), 0);
}

/** 近战子弹有效颗数的复核块：不过滤、简单法、几何法三种取法并排列着，人工据此定 mode。一颗近战类都没有、只有联弹打折时也出块（近战那几列为 0）。 */
export interface MeleeSegmentAudit {
  meleeHits: number;
  byNameHits: number;
  areaHits: number;
  linkageHorizontalHits: number;
  /** 靠传了 区域定位area 折分量的颗数（横向那类记在上一列，不重复计）。 */
  linkageAreaHits: number;
  /** 纵向一类联弹的颗数：传不传 area 都不折分量，按全值算。 */
  linkageVerticalHits: number;
  spreadHits: number;
  clusters: number;
  countedCap: number;
  countedHitbox: number;
  unpositionedClusters: number;
  segmentsUnfiltered: number;
  segmentsCap: number;
  segmentsHitbox: number;
  mode: MeleeBulletRules["mode"];
}

function meleeAudit(marks: BulletMark[], rules: MeleeBulletRules, attacks: number): MeleeSegmentAudit | undefined {
  const melee = marks.filter((mark) => mark.melee);
  const linkage = linkageTally(marks);
  // 非近战联弹不参与颗数折叠，但 霰弹值 照打折 —— 这一层的账也要留证据，不然人工看不出是谁被折过分量
  if (melee.length === 0 && linkage.discountedHorizontal + linkage.discountedByArea === 0) return undefined;
  const cap = effectiveMarks(marks, rules, "cap");
  const hitbox = effectiveMarks(marks, rules, "hitbox");
  return {
    meleeHits: melee.length,
    byNameHits: melee.filter((mark) => mark.byName).length,
    areaHits: melee.filter((mark) => mark.area).length,
    // 折分量看的是 联弹 的方向与 area，不看近战门，所以这几列在全部子弹上数（非近战联弹照样打折）
    linkageHorizontalHits: linkage.discountedHorizontal,
    linkageAreaHits: linkage.discountedByArea,
    linkageVerticalHits: linkage.vertical,
    spreadHits: melee.filter((mark) => !mark.area).length,
    clusters: cap.clusters,
    countedCap: cap.kept.length,
    countedHitbox: hitbox.kept.length,
    unpositionedClusters: hitbox.unpositionedClusters,
    segmentsUnfiltered: marks.reduce((sum, mark) => sum + mark.values.segments, 0) / attacks,
    segmentsCap: pelletSum(cap.kept, rules) / attacks,
    segmentsHitbox: pelletSum(hitbox.kept, rules) / attacks,
    mode: rules.mode,
  };
}

/** 穿刺口径的复核块：这一招里哪几种子弹被认成穿刺/次级穿刺、各多少颗。 */
export interface PierceSegmentAudit {
  pierceHits: number;
  secondaryHits: number;
  /** 实际命中的种类串（含靠元件名命中的），人工据此核对词表覆盖到哪一类。 */
  pierceKinds: string[];
  secondaryKinds: string[];
  /** 靠子弹元件名（而不是 子弹种类 声明）认出穿刺的颗数。 */
  byNameHits: number;
}

function pierceAudit(marks: BulletMark[]): PierceSegmentAudit | undefined {
  const hit = marks.filter((mark) => mark.pierce !== undefined);
  if (hit.length === 0) return undefined;
  const pierce = hit.filter((mark) => mark.pierce?.tier === "pierce");
  const secondary = hit.filter((mark) => mark.pierce?.tier === "次级穿刺");
  return {
    pierceHits: pierce.length,
    secondaryHits: secondary.length,
    pierceKinds: [...new Set(pierce.map((mark) => mark.pierce?.text ?? ""))],
    secondaryKinds: [...new Set(secondary.map((mark) => mark.pierce?.text ?? ""))],
    byNameHits: hit.filter((mark) => mark.pierce?.byName ?? false).length,
  };
}

/** 函数式发弹的复核块：一个发弹函数在这一招里对应多少段、多少倍率、真实触发过几次。 */
export interface FunctionShotAudit {
  name: string;
  /** 函数体声明在哪份文件（相对 LIBRARY）；不是本文件时要在疑点里说明。 */
  declaredIn: string;
  /** 一次发弹的段数（函数体的 霰弹值）。 */
  pelletsPerShot: number;
  /** 函数体 子弹威力 折出的倍率；读不出数值时不写。 */
  multiplier?: number;
  expressions: string[];
  /** 函数体声明的 子弹种类（联弹/穿刺 的判定就靠它）。 */
  kinds: string[];
  throttle: number;
  throttleBasis: ThrottleBasis;
  /** 有效帧内真实触发的调用次数（enterFrame 按在台帧数累计）。 */
  calls: number;
  /** 折出来的发弹颗数（calls 过闸门之后）。 */
  emissions: number;
  /** 这些发弹颗折进段数账里的分量（已过近战颗数、联弹与穿刺三层）。 */
  pelletSum: number;
}

/** 把同一招里同一个发弹函数的调用点并成一条账。 */
function functionShotAudit(tallies: Map<string, FunctionShotAudit>): FunctionShotAudit[] | undefined {
  if (tallies.size === 0) return undefined;
  return [...tallies.values()].sort((a, b) => b.emissions - a.emissions || a.name.localeCompare(b.name, "zh"));
}


/**
 * 作用域脚本里真正跳转到的状态名（含技能库条目）。
 * 跳转常用变量拼名字（`状态改变("a" + 随机数)`），所以同文件同前缀的标签一起算被引用，
 * 只把真正没人 goto 的孤立标签判成废弃动画。
 */
function referencedLabels(files: SymbolFile[]): Set<string> {
  const names = new Set<string>();
  for (const file of files) {
    const scripts = groups(file.xml, SCRIPT).join("\n");
    groups(scripts, JUMP).forEach((label) => names.add(label));
    groups(scripts, SKILL_PUSH, 2).forEach((label) => names.add(label));
  }
  return names;
}

/** 标签去掉尾随数字得到的前缀族名（a0/a1/a2 同族，打一下 保持原样）。 */
function labelStem(label: string): string {
  return label.replace(/\d+$/, "");
}

/** 摆放树深度：容器 → 动画 → 动画再摆的子元件，实测三层够用，留一层余量。 */
const MAX_PLACEMENT_DEPTH = 4;

/** 容器时间轴上的一段状态：状态名与它覆盖的帧区间。 */
interface StateSegment {
  label: string;
  start: number;
  end: number;
}

function segmentsOfLane(labeled: ParsedFrame[], end: number): StateSegment[] {
  return labeled.map((frame) => ({
    label: frame.label ?? "",
    start: frame.index,
    end: frame.index + spanOf(frame, labeled, end),
  }));
}

/**
 * 容器的状态段：取标签最多的那一层（状态机层），按标签切段。
 * 敌人容器普遍是"一层状态机 + 若干动作层"：动作层在某个状态段里摆一个动画元件，
 * 那个动画元件是干什么的，就由盖住它摆放帧的状态段决定。
 */
function stateSegmentsOf(container: SymbolFile): StateSegment[] {
  const frames = framesOf(container.xml);
  if (frames.length === 0) return [];
  const end = Math.max(...frames.map((frame) => frame.index + frame.duration)) + 1;
  const byLane = new Map<number, ParsedFrame[]>();
  for (const frame of frames) {
    if (frame.label === undefined) continue;
    const bucket = byLane.get(frame.lane);
    if (bucket === undefined) byLane.set(frame.lane, [frame]);
    else bucket.push(frame);
  }
  let best: StateSegment[] = [];
  let bestScore = 0;
  for (const labeled of byLane.values()) {
    const segments = segmentsOfLane(labeled, end);
    // 段数优先，段数相同看覆盖的帧数
    const score = segments.length * 1_000_000 + segments.reduce((sum, segment) => sum + (segment.end - segment.start), 0);
    if (score > bestScore) {
      bestScore = score;
      best = segments;
    }
  }
  return best;
}

/** 这一帧落在容器的哪个状态段里；盖不住段（状态层没标签）时返回 undefined。 */
function stateAt(segments: StateSegment[], index: number): string | undefined {
  return segments.find((segment) => index >= segment.start && index < segment.end)?.label;
}

/** 容器沿摆放链能拿到的一个元件，以及它被摆在哪些状态下。 */
interface PlacementNode {
  file: SymbolFile;
  /** 离容器的摆放层数：容器自己是 0 层，容器直接摆的动画是 1 层。 */
  depth: number;
  /** 摆它的状态名；同一个元件被多个状态摆到就都记下来。容器自己为空 —— 它的标签本身就是状态名。 */
  states: Set<string>;
}

/**
 * 容器的摆放树（含容器自己，最深 4 层）+ 每个元件挂在哪些状态段下。
 * 这是招式唯一的来源：同一个库里住着好几只怪是常态，兄弟怪的动画、摆放链之外的共享素材都不算这只怪的招式。
 * 1 层元件按摆放帧所在的状态段定性，更深的层继承父元件的状态 —— 出手动画再摆的子弹与特效仍然属于那一招。
 */
function placementNodes(files: SymbolFile[], container: SymbolFile): PlacementNode[] {
  const resolve = itemResolver(files);
  const segments = stateSegmentsOf(container);
  const cache = new Map<string, ParsedFrame[]>();
  const parsed = (file: SymbolFile): ParsedFrame[] => {
    const hit = cache.get(file.relPath);
    if (hit !== undefined) return hit;
    const frames = framesOf(file.xml);
    cache.set(file.relPath, frames);
    return frames;
  };
  const root: PlacementNode = { file: container, depth: 0, states: new Set<string>() };
  const nodes = new Map<string, PlacementNode>([[container.relPath, root]]);
  let frontier: PlacementNode[] = [root];
  for (let depth = 0; depth < MAX_PLACEMENT_DEPTH; depth += 1) {
    const next: PlacementNode[] = [];
    for (const node of frontier) {
      for (const frame of parsed(node.file)) {
        const inherited = [...node.states];
        for (const instance of frame.placed) {
          if (instance.item === undefined) continue;
          const hit = resolve(instance.item);
          if (hit === undefined || hit.relPath === node.file.relPath) continue;
          const state = node.depth === 0 ? stateAt(segments, frame.index) : undefined;
          const names = state === undefined ? inherited : [state];
          const existing = nodes.get(hit.relPath);
          if (existing !== undefined) {
            existing.depth = Math.min(existing.depth, node.depth + 1);
            names.forEach((name) => existing.states.add(name));
            continue;
          }
          const child: PlacementNode = { file: hit, depth: node.depth + 1, states: new Set(names) };
          nodes.set(hit.relPath, child);
          next.push(child);
        }
      }
    }
    if (next.length === 0) break;
    frontier = next;
  }
  return [...nodes.values()];
}

/** 这个元件是不是挂在攻击样状态上：容器自己看它的标签里有没有攻击样，其它层看继承来的状态名。 */
function isAttackBound(node: PlacementNode, rules: AttackStateRules): boolean {
  if (node.depth !== 0) return [...node.states].some((name) => isAttackState(name, rules));
  return framesOf(node.file.xml).some((frame) => frame.label !== undefined && isAttackState(frame.label, rules));
}

/**
 * 霸体系数的元件观测口径（制作组 2026-10-05）。工作簿只给了五档表
 * （长击退可击飞 1 / 短击退可击飞 2 / 长击退不可击飞 3 / 短击退不可击飞 4 / 不可击退不可击飞 5），
 * 档位怎么从元件里读全在这里：
 * - 可击飞 = **击倒 与 倒地 两段各自都有生效的击飞代码，并且那段确实摆了元件**。统一写法是状态段里实例上的
 *   `_parent.击飞浮空();` / `_parent.击飞倒地();`；没并进去的老模板把浮空代码内联在同一段上
 *   （`_parent.浮空 = true;` 加一段自写的 onEnterFrame 落回 Z 轴坐标），认 inlineAirborneWords ——
 *   这类同样算可击飞：代码逻辑在上面，只是没统一成那两个函数。
 *   两条都不认（制作组 2026-10-05 定）：只摆了名字叫击飞的元件而没有代码不算，那是美术摆放；
 *   注释里的代码（行注释与块注释）也不算，匹配前先剔注释。
 * - 击退长短看 被击 状态里那段受创动画：每个命名帧到下一个 动画完毕 的持续就是一发击退时长，
 *   没有命名帧就按第一帧到 动画完毕。大于 longKnockbackFrames 算长击退，否则短击退
 *   （与招式那边的命名帧计时同一个口径）。一次出手有多发时按 knockbackReading 归成一个判断。
 * - 被击 状态读不出击退时长（没有这个状态、或该状态段里没摆出可读的元件）就是不可击退，取 5；
 *   击倒/倒地 缺一段、段里没摆元件、或摆了但没有击飞逻辑，就是不可击飞，取 3 或 4。
 * 词表与阈值都写在 data/monster-census.json 的 armorRules 里，人工改口径不改代码。
 */
export interface ArmorRules {
  /** 击倒 状态段的词。 */
  knockdownWords: string[];
  /** 倒地 状态段的词。 */
  lyingWords: string[];
  /** 被击 状态段的词。 */
  hitWords: string[];
  /** 统一写法的击飞函数名：实例脚本或帧脚本里出现任一就是可击飞的证据。 */
  airborneCallWords: string[];
  /** 没统一进函数、内联在状态段上的浮空写法；按去掉空白后的脚本匹配，命中同样算可击飞。 */
  inlineAirborneWords: string[];
  /** 摆了击飞逻辑的元件名词。只用来把「摆了元件但没代码」的原因写准，本身不构成击飞证据。 */
  airborneInstanceWords: string[];
  /** 长击退的帧门槛：命名帧到 动画完毕 的持续**大于**该帧数才算长击退。 */
  longKnockbackFrames: number;
  /** 一次出手有多发击退时长时怎么归成一个长短判断：any 有一发长就算长、all 全都长才算长、mean 按均值。 */
  knockbackReading: "any" | "all" | "mean";
}

export const DEFAULT_ARMOR_RULES: ArmorRules = {
  knockdownWords: ["击倒"],
  lyingWords: ["倒地"],
  hitWords: ["被击", "受创", "受伤"],
  airborneCallWords: ["击飞浮空", "击飞倒地"],
  inlineAirborneWords: ["浮空 = true", "倒地 = true", "被击飞浮空"],
  airborneInstanceWords: ["击飞"],
  longKnockbackFrames: 9,
  knockbackReading: "any",
};

/** 一条击飞证据：哪一段、哪一帧、命中哪个词、以什么写法命中。 */
export interface ArmorEvidence {
  /** 状态段名（击倒 / 倒地）。 */
  state: string;
  /** 容器时间轴上的帧号。 */
  frame: number;
  /** 命中的词。 */
  word: string;
  /** 命中途径：统一函数 / 内联写法。元件名不算途径，只出现在 concerns 里。 */
  via: "函数" | "内联";
  /** 摆的元件名；脚本命中时也给，用来核对证据挂在哪段动画上。 */
  item?: string;
}

/** 一发击退的时长：受创动画里一个命名帧到 动画完毕 的持续。 */
export interface ArmorKnockbackSpan {
  /** 受创动画所在文件（相对 LIBRARY）。 */
  file: string;
  /** 计时起点：命名帧名；这份动画没有命名帧时写（整段）。 */
  label: string;
  /** 计时起点帧号。 */
  start: number;
  /** 击退时长（帧）。 */
  frames: number;
  /** 收口依据：认到 动画完毕 调用，还是退回这份动画的时间轴末尾。 */
  basis: "动画完毕" | "段尾";
}

export interface MonsterArmorMeasure {
  /** 五档观测值：1 长击退可击飞 / 2 短击退可击飞 / 3 长击退不可击飞 / 4 短击退不可击飞 / 5 不可击退不可击飞。 */
  factor?: number;
  /** 档位名，与工作簿那张表逐字对齐。 */
  band?: string;
  /** 击倒 与 倒地 两段是否各自都有击飞逻辑。 */
  airborne?: boolean;
  /** 击退长短：长 / 短 / 不可（读不出击退时长）。 */
  knockback?: "长" | "短" | "不可";
  /** 容器时间轴上有没有 被击 状态段。 */
  hitStateFound: boolean;
  /** 命中词表的状态段名与帧范围（被击/被击--/被击-无 一类变体都会列出来）。 */
  hitStates: string;
  /** 容器摆出的受创动画文件数。 */
  hitFiles: number;
  /** 击飞证据逐条列出（没证据就是空数组，人工据此判是不是词表没覆盖）。 */
  evidences: ArmorEvidence[];
  /** 每发击退的时长账。 */
  knockbackSpans: ArmorKnockbackSpan[];
  concerns: string[];
}

/** 状态段里按词表挑出来的那几段。 */
function rangesOf(segments: StateSegment[], words: string[]): StateSegment[] {
  return segments.filter((segment) => words.some((word) => segment.label.includes(word)));
}

/** 落在这些状态段范围里的容器帧。 */
function framesInRanges(frames: ParsedFrame[], ranges: StateSegment[]): ParsedFrame[] {
  return frames.filter((frame) => ranges.some((range) => frame.index >= range.start && frame.index < range.end));
}

/** 五档观测值 → 工作簿那张表的档位名。 */
const ARMOR_BAND_NAMES: Record<number, string> = {
  1: "长击退可击飞",
  2: "短击退可击飞",
  3: "长击退不可击飞",
  4: "短击退不可击飞",
  5: "不可击退不可击飞",
};

function armorBand(factor: number): string {
  return ARMOR_BAND_NAMES[factor] ?? `未知档 ${factor}`;
}

/**
 * 剔掉 AS2 的行注释与块注释，只留生效代码。注释里的 `_parent.倒地 = true;` 是废弃写法，
 * 现网确实有整块 onClipEvent 被块注释包着的怪（鳄嘴兽人），不能当击飞逻辑。
 */
function stripAs2Comments(text: string): string {
  let out = "";
  let index = 0;
  while (index < text.length) {
    const char = text[index];
    const next = text[index + 1];
    if (char === "/" && next === "/") {
      while (index < text.length && text[index] !== "\n") index += 1;
      continue;
    }
    if (char === "/" && next === "*") {
      const close = text.indexOf("*/", index + 2);
      index = close < 0 ? text.length : close + 2;
      continue;
    }
    out += char;
    index += 1;
  }
  return out;
}

/**
 * 量 霸体系数：只读容器自己的时间轴（击倒/倒地/被击 三段的状态定性都在容器层），
 * 击退时长再进到 被击 摆出的那份受创动画里量命名帧。
 */
export function measureArmor(container: SymbolFile, files: SymbolFile[], rules: ArmorRules): MonsterArmorMeasure {
  const frames = framesOf(container.xml);
  const segments = stateSegmentsOf(container);
  const resolve = itemResolver(files);
  const flat = (text: string): string => stripAs2Comments(text).replace(/\s+/g, "");
  const needles: { word: string; via: "函数" | "内联" }[] = [
    ...rules.airborneCallWords.map((word) => ({ word, via: "函数" as const })),
    ...rules.inlineAirborneWords.map((word) => ({ word, via: "内联" as const })),
  ];

  const evidenceOf = (words: string[]): { ranges: StateSegment[]; evidences: ArmorEvidence[]; placements: string[] } => {
    const ranges = rangesOf(segments, words);
    const evidences: ArmorEvidence[] = [];
    const placements: string[] = [];
    const state = ranges.map((range) => range.label).join("、");
    for (const frame of framesInRanges(frames, ranges)) {
      for (const script of frame.frameScripts) {
        const text = flat(script);
        for (const needle of needles) {
          if (text.includes(flat(needle.word))) evidences.push({ state, frame: frame.index, ...needle });
        }
      }
      for (const instance of frame.placed) {
        for (const script of instance.scripts) {
          const text = flat(script);
          for (const needle of needles) {
            if (text.includes(flat(needle.word))) {
              evidences.push({
                state,
                frame: frame.index,
                ...needle,
                ...(instance.item === undefined ? {} : { item: instance.item }),
              });
            }
          }
        }
        if (instance.item !== undefined && rules.airborneInstanceWords.some((word) => instance.item!.includes(word))) {
          placements.push(instance.item);
        }
      }
    }
    return { ranges, evidences, placements };
  };

  const knockdown = evidenceOf(rules.knockdownWords);
  const lying = evidenceOf(rules.lyingWords);
  const concerns: string[] = [];
  const missing = (name: string, scanned: ReturnType<typeof evidenceOf>): string | undefined => {
    if (scanned.ranges.length === 0) return `容器状态段里没有${name}`;
    const scoped = framesInRanges(frames, scanned.ranges);
    if (scoped.every((frame) => frame.placed.length === 0 && frame.frameScripts.length === 0)) return `${name} 状态段里没摆元件也没帧脚本`;
    if (scoped.every((frame) => frame.placed.length === 0)) return `${name} 状态段只有帧脚本、没摆元件`;
    if (scanned.evidences.length === 0)
      return scanned.placements.length > 0
        ? `${name} 状态段摆了 ${scanned.placements[0]} 这类击飞元件，但没有生效击飞代码（元件名与注释里的代码都不算）`
        : `${name} 状态段摆了元件但没有击飞逻辑`;
    return undefined;
  };
  const knockdownGap = missing("击倒", knockdown);
  const lyingGap = missing("倒地", lying);
  const airborne = knockdownGap === undefined && lyingGap === undefined;
  if (knockdownGap !== undefined) concerns.push(knockdownGap);
  if (lyingGap !== undefined) concerns.push(lyingGap);

  // 击退时长：被击 段摆出来的那份受创动画里，每个命名帧到下一个 动画完毕 的持续
  const hit = rangesOf(segments, rules.hitWords);
  const hitFrames = framesInRanges(frames, hit);
  const hitInstances = hitFrames.flatMap((frame) => frame.placed);
  const hitFiles: SymbolFile[] = [];
  const unresolvedItems: string[] = [];
  for (const instance of hitInstances) {
    if (instance.item === undefined) continue;
    const file = resolve(instance.item);
    if (file === undefined) {
      if (!unresolvedItems.includes(instance.item)) unresolvedItems.push(instance.item);
      continue;
    }
    if (!hitFiles.some((known) => known.relPath === file.relPath)) hitFiles.push(file);
  }
  const spans: ArmorKnockbackSpan[] = [];
  for (const file of hitFiles) {
    const all = framesOf(file.xml);
    if (all.length === 0) {
      concerns.push(`被击 摆的 ${file.relPath} 读不到时间轴`);
      continue;
    }
    const start = Math.min(...all.map((frame) => frame.index));
    const end = Math.max(...all.map((frame) => frame.index + frame.duration)) + 1;
    const over = all.filter((frame) => frameOverCall(frame)).map((frame) => frame.index).sort((a, b) => a - b);
    const named = new Map<string, ParsedFrame>();
    for (const frame of all) {
      if (frame.label === undefined) continue;
      const key = `${frame.label}@${frame.index}`;
      if (!named.has(key)) named.set(key, frame);
    }
    const targets = [...named.values()].sort((a, b) => a.index - b.index);
    if (targets.length === 0) {
      const stop = over.find((index) => index >= start);
      spans.push({
        file: file.relPath,
        label: "（整段）",
        start,
        frames: (stop ?? end) - start,
        basis: stop === undefined ? "段尾" : "动画完毕",
      });
      if (stop === undefined) concerns.push(`${file.relPath} 没有命名帧也没有 动画完毕，击退时长按动画末尾折算`);
      continue;
    }
    for (const frame of targets) {
      const stop = over.find((index) => index >= frame.index);
      spans.push({
        file: file.relPath,
        label: frame.label ?? "",
        start: frame.index,
        frames: (stop ?? end) - frame.index,
        basis: stop === undefined ? "段尾" : "动画完毕",
      });
      if (stop === undefined) concerns.push(`${file.relPath} 的 ${frame.label} 之后没有 动画完毕，击退时长按动画末尾折算`);
    }
  }

  const measure: MonsterArmorMeasure = {
    hitStateFound: hit.length > 0,
    hitStates: hit.map((range) => `${range.label}(${range.start}~${range.end})`).join("、"),
    hitFiles: hitFiles.length,
    evidences: [...knockdown.evidences, ...lying.evidences],
    knockbackSpans: spans,
    concerns,
  };
  if (hitFiles.length === 0) {
    if (hit.length === 0) concerns.push("容器状态段里没有 被击");
    else if (hitInstances.length === 0)
      concerns.push(`被击 段（${measure.hitStates}）盖住的 ${hitFrames.length} 帧里没摆元件`);
    else if (unresolvedItems.length > 0)
      concerns.push(`被击 段摆了 ${hitInstances.length} 个元件，${unresolvedItems.slice(0, 3).join("、")} 解析不到库文件`);
    else concerns.push(`被击 段（${measure.hitStates}）摆的元件都没有时间轴`);
  }
  if (spans.length === 0) {
    concerns.push("读不出击退时长，按不可击退取 5");
    return { ...measure, airborne, factor: 5, band: armorBand(5), knockback: "不可" };
  }
  const long =
    rules.knockbackReading === "any"
      ? spans.some((span) => span.frames > rules.longKnockbackFrames)
      : rules.knockbackReading === "all"
        ? spans.every((span) => span.frames > rules.longKnockbackFrames)
        : spans.reduce((sum, span) => sum + span.frames, 0) / spans.length > rules.longKnockbackFrames;
  const factor = airborne ? (long ? 1 : 2) : long ? 3 : 4;
  if (spans.some((span) => span.basis === "段尾")) concerns.push("击退时长有按动画末尾折算的发，人工复核阈值判定");
  return { ...measure, airborne, factor, band: armorBand(factor), knockback: long ? "长" : "短" };
}

/** 注册表里的一条源：编译产物口径的 swf 路径 + 库内元件名。 */
export interface AssetSource {
  swf: string;
  symbol?: string;
}

/** `<conflict>`/`<duplicate>` 块里记下的一条候选源：位置有，选哪份留给人工。 */
export interface UnresolvedAssetSource extends AssetSource {
  /** conflict = 同一个导出名住在多个包；duplicate = 同一个包里有多处导出。 */
  kind: "conflict" | "duplicate";
  /** 扫描器标了孤儿（库面板看不到，但编译产物可能仍导出）。 */
  orphan: boolean;
}

/** data/monster-census.json 里的人工定源条目。 */
export interface AttackSourceOverride extends AssetSource {
  /** 库内元件名（注册表的 symbolName 写法）。 */
  symbolName?: string;
  /** 为什么选这份、另一份实测差多少 —— 给人看的账，不参与判定。 */
  note?: string;
}

export interface MonsterAttackInput {
  spritename: string;
  /** 面板空手攻击力均值，用于把固定值伤害折算成倍率。 */
  panelAtkMin: number;
  panelAtkMax: number;
  /** 段数的一次攻击换算窗口（帧），量子弹跨度用；口径值写在 data/monster-census.json。 */
  segmentWindowFrames: number;
  /** 攻击样状态词表，缺省用 DEFAULT_ATTACK_STATE_RULES；口径写在配置里，人工可改词表不改代码。 */
  stateRules?: AttackStateRules;
  /** 近战子弹有效颗数口径，缺省用 DEFAULT_MELEE_BULLET_RULES；词表与命中框尺寸同样写在 data/monster-census.json。 */
  meleeRules?: MeleeBulletRules;
  /** 穿刺子弹的段数倍率口径，缺省用 DEFAULT_PIERCE_SEGMENT_RULES；词表与倍数写在 data/monster-census.json。 */
  pierceRules?: PierceSegmentRules;
  /** 霸体系数 的元件观测口径，缺省用 DEFAULT_ARMOR_RULES；词表与击退帧阈值都写在配置里。 */
  armorRules?: ArmorRules;
  /**
   * 注册表把这个模板记在 `<conflict>`/`<duplicate>` 里的候选源。
   * 只用来把"量不到"的原因写准（有素材但没定源 ≠ 注册表里查不到），不参与取源。
   */
  unresolvedSources?: UnresolvedAssetSource[];
}

interface LabelSpan {
  file: SymbolFile;
  label: string;
  span: number;
  start: number;
  window: ParsedFrame[];
  /** 这段是标签切出来的，还是靠播放头顺播打出来的（标签没盖住的段落 / 整个文件没标签）。 */
  kind: "label" | "gap" | "whole";
}

const MIN_WHOLE_TIMELINE_FRAMES = 4;

/**
 * 扫一个动画文件里的招式：带标签按标签切段；标签没盖住的段落、或整个文件没有标签的时间轴，
 * 只要够长就各算一招 —— 顺播到底的动画里这些段一样会打出来。
 */
function spansOf(file: SymbolFile, wholeAllowed: boolean): LabelSpan[] {
  const frames = framesOf(file.xml);
  if (frames.length === 0) return [];
  const start = Math.min(...frames.map((frame) => frame.index));
  const end = Math.max(...frames.map((frame) => frame.index + frame.duration)) + 1;
  const spans = new Map<string, LabelSpan>();
  for (const frame of frames) {
    if (frame.label === undefined) continue;
    const span = spanOf(frame, frames.filter((other) => other.lane === frame.lane), end);
    const existing = spans.get(frame.label);
    if (existing !== undefined && existing.span >= span) continue;
    spans.set(frame.label, {
      file,
      label: frame.label,
      span,
      start: frame.index,
      window: frames
        .filter((other) => other.index >= frame.index && other.index < frame.index + span)
        .sort((a, b) => a.index - b.index),
      kind: "label",
    });
  }
  const found = [...spans.values()];
  if (!wholeAllowed) return found;
  const stem = path.posix.basename(file.relPath, ".xml");
  if (found.length === 0) {
    if (end - start > MIN_WHOLE_TIMELINE_FRAMES) {
      found.push({
        file,
        label: `${stem}（整段）`,
        span: end - start,
        start,
        window: [...frames].sort((a, b) => a.index - b.index),
        kind: "whole",
      });
    }
    return found;
  }
  const covered = new Set<number>();
  for (const span of found) {
    for (let index = span.start; index < span.start + span.span; index += 1) covered.add(index);
  }
  const gaps: LabelSpan[] = [];
  let run: ParsedFrame[] = [];
  const flush = (): void => {
    const first = run[0];
    const last = run.at(-1);
    if (first !== undefined && last !== undefined && last.index + last.duration - first.index >= MIN_WHOLE_TIMELINE_FRAMES) {
      gaps.push({
        file,
        label: `${stem}（未标注段 ${first.index}~${last.index}）`,
        span: last.index + last.duration - first.index,
        start: first.index,
        window: [...run],
        kind: "gap",
      });
    }
    run = [];
  };
  for (const frame of [...frames].sort((a, b) => a.index - b.index)) {
    if (covered.has(frame.index)) flush();
    else run.push(frame);
  }
  flush();
  return [...found, ...gaps];
}

/** 量一只怪的有效招式：容器定位 → 沿摆放树取攻击样状态上的动画 → 标签切段 → 逐帧数子弹实例。 */
export function measureMonsterAttack(
  input: MonsterAttackInput,
  assets: Map<string, AssetSource[]>,
  repoRoot: string,
): MonsterAttackMeasure {
  const panelAtkMid = (input.panelAtkMin + input.panelAtkMax) / 2;
  const rules = input.stateRules ?? DEFAULT_ATTACK_STATE_RULES;
  const melee = input.meleeRules ?? DEFAULT_MELEE_BULLET_RULES;
  const pierce = input.pierceRules ?? DEFAULT_PIERCE_SEGMENT_RULES;
  const windowFrames = input.segmentWindowFrames;
  const candidates = assets.get(input.spritename) ?? [];
  for (const asset of candidates) {
    const pkg = packageFor(asset.swf, repoRoot);
    if (pkg === null || pkg.files.length === 0) continue;
    const symbol = asset.symbol;
    const container =
      pkg.files.find((file) => file.xml.includes(`linkageIdentifier="${input.spritename}"`)) ??
      (symbol === undefined
        ? undefined
        : pkg.files.find((file) => path.posix.basename(file.relPath, ".xml") === path.posix.basename(symbol))) ??
      pkg.files.find((file) => path.posix.basename(file.relPath, ".xml") === input.spritename);
    if (container === undefined) continue;

    const nodes = placementNodes(pkg.files, container);
    const resolve = itemResolver(pkg.files);
    const referenced = referencedLabels(nodes.map((node) => node.file));
    const containerScripts = groups(container.xml, SCRIPT).join("\n");
    const carriers = new Map<string, string[] | null>();
    const carrierOf = (item: string): string[] | undefined => {
      const file = resolve(item);
      return file === undefined ? undefined : carrierScripts(file, carriers);
    };
    // 归属硬门：招式只来自容器沿摆放链拿得到的元件。容器直接摆的那层先看，
    // 一个有效招式都没有（出手动画由中间层元件再摆）才往里再找一层。
    const placedNodes = nodes.filter((node) => node.depth <= 1);
    const widenedNodes = nodes.filter((node) => node.depth >= 2);
    // 容器帧脚本里声明的发弹函数：子动画只打一句调用，函数体与 性能倍率 的数值都住在容器上
    const containerFunctions = shootingFunctionsOf([container], panelAtkMid);

    const measure = (sources: PlacementNode[], pass: "placed" | "widened"): AttackSkillMeasure[] => {
      const out: AttackSkillMeasure[] = [];
      for (const node of sources) {
        const file = node.file;
        // 发弹函数可能声明在容器里、子动画只打一句 `_parent.射击()`：那种文件文本里没有 子弹威力，也得进来
        const own = shootingFunctionsOf([file], panelAtkMid);
        const funcs =
          file === container
            ? own
            : [...own, ...containerFunctions.filter((fn) => !own.some((entry) => entry.name === fn.name))];
        if (!file.xml.includes("子弹威力") && funcs.length === 0) continue;
        // 容器自己的标签就是状态名；1 层元件按摆放帧落在的状态段定性，更深的层继承父元件的状态
        const stateNames = node.depth === 0 ? [] : [...node.states];
        const attackStates = stateNames.filter((name) => isAttackState(name, rules));
        const boundToAttackState = node.depth === 0 ? true : attackStates.length > 0;
        // 状态硬门：只有挂在攻击样状态上的元件才产招式；无标签整段与未标注段落也只在这样的元件里找
        const spans = spansOf(file, pass === "placed" && boundToAttackState);
        // 本文件里被直接跳转到的标签前缀族：用来放行 状态改变("a"+随机数) 拼出来的兄弟标签
        const families = new Set(
          spans.filter((span) => span.kind === "label" && referenced.has(span.label)).map((span) => labelStem(span.label)),
        );
        // 按名调度的合集（有攻击样的标签被字面 goto 命中）里没人 goto 的标签是废弃动画；
        // 容器摆的动画若没人按名挑它的招式，就是播放头顺播到底 —— 每一段都会打出来。
        // 只被 goto 到 受创/站立 一类状态标签不算调度：那是宿主在挑状态，招式段仍然顺播。
        const dispatched = spans.some(
          (span) => span.kind === "label" && referenced.has(span.label) && !NON_ATTACK_LABEL.test(span.label),
        );
        for (const span of spans) {
          const marks: BulletMark[] = [];
          const windowEnd = span.start + span.span;
          const shotTally = new Map<string, FunctionShotAudit>();
          const fileScalars = numericScalarsOf(groups(file.xml, SCRIPT).join("\n"));
          for (const frame of span.window) {
            const hits = bulletMarks(frame, carrierOf);
            for (const hit of hits) {
              const values = instanceValues(hit.scripts, panelAtkMid, fileScalars);
              if (values.segments === 0) continue;
              marks.push(markOf(hit, values, frame.index - span.start, melee, pierce));
            }
            // 把自己当子弹摆出去的实例（内联或子弹元件带 子弹威力）已经计过一次命中，不再按它调用发弹函数重复计
            const consumed = new Set(
              hits.map((hit) => hit.instance).filter((instance): instance is PlacedInstance => instance !== undefined),
            );
            for (const site of shotSitesInFrame(frame, funcs, windowEnd, consumed)) {
              const hit: PlacedHit = {
                scripts: [site.fn.body],
                ...(site.anchor === undefined ? {} : { instance: site.anchor }),
                anchorNamed: true,
              };
              const key = `${site.fn.declaredIn}::${site.fn.name}`;
              const tally = shotTally.get(key) ?? {
                name: site.fn.name,
                declaredIn: site.fn.declaredIn,
                pelletsPerShot: site.fn.values.segments,
                ...(site.fn.values.multipliers.length > 0
                  ? { multiplier: site.fn.values.multipliers.reduce((s, v) => s + v, 0) / site.fn.values.multipliers.length }
                  : {}),
                expressions: site.fn.values.expressions,
                kinds: groups(site.fn.body, KIND),
                throttle: site.fn.throttle,
                throttleBasis: site.fn.throttleBasis,
                calls: 0,
                emissions: 0,
                pelletSum: 0,
              };
              tally.calls += site.calls;
              tally.emissions += site.offsets.length;
              for (const at of site.offsets) {
                const mark = markOf(hit, site.fn.values, at - span.start, melee, pierce);
                marks.push(mark);
                tally.pelletSum += pelletsOf(mark, melee);
              }
              shotTally.set(key, tally);
            }
          }
          const functionShots = functionShotAudit(shotTally);
          if (marks.length === 0) continue;
          const offsets = marks.map((mark) => mark.offset);
          const multipliers = marks.flatMap((mark) => mark.values.multipliers);
          const firstBulletOffset = Math.min(...offsets);
          const lastBulletOffset = Math.max(...offsets);
          const bulletSpanFrames = lastBulletOffset - firstBulletOffset;
          const attacks = attackCountOf(bulletSpanFrames, windowFrames);
          const chosen = effectiveMarks(marks, melee, melee.mode);
          const audit = meleeAudit(marks, melee, attacks);
          const pierceBlock = pierceAudit(marks);
          const dropped = marks.length - chosen.kept.length;
          // 后摇量子弹打完到招式结束：结束帧认 动画完毕 调用（出手动画靠它通知容器切状态），
          // 这份动画里没有该调用（写法不同或由容器直接切状态）就退回这一段动画的段尾，并把依据标出来。
          const overFrame = span.window
            .filter((frame) => frameOverCall(frame))
            .reduce((max, frame) => Math.max(max, frame.index - span.start), -1);
          const tailBasis: "动画完毕" | "段尾" = overFrame >= 0 ? "动画完毕" : "段尾";
          const rawTail = overFrame >= 0 ? overFrame - lastBulletOffset : span.span - 1 - lastBulletOffset;
          const tailFrames = Math.max(0, rawTail);
          // 状态名一律如实记下挂在哪些状态段上，被状态硬门否掉时人工才知道是哪一段挡的
          const state = node.depth === 0 ? span.label : stateNames.join("、");
          const stateOk = node.depth === 0 ? isAttackState(span.label, rules) : boundToAttackState;
          const direct = span.kind !== "label" || referenced.has(span.label);
          const byFamily = !direct && labelStem(span.label) !== "" && families.has(labelStem(span.label));
          // 容器直接摆放、又没人按名调度这个文件的标签 —— 顺播一定打到，视为有效招式。
          // 往里再找一层时继续要求字面跳转引用，免得共享元件串到兄弟怪身上。
          const byPlacement = pass === "placed" && !dispatched && !direct && !byFamily;
          const concerns: string[] = [];
          if (!stateOk) {
            concerns.push(
              `元件挂在「${stateNames.join("、") || "（摆放帧不在任何状态段里）"}」上，不在攻击样词表里`,
            );
          }
          if (!direct && !byFamily && !byPlacement) concerns.push("没被跳转引用（疑似废弃动画）");
          if (byFamily) concerns.push("同族标签被跳转，按拼名跳转放行");
          if (byPlacement) concerns.push("容器摆放的动画无人按名调度，标签顺播，按摆放放行");
          if (span.kind === "whole") concerns.push("动画元件没有状态标签，整段计一招");
          if (span.kind === "gap") concerns.push("标签没盖住的段落，按顺播计一招");
          if (pass === "widened") concerns.push(`元件在摆放链第 ${node.depth} 层，归属需复核`);
          if (NON_ATTACK_LABEL.test(span.label)) concerns.push("状态名不像攻击");
          if (marks.every((mark) => mark.values.relative === 0 && mark.values.fixed > 0))
            concerns.push("倍率来自固定值伤害，按面板均值折算");
          if (tailBasis === "段尾") concerns.push("这段动画里没有 动画完毕 调用，后摇按段尾折算");
          if (rawTail < 0) concerns.push(`动画完毕 在末子弹之前（第 ${overFrame} 帧），后摇按 0 记`);
          if (functionShots !== undefined) {
            const calls = functionShots.reduce((sum, shot) => sum + shot.calls, 0);
            const emissions = functionShots.reduce((sum, shot) => sum + shot.emissions, 0);
            concerns.push(
              `${functionShots.map((shot) => shot.name).join("、")} 由函数发弹：有效帧内真实触发 ${calls} 次，闸门后折出 ${emissions} 颗`,
            );
            for (const shot of functionShots) {
              if (shot.throttleBasis === "读不出") concerns.push(`${shot.name} 的闸门变量读不出数值，按每次调用都发一颗算`);
              if (shot.declaredIn !== file.relPath)
                concerns.push(`${shot.name} 的函数体在 ${shot.declaredIn} 里声明，本文件只有调用`);
            }
          }
          // 三本账都在全部子弹上数，不看 audit 在不在：只摆纵向联弹的一招不出 audit 块，账也得报
          const linkage = linkageTally(marks);
          if (linkage.discountedHorizontal + linkage.discountedByArea > 0)
            concerns.push(
              `${linkage.discountedHorizontal} 颗横向联弹、${linkage.discountedByArea} 颗传了 area 的联弹，霰弹值 按 ${melee.linkageFactor} 折分量`,
            );
          if (linkage.vertical > 0) concerns.push(`${linkage.vertical} 颗纵向联弹，霰弹值 不折分量`);
          if (linkage.fullValue > 0)
            concerns.push(
              `${linkage.fullValue} 颗含 联弹 但既没传 area、种类也不在 linkageHorizontalWords 里，霰弹值 按全值算`,
            );
          if (audit !== undefined && audit.byNameHits > 0)
            concerns.push(`${audit.byNameHits} 颗没声明 子弹种类，按子弹元件名认成近战类`);
          if (audit !== undefined && audit.unpositionedClusters > 0)
            concerns.push(`${audit.unpositionedClusters} 拨读不到子弹坐标，几何法退回每拨最多 ${melee.clusterCap} 颗`);
          if (audit !== undefined && dropped > 0)
            concerns.push(
              `${audit.spreadHits} 颗无区域近战子弹分 ${audit.clusters} 摆，按${
                melee.mode === "cap" ? `每拨最多 ${melee.clusterCap} 颗` : `玩家命中框 ${melee.hitboxWidth}×${melee.hitboxHeight} 最多框住的颗数`
              }只算 ${audit.spreadHits - dropped} 颗`,
            );
          if (pierceBlock !== undefined && pierceBlock.pierceHits > 0)
            concerns.push(
              `${pierceBlock.pierceHits} 颗穿刺子弹（${pierceBlock.pierceKinds.join("、")}）段数按 ${pierce.pierceFactor} 倍计`,
            );
          if (pierceBlock !== undefined && pierceBlock.secondaryHits > 0)
            concerns.push(
              `${pierceBlock.secondaryHits} 颗次级穿刺子弹（${pierceBlock.secondaryKinds.join("、")}）段数按 ${pierce.secondaryPierceFactor} 倍计`,
            );
          if (pierceBlock !== undefined && pierceBlock.byNameHits > 0)
            concerns.push(`${pierceBlock.byNameHits} 颗没声明 子弹种类，按子弹元件名认成穿刺`);
          out.push({
            file: span.file.relPath,
            label: span.label,
            frames: span.span,
            attacks,
            tempoFrames: span.span / attacks,
            segments: pelletSum(chosen.kept, melee) / attacks,
            windupFrames: firstBulletOffset,
            firstBulletOffset,
            lastBulletOffset,
            bulletSpanFrames,
            tailFrames,
            tailBasis,
            hits: marks.length,
            ...(audit === undefined ? {} : { melee: audit }),
            ...(pierceBlock === undefined ? {} : { pierce: pierceBlock }),
            ...(functionShots === undefined ? {} : { functionShots }),
            ...(multipliers.length > 0
              ? { multiplier: multipliers.reduce((sum, value) => sum + value, 0) / multipliers.length }
              : {}),
            expressions: [...new Set(marks.flatMap((mark) => mark.values.expressions))].slice(0, 6),
            ...(state === "" ? {} : { state }),
            depth: node.depth,
            usable: stateOk && (direct || byFamily || byPlacement) && !NON_ATTACK_LABEL.test(span.label),
            concerns,
          });
        }
      }
      return out;
    };

    let skills = measure(placedNodes, "placed");
    let scope: MonsterAttackMeasure["scope"] = "placed";
    // 容器直接摆的那层没有一个有效招式（出手动画由中间层元件再摆）才沿摆放链往里再找一层
    if (!skills.some((skill) => skill.usable) && widenedNodes.length > 0) {
      skills = [...skills, ...measure(widenedNodes, "widened")];
      scope = "widened";
    }
    const usable = skills.filter((skill) => skill.usable);
    skills.sort((a, b) => a.file.localeCompare(b.file) || a.label.localeCompare(b.label));

    // 一个招式都没量到时的两种解释要分开：摆放链里根本没有攻击样状态上的元件，还是有但打不出子弹实例
    const boundCount = nodes.filter(
      (node) => node.file.xml.includes("子弹威力") && isAttackBound(node, rules),
    ).length;
    const desire = groups(containerScripts, DESIRE).map((value) => Number(value));
    const gates = [...new Set(groups(containerScripts, GATE).map((value) => (value === "" ? "×1" : value.replace(/\s/g, ""))))];
    return {
      spritename: input.spritename,
      source: asset.swf,
      kind: pkg.kind,
      scope,
      ...(desire.length > 0 ? { attackDesire: desire } : {}),
      ...(gates.length > 0 ? { gates } : {}),
      skills,
      armor: measureArmor(container, pkg.files, input.armorRules ?? DEFAULT_ARMOR_RULES),
      ...(skills.length === 0
        ? {
            note:
              nodes.length === 1
                ? "容器没沿摆放链摆出任何元件（出手动画由别的元件摆，或子弹参数写在代码里）"
                : boundCount === 0
                  ? `容器摆了 ${nodes.length - 1} 个元件，没有一个挂在攻击样状态段上（或子弹参数写在代码里）`
                  : "挂在攻击样状态段上的动画里没打出带参数的子弹实例",
          }
        : usable.length === 0
          ? { note: `候选招式都没通过有效性判定（${skills.length} 个候选），已保留等人工判定` }
          : scope === "widened"
            ? { note: "容器直接摆的动画里没有效招式，沿摆放链往里再找一层（归属需复核）" }
            : skills.length > usable.length
              ? { note: `已排除 ${skills.length - usable.length} 个废弃动画或非攻击状态` }
              : {}),
    };
  }
  return {
    spritename: input.spritename,
    skills: [],
    note:
      candidates.length > 0
        ? "定位不到容器元件"
        : describeMissingSource(input.spritename, input.unresolvedSources ?? []),
  };
}

/** 注册表没给出可取源时的说明：有 <conflict>/<duplicate> 记录就是"没定源"，不是"查不到"。 */
function describeMissingSource(spritename: string, unresolved: UnresolvedAssetSource[]): string {
  if (unresolved.length === 0) return `asset_source_map 里没有 ${spritename} 的任何记录`;
  const kinds = [...new Set(unresolved.map((source) => source.kind))].join("/");
  const where = unresolved
    .map((source) => `${source.swf}${source.symbol === undefined ? "" : `（${source.symbol}）`}${source.orphan ? "，孤儿" : ""}`)
    .join(" 与 ");
  return `注册表只把它记在 <${kinds}>：${where} 都有源，但扫描器不替人选源（要人工定源，或在 data/monster-census.json 的 attackSourceOverrides 里指定）`;
}

/** 一只怪的观测汇总：三个系数的原始观测值都在这里。 */
export interface AttackSummary {
  /** 有效招式平均段数 → 段数系数（按当前近战颗数口径折过）。 */
  segments?: number;
  /**
   * 三种颗数取法的段数均值并排给：不过滤（旧口径）/ 简单法 / 几何法。
   * 只在有近战类子弹的行里出现，人工据此定 mode；没近战子弹的行不写这三项。
   */
  segmentsUnfiltered?: number;
  segmentsCap?: number;
  segmentsHitbox?: number;
  /** 有效招式平均倍率 → 攻击倍率。 */
  multiplier?: number;
  /** 前摇均值（帧）：有效招式 前摇 的算术平均，攻速系数按「前摇 + 后摇×换算倍率」取档。 */
  windupMean?: number;
  /** 后摇均值（帧）：末子弹帧到招式结束帧，攻速取档按换算倍率折进去。 */
  tailMean?: number;
  /** 有效招式里靠 动画完毕 调用认出结束帧的招数；剩下的退回段尾。 */
  overCallSkills: number;
  /** 单次攻击总时长中位数（帧），仅供人工复核长持续招式；攻速取档不吃这个值。 */
  tempoMedian?: number;
  /** 进平均值的招式数。 */
  skills: number;
  /** 候选招式数（含被判定为废弃/非攻击的）。 */
  candidates: number;
  fixedValueSkills: number;
  /** 霸体系数 的元件观测原始值（击飞证据 + 击退时长账）；没定位到容器时不出现。 */
  armor?: MonsterArmorMeasure;
}

/** 有效招式的平均段数、平均倍率与前摇/节奏中位数；这就是三个系数的实测值来源。 */
export function summarizeAttack(measure: MonsterAttackMeasure): AttackSummary {
  const armorPart = measure.armor === undefined ? {} : { armor: measure.armor };
  const pool = measure.skills.filter((skill) => skill.usable);
  if (pool.length === 0) return { skills: 0, candidates: measure.skills.length, overCallSkills: 0, fixedValueSkills: 0, ...armorPart };
  const median = (values: number[]) => {
    const sorted = [...values].sort((a, b) => a - b);
    return sorted[Math.floor(sorted.length / 2)] ?? Number.NaN;
  };
  const mean = (values: number[]) => values.reduce((sum, value) => sum + value, 0) / values.length;
  const multipliers = pool.map((skill) => skill.multiplier).filter((value): value is number => value !== undefined);
  // 三种取法逐招对照：这一招没有近战类子弹时它本来就不折，取当前段的值即可
  const audited = pool.some((skill) => skill.melee !== undefined);
  const variant = (key: "segmentsUnfiltered" | "segmentsCap" | "segmentsHitbox") =>
    mean(pool.map((skill) => skill.melee?.[key] ?? skill.segments));
  return {
    segments: mean(pool.map((skill) => skill.segments)),
    ...(audited
      ? { segmentsUnfiltered: variant("segmentsUnfiltered"), segmentsCap: variant("segmentsCap"), segmentsHitbox: variant("segmentsHitbox") }
      : {}),
    ...(multipliers.length > 0 ? { multiplier: mean(multipliers) } : {}),
    windupMean: mean(pool.map((skill) => skill.windupFrames)),
    tailMean: mean(pool.map((skill) => skill.tailFrames)),
    overCallSkills: pool.filter((skill) => skill.tailBasis === "动画完毕").length,
    tempoMedian: median(pool.map((skill) => skill.tempoFrames)),
    skills: pool.length,
    candidates: measure.skills.length,
    fixedValueSkills: pool.filter((skill) => skill.concerns.some((concern) => concern.startsWith("倍率来自固定值"))).length,
    ...armorPart,
  };
}

/** 前摇帧数 → 攻速档位；门槛由 data/monster-census.json 给出，人工可改配置而不改代码。 */
export interface AttackTempoBand {
  /**
   * 前摇上限（帧，不含等于）：均值小于该帧数才取这一档，按上限升序取第一个命中的档。
   * 引入后摇时门槛按 (1 + 后摇换算倍率) 放宽，比较对象是「前摇 + 后摇×倍率」，这里的常量值不动。
   */
  maxWindupFrames: number;
  factor: number;
  /** 档位说明，对应工作簿 D12 的 极慢~极快。 */
  label: string;
}

export interface AttackFlagProposal {
  /** 观测折算出的标识值（攻速系数/攻击倍率/段数系数），没有证据的项不写。 */
  flags: Record<string, number>;
  /** 取档过程与超出工作簿建议区间的报警。 */
  notes: string[];
}

const D13_MULTIPLIER_MAX = 3;
const D13_SEGMENT_MAX = 10;

/**
 * 观测值 → 标识取值：段数与倍率按 0.5 网格归档（与现网已标注行同一词表），
 * 攻速以前摇为主：有效前摇 = 前摇均值 + 后摇均值 × tailFactor，档位门槛同步放宽 (1 + tailFactor) 倍
 * （制作组 2026-10-04 口径：后摇很长的怪适当算慢一档，但不改档位常量本身的值）。
 * 段数量子弹跨度（首末子弹帧）按窗口折成的次数均摊，次数允许小数。
 * 这里只做"观测→填表"的换算，因此不存在反推；唯一一处读面板是 韧性系数 给 霸体系数 带小数位
 * （Excel H34：高于 20 时每 20 点加 0.1、上限 0.5），那是定义换算不是拟合。
 */
export function proposeAttackFlags(
  summary: AttackSummary,
  bands: AttackTempoBand[],
  tailFactor: number,
  tenacity?: number,
): AttackFlagProposal {
  const flags: Record<string, number> = {};
  const notes: string[] = [];
  const armorFactor = summary.armor?.factor;
  if (summary.skills === 0 && armorFactor === undefined) return { flags, notes: ["没有可用招式，不给候选值"] };
  if (summary.skills === 0) notes.push("没有可用招式，攻速/倍率/段数 不给候选值");

  if (summary.windupMean !== undefined) {
    const tail = summary.tailMean ?? 0;
    const effective = summary.windupMean + tail * tailFactor;
    const sorted = [...bands].sort((a, b) => a.maxWindupFrames - b.maxWindupFrames);
    const picked = sorted.find((band) => effective < band.maxWindupFrames * (1 + tailFactor)) ?? sorted.at(-1);
    if (picked !== undefined) {
      Object.assign(flags, { 攻速系数: picked.factor });
      notes.push(
        tailFactor === 0
          ? `前摇均值 ${round2(summary.windupMean)} 帧 → 攻速 ${picked.factor}（${picked.label}）`
          : `前摇 ${round2(summary.windupMean)} 帧 + 后摇 ${round2(tail)} 帧×${tailFactor} = ${round2(effective)} 帧，`
            + `对放宽 ${(1 + tailFactor).toFixed(2)} 倍的档位门槛 → 攻速 ${picked.factor}（${picked.label}）`,
      );
      if (tailFactor > 0 && summary.overCallSkills < summary.skills) {
        notes.push(`${summary.skills - summary.overCallSkills} 招没找到 动画完毕 调用，后摇退回段尾折算`);
      }
    }
  }
  if (summary.multiplier !== undefined) {
    const value = snapMonsterCoefficient(summary.multiplier).value;
    Object.assign(flags, { 攻击倍率: value });
    if (summary.multiplier > D13_MULTIPLIER_MAX) notes.push(`倍率 ${round2(summary.multiplier)} 超出 D13 常用上限 ${D13_MULTIPLIER_MAX}`);
  }
  if (summary.segments !== undefined) {
    const value = snapMonsterCoefficient(summary.segments).value;
    Object.assign(flags, { 段数系数: value });
    if (summary.segments > D13_SEGMENT_MAX) notes.push(`段数 ${round2(summary.segments)} 超出 D13 建议上限 ${D13_SEGMENT_MAX}`);
  }
  if (summary.fixedValueSkills > 0) notes.push(`${summary.fixedValueSkills} 招固定值伤害按面板均值折算`);
  if (armorFactor !== undefined && summary.armor !== undefined) {
    const decimal = tenacity === undefined ? 0 : superArmorDecimalFromTenacity(tenacity);
    const value = Math.round((armorFactor + decimal) * 10) / 10;
    Object.assign(flags, { 霸体系数: value });
    notes.push(armorAccount(summary.armor, tenacity, decimal));
  }
  return { flags, notes };
}

/** 霸体档位的取档账：可击飞与否怎么来的、击退时长哪几发、按哪个读法归的类、韧性带出的小数位。 */
export function armorAccount(armor: MonsterArmorMeasure, tenacity?: number, decimal = 0): string {
  const parts: string[] = [];
  parts.push(
    armor.airborne === true
      ? `击倒/倒地 各有击飞逻辑（${armor.evidences.length} 处证据）`
      : "击倒/倒地 没凑齐击飞逻辑（不可击飞）",
  );
  if (armor.knockbackSpans.length > 0) {
    parts.push(
      `击退时长 ${armor.knockbackSpans.map((span) => `${span.label}=${span.frames}${span.basis === "段尾" ? "†" : ""}`).join("、")}`
        + ` → ${armor.knockback}击退`,
    );
  } else {
    parts.push("被击 读不出击退时长 → 不可击退");
  }
  parts.push(
    decimal === 0
      ? `取 ${armor.factor}（${armor.band}）`
      : `取 ${armor.factor}（${armor.band}）＋韧性 ${tenacity} 按 Excel H34 加 ${decimal.toFixed(1)} = ${Math.round(((armor.factor ?? 0) + decimal) * 10) / 10}`,
  );
  return `霸体：${parts.join("；")}`;
}

function round2(value: number): number {
  return Math.round(value * 100) / 100;
}

/** 解析 asset_source_map.xml：id → 可能多个来源（同一元件在不同包里有副本）。
 *  overrides 是 data/monster-census.json 里的人工定源，直接顶掉注册表给这个模板记的来源；
 *  注册表本身是 scan_linkage.py 的 DO-NOT-EDIT 生成物，又被图标/换装烘焙管线消费，不在这里改它。 */
export function loadAssetSources(repoRoot: string, overrides?: Record<string, AttackSourceOverride[]>): Map<string, AssetSource[]> {
  const text = readXml(path.join(repoRoot, "data/items/asset_source_map.xml"));
  const map = new Map<string, AssetSource[]>();
  for (const match of text.matchAll(ASSET)) {
    const attrs = cap(match, 1) ?? "";
    const id = cap(ASSET_ID.exec(attrs), 1);
    const swf = cap(ASSET_SWF.exec(attrs), 1);
    if (id === undefined || swf === undefined) continue;
    const symbol = cap(ASSET_SYMBOL.exec(attrs), 1);
    const entry: AssetSource = { swf, ...(symbol === undefined ? {} : { symbol }) };
    const bucket = map.get(id);
    if (bucket === undefined) map.set(id, [entry]);
    else bucket.push(entry);
  }
  for (const [id, sources] of Object.entries(overrides ?? {})) {
    const pinned: AssetSource[] = [];
    for (const source of sources) {
      pinned.push(source.symbolName === undefined ? { swf: source.swf } : { swf: source.swf, symbol: source.symbolName });
    }
    if (pinned.length > 0) map.set(id, pinned);
  }
  return map;
}

/** 读注册表里 <conflict>/<duplicate> 两块：这些模板有素材但扫描器没替人选源。 */
export function loadUnresolvedAssetSources(repoRoot: string): Map<string, UnresolvedAssetSource[]> {
  const text = readXml(path.join(repoRoot, "data/items/asset_source_map.xml"));
  const map = new Map<string, UnresolvedAssetSource[]>();
  for (const match of text.matchAll(UNRESOLVED_BLOCK)) {
    const kind = match[1] as "conflict" | "duplicate";
    const id = match[2];
    const body = match[3] ?? "";
    if (id === undefined) continue;
    const sources: UnresolvedAssetSource[] = [];
    for (const source of body.matchAll(SOURCE_TAG)) {
      const attrs = cap(source, 1) ?? "";
      const swf = cap(ASSET_SWF.exec(attrs), 1);
      if (swf === undefined) continue;
      const symbol = cap(ASSET_SYMBOL.exec(attrs), 1);
      sources.push({
        swf,
        ...(symbol === undefined ? {} : { symbol }),
        kind,
        orphan: /orphan="true"/.test(attrs),
      });
    }
    if (sources.length > 0) map.set(id, sources);
  }
  return map;
}
