// 选关系统_WebView.as — WebView 选关面板正式入口命令
// 当前版本：正式入口打开 stage-select 面板；普通关卡结束按 _root.关卡地图帧值 返回并停留在 Flash，玩家再次显式进入选关入口时才打开 Web；旧 Flash 关卡地图仅作通信失败 fallback。
StageSelectPanelService.install();
