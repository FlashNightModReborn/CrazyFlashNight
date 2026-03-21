import org.flashNight.gesh.depth.*;

=== AUTOMATION TEST ===
Time: Sat Mar 21 10:55:05 GMT+0800 2026
[DepthManagerTest] 
==================================================
[DepthManagerTest]  DepthManager (Twip Trick) 测试套件
[DepthManagerTest] ==================================================
[DepthManagerTest] 正在设置测试环境...
[DepthManagerTest] 测试环境设置完成，创建了 50 个测试影片剪辑
[DepthManagerTest] 
----- 标定测试 -----
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
[DepthManagerTest] 
----- 基本操作测试 -----
[DepthManagerTest] √ 测试通过: 添加新实体
监听器已移除：HID8
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[DepthManagerTest] √ 测试通过: 热路径 eager apply
监听器已移除：HID9
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[DepthManagerTest] √ 测试通过: 批量热路径
监听器已移除：HID10
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[DepthManagerTest] √ 测试通过: 更新已有实体
监听器已移除：HID11
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[DepthManagerTest] √ 测试通过: 移除实体
[DepthManagerTest] 
----- 零碰撞测试 -----
监听器已移除：HID12
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[DepthManagerTest] √ 测试通过: 50实体同Y零碰撞
[DepthManagerTest] 
----- 排序单调性测试 -----
监听器已移除：HID13
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[DepthManagerTest] √ 测试通过: 排序单调性
监听器已移除：HID14
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[DepthManagerTest] √ 测试通过: 同Y稳定性
[DepthManagerTest] 
----- 错误处理测试 -----
监听器已移除：HID15
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[DepthManagerTest] √ 测试通过: null MC 处理
[DepthManagerTest] √ 测试通过: NaN targetY 处理
[DepthManagerTest] √ 测试通过: 未注册/null 查询
监听器已移除：HID17
[DepthManagerTest] √ 测试通过: 容量上限
[DepthManagerTest] √ 测试通过: 外部clip查询
[DepthManagerTest] 
----- 惰性剔除测试 -----
监听器已移除：HID16
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[DepthManagerTest] √ 测试通过: 惰性剔除
监听器已移除：HID19
[DepthManagerTest] √ 测试通过: 容量压力兜底回收
监听器已移除：HID18
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[DepthManagerTest] √ 测试通过: 同名MC复用
[DepthManagerTest] 
----- 内存管理测试 -----
监听器已移除：HID20
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[DepthManagerTest] √ 测试通过: add-remove 循环
监听器已移除：HID21
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[DepthManagerTest] √ 测试通过: clear 操作
监听器已移除：HID22
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
监听器已移除：HID23
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[DepthManagerTest] √ 测试通过: dispose + 重建
[DepthManagerTest] 
----- 场景切换测试 -----
监听器已移除：HID24
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[DepthManagerTest] √ 测试通过: 场景切换(全量re-feed)
监听器已移除：HID25
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[DepthManagerTest] √ 测试通过: 场景切换(部分re-feed)
[DepthManagerTest] 
==================================================
[DepthManagerTest]  性能测试
[DepthManagerTest] ==================================================
[DepthManagerTest] 预生成随机数据: 100000 个 (种子=42, 可复现)
[DepthManagerTest] 正在预热测试环境...
监听器已移除：HID28
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[DepthManagerTest] 预热完成
[DepthManagerTest] 测试原生 swapDepths 性能 (2000 迭代)...
[DepthManagerTest] 原生 swapDepths: 总 123ms / 2000 迭代 = 62 μs/帧
[DepthManagerTest] 测试 DepthManager 性能（稳态，2000 迭代）...
监听器已移除：HID26
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[DepthManagerTest] DepthManager(逐实体): 总 337ms / 2000 迭代 = 169 μs/帧（稳态）
[DepthManagerTest] 测试 DepthManager 批量性能（稳态，2000 迭代）...
监听器已移除：HID29
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[DepthManagerTest] DepthManager(批量): 总 201ms / 2000 迭代 = 101 μs/帧（稳态）
[DepthManagerTest] ────── 性能对比: 逐实体 updateDepth（2000 迭代，50 实体） ──────
[DepthManagerTest]   裸 swapDepths : 62 μs/帧
[DepthManagerTest]   DepthManager  : 169 μs/帧
[DepthManagerTest]   倍率          : 2.73x
[DepthManagerTest]   开销          : 174%
[DepthManagerTest] ○ 开销 174%，达到当前阶段 <200% 目标
[DepthManagerTest] 旧方案基线: 27.15ms/20迭代 ≈ 1358 μs/帧
[DepthManagerTest] √ 新方案优于旧方案 (8x 加速)
[DepthManagerTest] ────── 性能对比: 批量 updateDepthBatch（2000 迭代，50 实体） ──────
[DepthManagerTest]   裸 swapDepths : 62 μs/帧
[DepthManagerTest]   DepthManager  : 101 μs/帧
[DepthManagerTest]   倍率          : 1.63x
[DepthManagerTest]   开销          : 63.4%
[DepthManagerTest] ○ 开销 63.4%，批量热路径已处于可用区间
[DepthManagerTest] 旧方案基线: 27.15ms/20迭代 ≈ 1358 μs/帧
[DepthManagerTest] √ 新方案优于旧方案 (13x 加速)
[DepthManagerTest] 
==================================================
[DepthManagerTest]  测试总结
[DepthManagerTest] ==================================================
[DepthManagerTest] 功能测试:
[DepthManagerTest] - 总测试数: 24
[DepthManagerTest] - 通过: 24
[DepthManagerTest] - 失败: 0
[DepthManagerTest] √ 全部通过
[DepthManagerTest] 正在清理测试环境...
监听器已移除：HID30
所有监听器已移除：onUnload，已恢复原生处理器。
目标对象的所有事件已清理，已释放 watch 拦截器。
[DepthManagerTest] 测试环境已清理
=== END TEST ===
[compile] done
