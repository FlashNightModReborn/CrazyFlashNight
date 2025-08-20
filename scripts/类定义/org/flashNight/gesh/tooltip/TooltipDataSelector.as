class org.flashNight.gesh.tooltip.TooltipDataSelector {
  public static function getEquipmentData(item:Object, tier:String):Object {
    if (tier == null) return item.data;
    switch (tier) {
      case "二阶": return item.data_2;
      case "三阶": return item.data_3;
      case "四阶": return item.data_4;
      case "墨冰": return item.data_ice;
      case "狱火": return item.data_fire;
      default: return item.data;
    }
  }
} 