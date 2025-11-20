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
        trace("✓ 预期总数 = 70 个配件");

        if (data.mod.length == 70) {
            trace("✓ 配件数量验证通过！");
        } else {
            trace("✗ 警告：配件数量不符！实际 " + data.mod.length + " 个，预期 70 个");
        }

        // 打印前5个和后5个配件的名称
        if (data.mod && data.mod.length > 0) {
            trace("✓ 前5个配件：");
            for (var i:Number = 0; i < Math.min(5, data.mod.length); i++) {
                trace("  - " + data.mod[i].name);
            }
            trace("✓ 后5个配件：");
            var startIdx:Number = Math.max(0, data.mod.length - 5);
            for (var j:Number = startIdx; j < data.mod.length; j++) {
                trace("  - " + data.mod[j].name);
            }
        }

        trace("======================================");
        trace("EquipModListLoader 拆分测试完成！");
        trace("======================================");

        // 传递给 EquipmentUtil 进行初始化
        org.flashNight.arki.item.EquipmentUtil.loadModData(data.mod);
    },
    function():Void {
        trace("✗ 测试失败：装备配件数据加载失败！");
        trace("======================================");
    }
);
