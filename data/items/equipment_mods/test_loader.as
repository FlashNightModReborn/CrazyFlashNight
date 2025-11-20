// EquipModListLoader 测试脚本
// 在游戏中的某个帧或按钮上执行此脚本来测试加载器

import org.flashNight.gesh.xml.LoadXml.EquipModListLoader;
import org.flashNight.gesh.object.ObjectUtil;

trace("======================================");
trace("开始测试 EquipModListLoader");
trace("======================================");

// 获取 EquipModListLoader 实例
var modListLoader:EquipModListLoader = EquipModListLoader.getInstance();

// 加载配件数据
modListLoader.loadModData(
    function(data:Object):Void {
        trace("✓ 测试成功：装备配件数据加载成功！");
        trace("✓ 配件总数 = " + data.mod.length);

        // 打印前3个配件的名称
        if (data.mod && data.mod.length > 0) {
            trace("✓ 前3个配件：");
            for (var i:Number = 0; i < Math.min(3, data.mod.length); i++) {
                trace("  - " + data.mod[i].name);
            }
        }

        trace("======================================");
        trace("EquipModListLoader 测试完成！");
        trace("======================================");

        // 传递给 EquipmentUtil 进行初始化
        org.flashNight.arki.item.EquipmentUtil.loadModData(data.mod);
    },
    function():Void {
        trace("✗ 测试失败：装备配件数据加载失败！");
        trace("======================================");
    }
);
