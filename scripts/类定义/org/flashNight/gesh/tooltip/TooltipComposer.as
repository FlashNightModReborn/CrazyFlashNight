﻿// 文件：scripts/类定义/org/flashNight/gesh/tooltip/TooltipComposer.as
// 说明：将 _root.注释组合 的"文本段拼装逻辑"抽象为可复用的静态类。
// 依赖：TooltipTextBuilder 中的一系列构建函数（需返回 Array<string> 或 null）。
// 
// ──────────────────────────────────────────────────────────────────────────────
// 使用指引：
//  1) 确保类路径（Publish Settings → ActionScript 2.0 Settings → Classpath）包含
//     "scripts/类定义/"的上层目录；文件路径与包名严格一致（区分大小写）。 
//  2) TooltipTextBuilder 的各构建函数应遵循：
//        - 输入：对象/原始值（允许为 null/undefined，函数内部自行兜底或返回 null）
//        - 输出：Array<string>（可为空数组）；如无内容请返回 null 或 []。
//     本类会对返回值做 null 判空处理，避免无意义段落与中间数组。
//  3) 性能注意：本类使用 append(…) 逐个 push，避免多次 concat 产生的临时数组。
//  4) 线程/状态：全静态、无内部可变状态；可并发/重入安全（AS2 单线程环境）。 
//  5) 迁移建议：旧的 _root.注释组合.* 可直接以本类静态方法替换；如需过渡期兼容可在入口脚本
//     放置一个映射对象，将旧调用转发到本类（见以往提供的"兼容包装"示例）。
//
// 常见问题（FAQ）：
//  Q1：TooltipTextBuilder 某个函数抛错导致拼装中断？
//   A：请确保该函数对可空输入做好判断，并在"无内容"时返回 null/[]；本类会自动忽略 null。
//  Q2：value.tier / level 缺失？
//   A：本类不做默认值推断。请于调用前保证必要字段齐备；或在 TooltipTextBuilder 内部兜底。
//  Q3：拼接结果出现"null""undefined"字样？
//   A：通常是某构建函数直接把原始对象拼入字符串导致；请确保仅返回字符串片段。
// ──────────────────────────────────────────────────────────────────────────────

import org.flashNight.arki.item.BaseItem;
import org.flashNight.gesh.tooltip.*;
import org.flashNight.gesh.string.StringUtils;

/**
 * # TooltipComposer
 * 
 * 用于**组合物品注释的各类文本片段**（简介头、装备属性、基础描述等），并输出完整 HTML 字符串。
 * 
 * 设计目标：
 * - **零实例**：提供纯静态方法，避免在 AS2 环境下的无谓对象创建；
 * - **高健壮性**：对各子段返回值进行 `null` 过滤，防止空段插入；
 * - **易维护**：职责单一，仅负责"拼装"；具体内容由 `TooltipTextBuilder` 提供；
 * - **低开销**：内部使用 `append` 逐个 `push`，避免 `concat` 带来的中间数组。
 *
 * 依赖协定（Contract）：
 * - `TooltipTextBuilder.*` 需返回 `Array`（元素为 `String`）或 `null`。
 * - 当输入不满足生成条件，应返回 `null` 或空数组，而非抛错或返回非字符串元素。
 *
 * 示例（生成完整注释）：
 * ```actionscript
 * var html:String = org.flashNight.gesh.tooltip.TooltipComposer.generateItemFullText(item, value, level);
 * _root.注释框.文本框.htmlText = html;
 * ```
 */
class org.flashNight.gesh.tooltip.TooltipComposer {

  // ──────────────── 基础段拼装 ────────────────

  /**
   * 组合"基础信息"段落集合：
   * - 物品基础描述
   * - 剧情/情报提示
   * - 合成材料
   * - 刀技乘数
   * - 战技信息
   * - 生命周期
   *
   * @param item:Object 物品数据对象
   * @return String 拼装后的 HTML 字符串
   */
  public static function generateItemDescriptionText(item:Object):String {
    var buffer:Array = [];
    
    append(buffer, TooltipTextBuilder.buildBasicDescription(item));
    append(buffer, TooltipTextBuilder.buildStoryTip(item));
    append(buffer, TooltipTextBuilder.buildSynthesisMaterials(item));
    append(buffer, TooltipTextBuilder.buildBladeSkillMultipliers(item));
    append(buffer, TooltipTextBuilder.buildSkillInfo(item.skill));
    append(buffer, TooltipTextBuilder.buildLifecycleInfo(item.lifecyle));
    
    return buffer.join("");
  }

  // ──────────────── 简介面板拼装 ────────────────

  /**
   * 组合"简介面板"内容：
   * - 简介标题头（物品名、类型、价格等）
   * - 装备属性块
   *
   * @param item:Object 物品数据对象
   * @param value:Object 数值对象（包含 tier、level 等）
   * @param upgradeLevel:Number 强化等级（默认从 value.level 获取，最小值 1）
   * @return String 拼装后的 HTML 字符串
   */
  public static function generateIntroPanelContent(baseItem:BaseItem, item:Object):String {
    var buffer:Array = [];
    
    append(buffer, TooltipTextBuilder.buildIntroHeader(baseItem, item));
    append(buffer, TooltipTextBuilder.buildStats(baseItem, item));
    
    return buffer.join("");
  }

  // ──────────────── 完整组合 ────────────────

  /**
   * 生成物品完整注释文本：
   * - 基础段（含生命周期、合成材料、技能信息等）
   * - 简介段（含标题头、装备属性）
   * 
   * @param item:Object 物品数据对象
   * @param value:Object 数值对象（包含 tier、level 等）
   * @param upgradeLevel:Number 强化等级（默认从 value.level 获取，最小值 1）
   * @return String 完整的 HTML 文本
   */
  public static function generateItemFullText(item:Object, value:Object, upgradeLevel:Number):String {
    if (upgradeLevel == undefined || isNaN(upgradeLevel) || upgradeLevel < 1) {
      upgradeLevel = (value && value.level > 0) ? value.level : 1;
    }

    var descriptionText:String = generateItemDescriptionText(item);
    var introText:String 
    // var introText:String = generateIntroPanelContent(item, value, upgradeLevel);
    
    return descriptionText + introText; 
  }

  // ──────────────── 私有辅助方法 ────────────────

  /**
   * 高效数组拼接：
   * 将 source 数组的所有元素逐个推入 destination（就地修改）
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

  // ──────────────── 图标渲染控制 ────────────────

  /**
   * 渲染物品图标注释：
   * - 获取物品数据
   * - 处理布局
   * - 拼接文本内容
   * - 调用渲染方法
   * 
   * @param enable:Boolean 是否启用显示
   * @param name:String 物品名称
   * @param value:Object 物品数值对象
   * @param introString:String 预先拼好的简介面板文本（简介头 + 装备段）
   * @param extraString:String 额外显示的文本（可选；用于把短描述并入简介面板）
   */
  public static function renderItemIcon(enable:Boolean, name:String, value:Object, introString:String, extraString:String):Void {
    if (enable) {
      var data:Object = org.flashNight.arki.item.ItemUtil.getItemData(name);
      
      // 交给布局模块决定尺寸与偏移
      var target:MovieClip = TooltipBridge.getIconTarget();
      var background:MovieClip = TooltipBridge.getIntroBackground();
      var text:MovieClip = TooltipBridge.getIntroTextBox();
      var layout:Object = TooltipLayout.applyIntroLayout(data.type, target, background, text);
      var stringWidth:Number = layout.width;

      // 使用传入的简介文本；如有 extraString（短描述），并入简介面板
      var introduction:String = introString ? introString : "";
      if (extraString) {
        introduction += "<BR>" + extraString;
      }

      // 调用通用图标核心函数
      TooltipLayout.renderIconTooltip(true, data.icon, introduction, stringWidth, data.type);
      
      // 立刻把整体容器根据"简介背景"的实际边界回弹到屏幕可视区
      TooltipBridge.clampContainerByBg(background, 8);
    } else {
      TooltipLayout.renderIconTooltip(false);
    }
  }

  /**
   * 智能显示物品注释（自适应长短内容优化）：
   * - 根据内容长度智能选择显示策略
   * - 长内容：分离显示（主框体+图标面板）
   * - 短内容：合并显示（仅图标面板）
   * 
   * @param name:String 物品名称
   * @param value:Object 物品数值对象
   * @param descriptionText:String 主要描述内容
   * @param introText:String 简介面板内容
   * @param options:Object 可选配置参数 { totalMultiplier:Number, descDivisor:Number }
   */
  public static function renderItemTooltipSmart(name:String, value:Object, descriptionText:String, introText:String, options:Object):Void {
    // 获取配置参数（支持自定义，有默认值）
    var totalMultiplier:Number = (options && options.totalMultiplier) ? options.totalMultiplier : TooltipConstants.SMART_TOTAL_MULTIPLIER;
    var descDivisor:Number = (options && options.descDivisor) ? options.descDivisor : TooltipConstants.SMART_DESC_DIVISOR;
    
    // 智能长度判断（使用 htmlLengthScore 更准确评估）
    var threshold:Number = TooltipConstants.SPLIT_THRESHOLD;
    var descLength:Number = StringUtils.htmlLengthScore(descriptionText, null);
    var totalLength:Number = descLength + StringUtils.htmlLengthScore(introText, null);

    // 保底清理
    TooltipLayout.hideTooltip();

    if (totalLength > threshold * totalMultiplier && descLength > threshold / descDivisor) {
      // 长内容策略：分离显示
      var calculatedWidth:Number = TooltipLayout.estimateWidth(descriptionText);
      TooltipLayout.showTooltip(calculatedWidth, descriptionText);
      renderItemIcon(true, name, value, introText, null);
    } else {
      // 短内容策略：合并显示
      renderItemIcon(true, name, value, introText, descriptionText);
      
      // 隐藏主框体
      TooltipBridge.setTextContent("main", "");
      TooltipBridge.setVisibility("main", false);
      TooltipBridge.setVisibility("mainBg", false);
    }
  }
}