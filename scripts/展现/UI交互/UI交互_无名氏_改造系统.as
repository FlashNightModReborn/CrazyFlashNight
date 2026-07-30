_root.改装系统 = new Object();
org.flashNight.arki.item.CraftingPanelService.install();

/**
 * 旧地图元件继续调用同一入口，但渲染与写入只允许进入 Web 合成工作台。
 * Launcher/协议未就绪时明确失败，不再装载 Flash 合成面板。
 */
_root.改装系统.加载改装清单 = function(清单):Boolean {
    if (org.flashNight.arki.item.CraftingPanelService.openPanel(String(清单), "world_crafting_entry")) {
        return true;
    }
    if (typeof _root.发布消息 == "function") {
        _root.发布消息("合成面板暂时不可用");
    }
    return false;
};
