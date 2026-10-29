# CF6 原生背景卸载回归

入口：`powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-cf6-native-background-tests.ps1 -TimeoutSeconds 480`。

此入口先在真实 CS6 TestLoader 中加载实际 `CF6_A01_BG.swf`，调用生产帧脚本的 `贴背景图`、`Cf6MapPresentation` 和 `SceneManager`，核对真实 `BitmapData.draw` 与跨帧 `unloadMovie` 后的房间续接。6项断言覆盖背景准备、一次绘制、世界和矩阵凭据、演员倍率、可见像素，以及A01炮塔服务调用一次。炮塔服务只记录调用，不能将本套件称为炮塔资源或实战验收。

随后串联 `Cf6MapMechanismTest` 的238项回归，包含等待卸载时的提前清场、重入、超时、身份变化和拆除。两套件都必须有本轮完整摘要、0失败和唯一完成标记；只编译成功不等于通过。测试不调用存档、库存、奖励或Host业务命令。

房间夹具只覆盖A01背景边界。R7教程、A02天空/视差及实际关卡切换使用隔离游戏旅程验证；不能用简化夹具省略的图层代替真实地图配置。复现与修复记录见[61路线教程与R7接入记录](../../../docs/闪客快打6肉鸽-61路线教程修复与R7地图接入-2026-10-27.md)。
