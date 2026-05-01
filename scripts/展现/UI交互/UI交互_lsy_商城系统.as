// 商城存盘函数已折入 SaveManager
// shim 层在 通信_lsy_原版存档系统.as 中委托到 SaveManager
// 此处不再重复定义，避免覆盖 shim 委托
//
// 2026-05: 旧 Flash 商城 UI（shopMainMC）已退役，运行时商城入口统一为
// Launcher SHOP -> WebView Panel(kshop) -> 商城系统_WebView.as。
//
// 本文件不再被 asLoader include；保留为迁移说明，避免旧 root API
// 重新挂载造成全局层索引开销。商城持久数据仍由 SaveManager 维护：
//   _root.商城购物车
//   _root.商城已购买物品
