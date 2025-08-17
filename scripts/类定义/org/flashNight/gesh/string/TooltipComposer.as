// 文件：scripts/类定义/org/flashNight/gesh/string/TooltipComposer.as
// 说明：将 _root.注释组合 class 化，提供等价的静态方法。
// 依赖：TooltipTextBuilder.* 返回 Array<string> 片段。


import org.flashNight.gesh.string.*;

class org.flashNight.gesh.string.TooltipComposer {

  // 禁止实例化（可选）
  public function TooltipComposer() {}

  // === 基础段：聚合描述/剧情/合成/刀技/战技/生命周期 ===
  public static function 基础段(item:Object):Array {
    var segments:Array = new Array();

    // 按顺序拼接各子段；append 做空值与 push 循环处理，避免 concat 产生中间数组
    append(segments, TooltipTextBuilder.buildBasicDescription(item));
    append(segments, TooltipTextBuilder.buildStoryTip(item));
    append(segments, TooltipTextBuilder.buildSynthesisMaterials(item));
    append(segments, TooltipTextBuilder.buildBladeSkillMultipliers(item));
    append(segments, TooltipTextBuilder.buildSkillInfo(item.skill));
    append(segments, TooltipTextBuilder.buildLifecycleInfo(item.lifecycle));

    return segments;
  }

  // === 装备段：直接调用现有的装备属性块生成 ===
  public static function 装备段(item:Object, tier:String, lvl:Number):Array {
    return TooltipTextBuilder.buildEquipmentStats(item, tier, lvl);
  }

  // === 简介头：直接调用现有的简介标题头生成 ===
  public static function 简介头(item:Object, value:Object, lvl:Number):Array {
    return TooltipTextBuilder.buildIntroHeader(item, value, lvl);
  }

  // === 生成物品全文：组合所有段落为完整 HTML ===
  public static function 生成物品全文(item:Object, value:Object, lvl:Number):String {
    var allSegments:Array = new Array();
    append(allSegments, 简介头(item, value, lvl));
    append(allSegments, 装备段(item, value.tier, lvl));
    append(allSegments, 基础段(item));
    return allSegments.join("");
  }

  // === 生成物品描述文本：仅描述部分（用于主要注释） ===
  public static function 生成物品描述文本(item:Object):String {
    return 基础段(item).join("");
  }

  // === 生成简介面板内容：只包含简介头 + 装备段（修复左侧面板语义） ===
  public static function 生成简介面板内容(item:Object, value:Object, lvl:Number):String {
    var segments:Array = new Array();
    append(segments, 简介头(item, value, lvl));
    append(segments, 装备段(item, value.tier, lvl));
    return segments.join("");
  }

  // === 小工具：把 src 里的元素逐个 push 到 dst（忽略 null/undefined） ===
  private static function append(dst:Array, src:Array):Void {
    if (src == null) return;
    var i:Number = 0;
    var n:Number = src.length;
    while (i < n) {
      dst.push(src[i]);
      i++;
    }
  }
}
