import org.flashNight.gesh.depth.*;

=== AUTOMATION TEST ===
Time: Sat Mar 21 16:15:18 GMT+0800 2026
[DepthManagerTest] 
[DepthManagerTest] ==================================================
[DepthManagerTest]  DepthManager (Twip Trick) 测试套件 v2
[DepthManagerTest] ==================================================
[DepthManagerTest] 正在设置测试环境...
[DepthManagerTest] 测试环境设置完成，创建了 50 个测试影片剪辑
[DepthManagerTest] 
[DepthManagerTest] ----- 标定测试 -----
监听器已移除：HID1
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
监听器已移除：HID2
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
监听器已移除：HID3
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
监听器已移除：HID4
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
监听器已移除：HID5
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[DepthManagerTest] √ 测试通过: 5组真实场景标定
监听器已移除：HID6
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[DepthManagerTest] √ 测试通过: 极端标定拒绝
监听器已移除：HID7
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[DepthManagerTest] √ 测试通过: 极端标定 N=128 可行
监听器已移除：HID8
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[DepthManagerTest] √ 测试通过: 反向calibrate(800,200)
[DepthManagerTest] 
[DepthManagerTest] ----- 基本操作测试 -----
[DepthManagerTest] √ 测试通过: 添加新实体
监听器已移除：HID9
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[DepthManagerTest] √ 测试通过: 热路径 eager apply
监听器已移除：HID10
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[DepthManagerTest] √ 测试通过: 批量热路径
监听器已移除：HID11
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[DepthManagerTest] √ 测试通过: 更新已有实体
监听器已移除：HID12
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[DepthManagerTest] √ 测试通过: 移除实体
[DepthManagerTest] 
[DepthManagerTest] ----- 零碰撞测试 -----
监听器已移除：HID13
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[DepthManagerTest] √ 测试通过: 50实体同Y零碰撞
[DepthManagerTest] 
[DepthManagerTest] ----- 排序单调性测试 -----
监听器已移除：HID14
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[DepthManagerTest] √ 测试通过: 排序单调性(显示列表)
监听器已移除：HID15
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[DepthManagerTest] √ 测试通过: 同Y稳定性(显示列表)
[DepthManagerTest] 
[DepthManagerTest] ----- 错误处理测试 -----
监听器已移除：HID16
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[DepthManagerTest] √ 测试通过: null MC 处理
[DepthManagerTest] √ 测试通过: NaN targetY 处理
[DepthManagerTest] √ 测试通过: 未注册/null 查询
监听器已移除：HID18
[DepthManagerTest] √ 测试通过: 容量上限
[DepthManagerTest] √ 测试通过: 外部clip查询
[DepthManagerTest] 
[DepthManagerTest] ----- 惰性剔除测试 -----
监听器已移除：HID17
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[DepthManagerTest] √ 测试通过: 惰性剔除
监听器已移除：HID20
[DepthManagerTest] √ 测试通过: 容量压力兜底回收
监听器已移除：HID19
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[DepthManagerTest] √ 测试通过: 同名MC复用
[DepthManagerTest] 
[DepthManagerTest] ----- stale 引用隔离测试 -----
监听器已移除：HID21
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[DepthManagerTest] √ 测试通过: dead引用sweepDead回收
监听器已移除：HID22
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[DepthManagerTest] √ 测试通过: 同名重建路径解析安全
[DepthManagerTest] 
[DepthManagerTest] ----- 同名外部clip隔离测试 -----
监听器已移除：HID23
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[DepthManagerTest] √ 测试通过: 同名外部clip隔离
[DepthManagerTest] 
[DepthManagerTest] ----- 批量stale __dmIdx测试 -----
监听器已移除：HID24
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[DepthManagerTest] √ 测试通过: 批量stale__dmIdx安全
[DepthManagerTest] 
[DepthManagerTest] ----- 内存管理测试 -----
监听器已移除：HID25
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[DepthManagerTest] √ 测试通过: add-remove 循环
监听器已移除：HID26
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[DepthManagerTest] √ 测试通过: clear 操作
监听器已移除：HID27
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
监听器已移除：HID28
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[DepthManagerTest] √ 测试通过: dispose + 重建
[DepthManagerTest] 
[DepthManagerTest] ----- 场景切换测试 -----
监听器已移除：HID29
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[DepthManagerTest] √ 测试通过: 场景切换(全量re-feed)
监听器已移除：HID30
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[DepthManagerTest] √ 测试通过: 场景切换(部分re-feed)
[DepthManagerTest] 
[DepthManagerTest] ==================================================
[DepthManagerTest]  性能基准（参考值）
[DepthManagerTest] ==================================================
[DepthManagerTest] 预生成随机数据: 100000 个 (种子=42, 可复现)
[DepthManagerTest] 正在预热测试环境...
监听器已移除：HID33
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[DepthManagerTest] 预热完成
[DepthManagerTest] 测试原生 swapDepths 性能 (2000 迭代)...
[DepthManagerTest] 原生 swapDepths: 总 121ms / 2000 迭代 = 61 μs/帧
[DepthManagerTest] 测试 DepthManager 性能（稳态，2000 迭代）...
监听器已移除：HID31
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[DepthManagerTest] DepthManager(逐实体): 总 331ms / 2000 迭代 = 166 μs/帧（稳态）
[DepthManagerTest] 测试 DepthManager 批量性能（稳态，2000 迭代）...
监听器已移除：HID34
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[DepthManagerTest] DepthManager(批量): 总 197ms / 2000 迭代 = 99 μs/帧（稳态）
[DepthManagerTest] ────── 逐实体 updateDepth（2000 迭代，50 实体） ──────
[DepthManagerTest]   裸 swapDepths : 61 μs/帧（理论下界，无 lookup/clamp/注册/stale 检测）
[DepthManagerTest]   DepthManager  : 166 μs/帧
[DepthManagerTest]   倍率          : 2.72x
[DepthManagerTest]   管理层开销    : 173.6%
[DepthManagerTest]   旧方案基线    : 1358 μs/帧（WAVL 树）→ 当前 8x 加速
[DepthManagerTest] ────── 批量 updateDepthBatch（2000 迭代，50 实体） ──────
[DepthManagerTest]   裸 swapDepths : 61 μs/帧（理论下界，无 lookup/clamp/注册/stale 检测）
[DepthManagerTest]   DepthManager  : 99 μs/帧
[DepthManagerTest]   倍率          : 1.62x
[DepthManagerTest]   管理层开销    : 62.8%
[DepthManagerTest]   旧方案基线    : 1358 μs/帧（WAVL 树）→ 当前 14x 加速
[DepthManagerTest] 
[DepthManagerTest] ==================================================
[DepthManagerTest]  测试总结
[DepthManagerTest] ==================================================
[DepthManagerTest] 功能测试:
[DepthManagerTest] - 总测试数: 29
[DepthManagerTest] - 通过: 29
[DepthManagerTest] - 失败: 0
[DepthManagerTest] √ 全部通过
[DepthManagerTest] 正在清理测试环境...
监听器已移除：HID35
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[DepthManagerTest] 测试环境已清理
=== END TEST ===
[compile] done
