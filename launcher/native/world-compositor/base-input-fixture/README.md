# B1 冷启动依赖实验（未具备输入准入）

此目录只用于验证启动前存档拒绝与真实场景/演员 RSL 装配；不是 B1 可玩候选。当前没有安装真实 `_root.初始化玩家模板`，不会声明 actorReady 或授予输入。结果及后续边界见 [施工检查点](../../../../docs/reports/统一输入-B1共享底座与冷装配检查点-2026-09-24.md)。

BaseBootstrap 必须无 imports/library，先验证 SharedObject.getLocal 拒绝函数 identity，再加载 BaseWorld。拒绝函数从未调用原生 getter。BaseWorld 实际加载医务室及主角-男；服务缺失不得用空实现冒称真实演员已就绪。RSL URL 目前绑定本机资源绝对路径，不能直接作为可分发闭包；已有发布SWF未改。

独立 CS6 目标分别为 bootstrap/BaseBootstrap.xfl 与 base/BaseWorld.xfl，publish-only 对应 ../BaseBootstrap.swf 与 ../BaseWorld.swf。仅本机诊断启动脚本与结果在 tmp/b1-unified-base，输入始终关闭。
