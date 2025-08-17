// 文件：scripts/类定义/org/flashNight/gesh/string/TooltipComposer.as
// 说明：将 _root.注释组合 的“文本段拼装逻辑”抽象为可复用的静态类。
// 依赖：TooltipTextBuilder 中的一系列构建函数（需返回 Array<string> 或 null）。
//
// ──────────────────────────────────────────────────────────────────────────────
// 使用指引：
//  1) 确保类路径（Publish Settings → ActionScript 2.0 Settings → Classpath）包含
//     “scripts/类定义/”的上层目录；文件路径与包名严格一致（区分大小写）。 
//  2) TooltipTextBuilder 的各构建函数应遵循：
//        - 输入：对象/原始值（允许为 null/undefined，函数内部自行兜底或返回 null）
//        - 输出：Array<string>（可为空数组）；如无内容请返回 null 或 []。
//     本类会对返回值做 null 判空处理，避免无意义段落与中间数组。
//  3) 性能注意：本类使用 append(…) 逐个 push，避免多次 concat 产生的临时数组。
//  4) 线程/状态：全静态、无内部可变状态；可并发/重入安全（AS2 单线程环境）。 
//  5) 迁移建议：旧的 _root.注释组合.* 可直接以本类静态方法替换；如需过渡期兼容可在入口脚本
//     放置一个映射对象，将旧调用转发到本类（见以往提供的“兼容包装”示例）。
//
// 常见问题（FAQ）：
//  Q1：TooltipTextBuilder 某个函数抛错导致拼装中断？
//   A：请确保该函数对可空输入做好判断，并在“无内容”时返回 null/[]；本类会自动忽略 null。
//  Q2：value.tier / level 缺失？
//   A：本类不做默认值推断。请于调用前保证必要字段齐备；或在 TooltipTextBuilder 内部兜底。
//  Q3：拼接结果出现“null”“undefined”字样？
//   A：通常是某构建函数直接把原始对象拼入字符串导致；请确保仅返回字符串片段。
// ──────────────────────────────────────────────────────────────────────────────

import org.flashNight.gesh.string.*;

/**
 * # TooltipComposer
 * 
 * 用于**组合物品注释的各类文本片段**（简介头、装备属性、基础描述等），并输出完整 HTML 字符串。
 * 
 * 设计目标：
 * - **零实例**：提供纯静态方法，避免在 AS2 环境下的无谓对象创建；
 * - **高健壮性**：对各子段返回值进行 `null` 过滤，防止空段插入；
 * - **易维护**：职责单一，仅负责“拼装”；具体内容由 `TooltipTextBuilder` 提供；
 * - **低开销**：内部使用 `append` 逐个 `push`，避免 `concat` 带来的中间数组。
 *
 * 依赖协定（Contract）：
 * - `TooltipTextBuilder.*` 需返回 `Array`（元素为 `String`）或 `null`。
 * - 当输入不满足生成条件，应返回 `null` 或空数组，而非抛错或返回非字符串元素。
 *
 * 示例（生成完整注释）：
 * ```actionscript
 * var html:String = org.flashNight.gesh.string.TooltipComposer.generateItemFullText(item, value, level);
 * _root.注释框.文本框.htmlText = html;
 * ```
 */
class org.flashNight.gesh.string.TooltipComposer {

  // ──────────────── 基础段拼装 ────────────────

  /**
   * 组合“基础信息”段落集合：
   * - 物品基础描述
   * - 剧情/情报提示
   * - 合成材料提示
   * - 刀技乘数说明
   * - 战技/技能信息（基于 `item.skill`）
   * - 生命周期信息（基于 `item.lifecycle`）
   *
   * @param  item  物品数据对象；允许缺失部分字段（子段函数应自行兜底）
   * @return Array 包含若干 **HTML 片段字符串** 的数组；若所有子段均为空，则可能返回空数组
   *
   * 健壮性：
   * - 若某子段生成函数返回 `null`，将被安全忽略；
   * - 若生成函数返回 `[]`，不会影响最终输出。
   *
   * 性能：
   * - 采用 `append` 逐项 `push`，避免 `concat` 带来的中间数组与 GC 压力。
   */
  public static function buildBasicSection(item:Object):Array {
    var segments:Array = new Array();

    // 顺序拼接各子段
    append(segments, TooltipTextBuilder.buildBasicDescription(item));
    append(segments, TooltipTextBuilder.buildStoryTip(item));
    append(segments, TooltipTextBuilder.buildSynthesisMaterials(item));
    append(segments, TooltipTextBuilder.buildBladeSkillMultipliers(item));
    append(segments, TooltipTextBuilder.buildSkillInfo(item.skill));
    append(segments, TooltipTextBuilder.buildLifecycleInfo(item.lifecycle));

    return segments;
  }

  // ──────────────── 装备段拼装 ────────────────

  /**
   * 组合“装备属性”段落集合。
   *
   * @param  item   物品数据对象
   * @param  tier   品阶/品质（字符串）；通常来自 `value.tier`
   * @param  level  等级（数值）；调用方需保证为有效数字
   * @return Array  HTML 片段数组；无内容时应由下层返回 `null`/`[]`
   *
   * 调用时机：
   * - 通常在简介头之后、基础段之前拼入。
   *
   * 约束：
   * - 不在此处推断默认品阶/等级；如需默认值，请在 `TooltipTextBuilder` 内实现。
   */
  public static function buildEquipmentSection(item:Object, tier:String, level:Number):Array {
    return TooltipTextBuilder.buildEquipmentStats(item, tier, level);
  }

  // ──────────────── 简介头拼装 ────────────────

  /**
   * 组合“简介标题头”段落集合（名称、稀有度、标签等）。
   *
   * @param  item   物品数据对象
   * @param  value  实例化数据（如强化等级、品质等）
   * @param  level  等级（数值）；通常与 `value` 一致，由调用者传入
   * @return Array  HTML 片段数组；下层可据字段缺失返回 `null`/`[]`
   *
   * 典型内容：
   * - 物品名与装饰符（稀有度颜色、前后缀等）
   * - 简要的标签/类型展示
   */
  public static function buildIntroHeader(item:Object, value:Object, level:Number):Array {
    return TooltipTextBuilder.buildIntroHeader(item, value, level);
  }

  // ──────────────── 终端输出：完整正文 ────────────────

  /**
   * 生成**完整物品注释 HTML**。
   * 拼装顺序：**简介头 → 装备段 → 基础段**。
   *
   * @param  item   物品数据对象
   * @param  value  物品实例化数据（如 tier、强化等）
   * @param  level  等级（Number）
   * @return String 完整 HTML 字符串
   *
   * 注意：
   * - 仅负责“拼接”；各子段缺失将被自动忽略（不留多余换行）。
   * - 若三个大段均为空，返回空字符串 ""。
   */
  public static function generateItemFullText(item:Object, value:Object, level:Number):String {
    var allSegments:Array = new Array();
    append(allSegments, buildIntroHeader(item, value, level));
    append(allSegments, buildEquipmentSection(item, value.tier, level));
    append(allSegments, buildBasicSection(item));
    return allSegments.join("");
  }

  // ──────────────── 终端输出：仅描述正文 ────────────────

  /**
   * 仅生成“基础段”（描述/剧情/合成/刀技/战技/生命周期）的 HTML 文本。
   * 适用于**主要注释区域**，当左侧简介面板已展示“简介头+装备段”时避免重复。
   *
   * @param  item   物品数据对象
   * @return String HTML 字符串（可能为空串）
   */
  public static function generateItemDescriptionText(item:Object):String {
    return buildBasicSection(item).join("");
  }

  // ──────────────── 终端输出：简介面板 ────────────────

  /**
   * 生成**简介面板内容**（仅包含“简介头 + 装备段”），
   * 用于左侧简介区域，避免与主注释区域的“基础段”重复。
   *
   * @param  item   物品数据对象
   * @param  value  物品实例化数据（含 tier 等）
   * @param  level  等级（Number）
   * @return String HTML 字符串（可能为空串）
   */
  public static function generateIntroPanelContent(item:Object, value:Object, level:Number):String {
    var segments:Array = new Array();
    append(segments, buildIntroHeader(item, value, level));
    append(segments, buildEquipmentSection(item, value.tier, level));
    return segments.join("");
  }

  // ──────────────── 内部工具：安全拼接 ────────────────

  /**
   * 安全地将 `source` 数组中的元素逐项 `push` 到 `destination`。
   * - 若 `source == null`，直接忽略；
   * - 不做类型检查，默认 `source[i]` 为字符串；
   * - 保持 O(n) 线性时间，且不产生中间数组。
   *
   * @param destination  目标数组（就地修改）
   * @param source       来源数组（允许为 null）
   */
  private static function append(destination:Array, source:Array):Void {
    if (source == null) return;
    var index:Number = 0;
    var length:Number = source.length;
    while (index < length) {
      destination.push(source[index]);
      index++;
    }
  }
}

