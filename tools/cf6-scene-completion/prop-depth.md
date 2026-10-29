# CF6 场景物件与人物深度

## 生产边界

`Cf6PropDepthService` 只给需要交错遮挡或运动的少量场景物件分配可拥有、可回收的世界直接子级。
静态底图继续烘焙；不可把整景拆成动态 MovieClip。背景烘焙随后卸载 `world.背景`，因此动态物件也不能留在背景内。

`SceneManager` 将 `world.getNextHighestDepth()` 定义为创建暂存区，单位与物件随后都交给同一个
`DepthManager.updateDepth`，不得手写源 depth 占据单位排序槽，也不得交换整个 `world.效果`。
`world.效果` 内部的顺序只能比较其子级，不能与 world 直接子级人物交错。

## 接线 API

实现：[Cf6PropDepthService.as](../../scripts/类定义/org/flashNight/arki/scene/Cf6PropDepthService.as)。

- `begin(world, worldIdentity, ownerToken)` 返回 session；同 owner 重入返回原 session，异 owner 拒绝。
- `create(session, id, worldX, worldY, sortY)` 返回 ticket 或 null；`ticket.holder` 是世界直接子级。
- `valid(ticket)` 必须在加载回调或修改画稿前调用，检查世界普通对象身份、session、owner、holder token/name/parent 和现役管理器。
- `update(ticket, sortY)` 只更新世界脚点排序，不推进动画、不改人物、不绕过暂停。
- `release(ticket)` 回收自己的 holder 和管理器登记；`end(session)` 释放全组，供死亡、撤退、换场、加载失败共用。

加载目标应是 `ticket.holder.createEmptyMovieClip("art", 0)`，不可对 holder 本身 loadClip（会清除拥有标记）。
回调除 `valid(ticket)` 外仍须核对自己的 load attempt、target 和监听器身份；服务并不替消费者管理异步请求。
调用者在结束时撤销自己的 loader/listener，再调用 end。原生 world 卸载会销毁其子级；服务不保留全局 session，也不新增每帧 watcher。

`worldX/worldY` 与 `sortY` 均为最终 CF7 世界坐标。只有画稿 art 承接视觉倍率及 pivot，不能再次缩放 sortY。
比例数据的 `artMatrixSpace="holder-local"` 表示矩阵平移为 `-A*pivotNative`，holder 位于 worldPivot，
因此 art 的 pivot 恰好映射到 holder 原点；源父容器的 `parentLocalAfter` 不能直接赋给 art。
门前景、门后景各用独立 ticket 与明确的地面脚点。源图层 depth 仅用于源层顺序，不是 world sortY。
相同 sortY 的前后顺序遵循 DepthManager 的稳定注册顺序，不人为承诺与任意人物的同 Y 前后关系。

## 遮罩与生命周期限制

人物仍是原来的 world 直接子级；AS2 没有 reparent 或 getMask。门前景遮挡不能替代人物裁剪。
现在由 [Cf6ActorMaskPresentation](../../scripts/类定义/org/flashNight/arki/scene/Cf6ActorMaskPresentation.as)
在独立拥有的位图代理上使用门遮罩，原人物的 mask、父链、碰撞与身份不改。原人物隐藏与恢复继续归 TraversalService 的显示责任与比较后恢复逻辑。

代理只接受 **born-known-none**：当前 `cf6-sting` 的 `historical/type61` 路线、active、同存档槽、当前受控的 `主角-男`，
由统一单位加载函数在本次新 attach 的 initObject 中注入
[Cf6ActorMaskState](../../scripts/类定义/org/flashNight/arki/scene/Cf6ActorMaskState.as) 的普通对象出生身份与实例级转发函数。
其他演员、书籍和旧实例不补签“无 mask”，也不改 MovieClip.prototype。
转发先把记录设为 unknown，然后原样调用 native.apply；保留原返回值及异常。
仅明确 `setMask(null)` 且 native 返回 true 才重新确认 none。已有外部 mask、被覆盖的转发函数、出生换代或未知实例均拒绝代理。
恢复转发函数本身不消除已观察到的未知历史。当前源码没有其他 actor 级 setMask 路线；后续调用须沿实例方法，不能绕过记录直接调用 prototype native。

未知 actor 级外部 mask **不属于支持范围**。原点的六项 probe 曾得到可捕获结果，但复杂位置、镜像、缩放的 R1–R4 试验均未成立；
R4 使用唯一实例路径且跨帧稳定后，仍出现外部 mask 的空捕获。这些否定证据保留，不把新合同的通过改写成旧的无条件支持。
actor 内部 man 子树的遮罩由整只 actor 的绘制保留，不能改为只画 man 来绕过 actor 级未知状态。

代理复用现役 PropDepth session/ticket，sortY 为同一人物脚点；world/actor/control/birth/token、mask art 和显示责任都要精确匹配。
单边最大 1024、每块位图最多 524288 像素；非法边界、预算超限、分配失败、空捕获或失去拥有关系均释放代理并使演出取消，不能返回空白成功。
大门 1750 没有人物 mask，其空 Mask 占位始终不编译、不消费。

1720/1729 的源 mask190 不仅覆盖人物，还覆盖 source depth4/5 的移动背景。生成器现仅给其 `clipDepth` 实际包含的 Back 元件加原生遮罩，
没有把整个 Back/Front 误裁；原静态背景与门框仍独立。实际 SWF 的窗外像素保持不变、窗内存在运动。

MovieClip 引用可能在同路径重建后重指向新实例，因此 session/holder 使用普通 Object 身份。
检测到外国替换后，迟到 release/end 不碰新实例、不删其深度登记；被外部绕过服务移除的旧登记由场景管理器生命周期清理，
不得为回收一个旧 ID 而误删同路径新对象。正常所有者应先 release 再删 holder；不要自行 removeMovieClip。
重新加载用新 ticket（释放旧 ticket 后可复用业务 id），不能复用旧加载回调。

## 验证入口与证据范围

[focused runner](../../scripts/run-cf6-prop-depth-tests.ps1) 走现役 scratch 备份、mutex 与恢复协议，
读取独立 [template](../../scripts/test-runners/cf6-prop-depth/TestLoader.as.template)，
运行 [suite](../../scripts/类定义/org/flashNight/arki/scene/Cf6PropDepthServiceTest.as)。
30 个断言含真实 BitmapData 像素前后遮挡、视觉倍率与脚点解耦、重复拥有者、容量失败、释放回收、
holder/world 同路径替换、死亡撤退清理入口及结束后的迟到调用。

编译与 AVM1 统一由主集成队列执行；深度 suite 已获得本轮 Compiler 0/0 与 30/0。
[实际门资源 runner](../../scripts/run-cf6-traversal-assets-tests.ps1) 检查八个 SWF 的 1124 帧、30 个断言，
包括 Mask 的活动帧/固定窗口及 Back 的原生 clipDepth 裁剪；1750 Front 的 40 帧均为空是源事实。

[born-known-none runner](../../scripts/run-cf6-actor-mask-known-none-tests.ps1) 使用独立
[原生出生 fixture](../../scripts/test-runners/cf6-actor-mask-known-none/MaskBirthProbe/MaskBirthProbe.xfl)，
21 项实际 attachMovie/第一帧断言证明 initObject 转发先于原第一帧 setMask，并验证返回/异常和出生换代。
几何与生命周期 suite 覆盖非零世界/人物坐标、左右镜像、人物缩放、内部 man mask、隐藏后采样、显示责任失效与根 mask 拒绝。
当前出生 21 项与几何/生命周期 47 项（含 owned-mask 收窄/恢复）已取得本轮真实 AVM1 通过及 Compiler 0/0。
旧的无条件外部 mask fixture 已原字节移入[只读诊断归档](diagnostics/unknown-actor-mask/README.md)，
保留迁移 SHA 与失败回执标识，不再留下现役失败 runner，也不作为新合同的通过入口。

这些机器证据仍不代签真实装备组合、门口脚底比例、玩家观感或整章标准入口验收。
