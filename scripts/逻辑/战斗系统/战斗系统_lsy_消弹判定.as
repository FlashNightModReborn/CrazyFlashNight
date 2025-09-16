import org.flashNight.arki.bullet.BulletComponent.Queue.*;

// ============================================================================
// 消除子弹（重构版，使用 BulletCancelQueueProcessor 类）
// ----------------------------------------------------------------------------
// 用法（保持向后兼容）：
//   1) var p = _root.消弹属性初始化(某个消弹区域MC);
//   2) _root.消除子弹(p);   // 本帧只入队
//   3) 每帧由 frameUpdate 事件统一批处理并清空队列
// ----------------------------------------------------------------------------
// 设计说明：
// - 核心逻辑已迁移到 BulletCancelQueueProcessor 类
// - 本文件保留原有的 _root 接口作为包装器，确保向后兼容
// - 新代码建议直接使用 BulletCancelQueueProcessor 的静态方法
// ============================================================================

// ===============================
// 初始化处理器
// ===============================
BulletCancelQueueProcessor.initialize();

// ===============================
// 公共API：包装器方法（向后兼容）
// ===============================

// 消除子弹入队接口
_root.消除子弹 = function(obj:Object):Void {
    BulletCancelQueueProcessor.enqueue(obj);
};

// 消弹属性初始化辅助方法
_root.消弹属性初始化 = function(消弹区域:MovieClip):Object {
    return BulletCancelQueueProcessor.initArea(消弹区域);
};


