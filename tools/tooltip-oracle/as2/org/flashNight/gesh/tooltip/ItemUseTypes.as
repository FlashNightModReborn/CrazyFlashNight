/**
 * ItemUseTypes - 物品使用类型常量
 *
 * 职责：
 * - 定义所有物品的 use 字段常量
 * - 避免硬编码字符串在代码中散布
 * - 提供类型安全的引用
 *
 * 设计原则：
 * - 所有常量使用 public static（AS2 中无 final 关键字）
 * - 常量名使用大写下划线命名法
 * - 常量值与游戏数据中的实际字符串保持一致
 *
 * 使用示例：
 * ```actionscript
 * switch (item.use) {
 *     case ItemUseTypes.MELEE:
 *         // 处理近战武器
 *         break;
 *     case ItemUseTypes.PISTOL:
 *         // 处理手枪
 *         break;
 * }
 * ```
 */
class org.flashNight.gesh.tooltip.ItemUseTypes {

  // ══════════════════════════════════════════════════════════════
  // 武器类型
  // ══════════════════════════════════════════════════════════════

  /**
   * 近战武器（刀类）
   */
  public static var MELEE:String = "刀";

  /**
   * 手枪类武器
   */
  public static var PISTOL:String = "手枪";

  /**
   * 长枪类武器
   */
  public static var RIFLE:String = "长枪";

  /**
   * 投掷武器（手雷）
   */
  public static var GRENADE:String = "手雷";

  // ══════════════════════════════════════════════════════════════
  // 防具类型
  // ══════════════════════════════════════════════════════════════

  /**
   * 防具/护甲
   */
  public static var ARMOR:String = "防具";

  // ══════════════════════════════════════════════════════════════
  // 消耗品类型
  // ══════════════════════════════════════════════════════════════

  /**
   * 药剂/药水
   */
  public static var POTION:String = "药剂";

  // ══════════════════════════════════════════════════════════════
  // 其他类型
  // ══════════════════════════════════════════════════════════════

  /**
   * 技能
   */
  public static var SKILL:String = "技能";

  /**
   * 材料
   */
  public static var MATERIAL:String = "材料";

  /**
   * 情报
   */
  public static var INFORMATION:String = "情报";

  // ══════════════════════════════════════════════════════════════
  // 物品类型（item.type）
  // ══════════════════════════════════════════════════════════════

  /**
   * 武器类型（用于布局判断）
   */
  public static var TYPE_WEAPON:String = "武器";

  /**
   * 防具类型（用于布局判断）
   */
  public static var TYPE_ARMOR:String = "防具";

  /**
   * 技能类型（用于布局判断）
   */
  public static var TYPE_SKILL:String = "技能";

  /**
   * 消耗品类型（用于布局判断）
   */
  public static var TYPE_CONSUMABLE:String = "消耗品";

  // ══════════════════════════════════════════════════════════════
  // 工具方法
  // ══════════════════════════════════════════════════════════════

  /**
   * 判断是否为枪械类型（手枪或长枪）
   *
   * @param useType:String 物品的 use 字段值
   * @return Boolean 是否为枪械
   */
  public static function isGun(useType:String):Boolean {
    return useType == PISTOL || useType == RIFLE;
  }

  /**
   * 判断是否为武器类型
   *
   * @param useType:String 物品的 use 字段值
   * @return Boolean 是否为武器
   */
  public static function isWeapon(useType:String):Boolean {
    return useType == MELEE || useType == PISTOL || useType == RIFLE || useType == GRENADE;
  }
}