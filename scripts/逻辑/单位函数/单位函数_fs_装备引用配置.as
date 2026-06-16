
// _root.装备引用配置 接口（FLA 肢体素材通过此接口调用，无法迁移）
// 实现已下沉到 org.flashNight.arki.unit.UnitComponent.Dressup.DressupReferenceManager
// 时序与事件契约：agentsDoc/as2-load-timing.md
_root.装备引用配置 = {};

// 函数桥接（与 单位函数_lsy_主角射击函数.as 同款写法）
_root.装备引用配置.配置装扮     = DressupReferenceManager.attach;
_root.装备引用配置.刷新所有装扮 = DressupReferenceManager.refreshAll;
