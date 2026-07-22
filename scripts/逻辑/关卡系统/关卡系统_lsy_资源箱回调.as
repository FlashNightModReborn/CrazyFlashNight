

// 资源箱根回调的唯一源码；所有网格箱只允许进入 Web loot authority。

_root.地图元件.资源箱开启脚本 = function(target:MovieClip) {
    target._visible = true;

    // 任一既有 authority / suspend / recovery fence 都必须拦截当前回调。
    // guard 命中后只停住并等待 Web-only 服务收敛，绝不渲染 Flash 资源箱 UI。
    var lootGuard:Object = org.flashNight.arki.item.LootContainerService.guardOpenGrid(target);
    if (lootGuard.handled) {
        trace("[LootContainer] open callback guarded: " + lootGuard.reason);
        return;
    }

    // 与 InteractionHandler 共用唯一 shape 分类，不能在结束帧用 Number() 宽松转换
    // 重开一条字符串/小数/超界尺寸旁路。正常交互已在 kill 前为 supported Web grid
    // 建立 reservation；结束帧只负责激活同一 authority 并请求 Web。
    var lootShape:String = org.flashNight.arki.item.LootContainerService.classifyMapChestShape(target);
    if (lootShape == "supported_web_grid") {
        var activated:Object = org.flashNight.arki.item.LootContainerService.activateReservedOpen(target);
        if (activated.success) {
            if (activated.duplicate !== true
                    && !org.flashNight.arki.item.LootContainerService.requestOpenPanel()) {
                trace("[LootContainer] Web panel request rejected; authority retained");
            }
        } else {
            trace("[LootContainer] reserved activation rejected: " + activated.error);
        }
        return;
    }

    // 已准入箱体中，只有两维完整的非正整数保留地面直投。malformed/超界尺寸与
    // 意外调用本回调的非箱对象均 fail closed，不能借旧 AS2 路径掩盖配置错误。
    if (lootShape != "direct_delivery") {
        trace("[LootContainer] open callback rejected shape: " + lootShape);
        return;
    }

    // 非正网格箱从来不创建物品栏 UI，保持直接地面掉落。
    target.掉落物判定 = _root.敌人函数.掉落物判定;
    target.掉落物品 = _root.敌人函数.掉落物品;
    target.掉落物判定();
}

_root.地图元件.资源箱破碎脚本 = function(target:MovieClip) {
    target._visible = true;

    var lootGuard:Object = org.flashNight.arki.item.LootContainerService.guardBreakGrid(target);
    if (lootGuard.handled) {
        trace("[LootContainer] break callback guarded: " + lootGuard.reason);
        return;
    }

    // Web-only 迁移只替换“正常交互 → 结束时间轴 → 网格 UI”路径。破碎时间轴没有
    // InteractionHandler reservation，继续保持既有直接爆落语义；上面的 guard 会先
    // 截住同一箱已经 reservation、物化、激活、挂起或待收敛的 Web authority，避免重复发奖。
    target.掉落物判定 = _root.敌人函数.掉落物判定;
    target.掉落物品 = _root.敌人函数.掉落物品;
    target.掉落物判定();
}
