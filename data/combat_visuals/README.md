# 战斗表现派生资源

`bullet_styles.v1.json` 由 `tools/combat-bullet-visuals/build.py` 从
`flashswf/arts/原版素材库-子弹` 的 XFL 真源和已发布 SWF 确定性派生。不要手改 JSON。

```powershell
python tools/combat-bullet-visuals/build.py
python tools/combat-bullet-visuals/build.py --check
```

首批仅登记两种单帧视觉：`普通子弹` 与 `加强普通子弹`。它们分别与
`单元体-普通子弹`、`单元体-加强普通子弹` 共享一个视觉母版；六个枪式联弹
前缀只复用母版，不继承普通子弹的碰撞或伤害规则。普通单元体此前在 Y 方向
偏移 18 twip（0.9 像素），现已在 XFL 真源对齐到普通子弹的注册原点。
加强型基底的黄色 GlowFilter 参数由真源读取；不支持的新滤镜、混合或复杂
形状会让生成失败，不会静默降级。

`bullet_visual_caps` 按资源与原生能力协商影子采样或显示接管。AS2 始终持有碰撞、
伤害、游戏随机数和逻辑生命周期；连接后的 F 包可追加 `\x05` 段，格式为
`epoch|frame|normalCount|chainCount|overflow|nativeOwned;style,x,y,rotation,xscale,yscale,alpha;...`。
最多 256 个可见条目，Host 对长度、数量、数值和连接代次严格检查。
旧包缺少 `nativeOwned` 时仅采样。运行开关与资源就绪共同决定是否接管，不能从目录存在
推断当前进程已启用。当前源码已取消子弹接管的 `tmp` 目录限制；目录/原生就绪且
未设置 `CF7_BULLET_NATIVE_DISABLE=1` 时，候选与正式路径使用相同准入规则。

`effects.v1.json` 和 `effects-atlas.png` 是弹壳/枪火的独立白名单与图集，生成、
脚本适配、资源上限和验证命令见[资源工具](../../tools/combat-fx-assets/README.md)。
Host 校验图集和源 SWF，GPU 纹理就绪后才发送 `combat_fx_caps` v1；AS2 使用返回的
样式索引，不另维护启用清单。新增 F `\x06` 段在子弹段之后：

```text
epoch|sequence|gameTick|paused
;s,style,x,y,scaleXPercent,scaleYPercent,groundY,count,seed,0
;m,style,x,y,scaleXPercent,scaleYPercent,rotation,seed,0
;i,style,x,y,scaleXPercent,scaleYPercent,rotation,seed,0
;a,settlementId,drawn
```

这些是有序出生/贴图回执事件，不能按 latest-wins 丢弃中间 F 包；native 绘制快照可以更新覆盖。
每帧最多 32 个发射事件、独立的 32 个命中事件和 64 个回执；每个弹壳事件最多展开 64 颗，
C# 活动上限为 256 弹壳、64 枪火、128 命中特效，与子弹预算分离。游戏 tick 控制物理和帧序列；暂停冻结，
大于 8 tick 的缺口清理旧装饰，不用墙钟无限追赶。

C# 首次触地通过 `combat_fx_events` 提示声音；落稳回传世界位姿，每批至多 8 项。
AS2 每帧最多贴 4 项、队列 64、每图 4096、每 64×64 格 32；源位图最多缓存 32 种。
贴图回执使原生落稳精灵短暂保留并渐隐；缺回执有超时，旧连接/旧场景不能贴入新图。
弹壳和屎花参与世界调色，枪火及火花类自发光；绘制顺序为弹壳→子弹→命中特效→枪火。

命中特效只从已审核、不使用返回 MovieClip 的命中入口准入，普通/射线/地图终止、弹道取消
与单位受击仍执行原来的结算逻辑。`EffectSystem.Effect` 第六参数显式传 `true` 才尝试接管；
未传时继续返回旧 MC，避免破坏调用方的后续变换/状态使用。白名单外效果仍走 AS2。

`local_lights.v1.json` 是手写视觉预设：枪火颜色、世界半径、能量和游戏 tick 寿命，以及全局响应上限。
它不改变伤害或夜视选择。C# 从发射事件生成独立的短时光源，最多 16 个；空枪火动画分支仍可发光，
命中特效不自动生成灯。原生 ABI 7 把光与精灵作为同一快照提交，在 256×144 RGBA16F 光场内累加，
世界、天气、弹体与受光精灵共享一次纹理采样，按当前视口/镜头对齐。光场约 288 KiB，无阴影/遮挡深度。
局部增亮从未调暗的源纹理做有界曝光响应，保留纹理细节。普通光照的环境 LUT 不压暗或染蓝枪火暖光；
夜视等矩阵模式仍保留其色向。峰值保持两个游戏 tick 后线性衰减，当前预设寿命为 4–6 tick；
叠加响应上限为 0.78，半径外不受影响，纯黑源不会凭空变成不透明光球。
将 `maximumResponse` 设为 0 并重启可做无灯对照；光源同样随游戏 tick 暂停、切场景和断连清理。

未支持或能力未就绪时，新实例走旧 AS2 路径；已接管的装饰在超限/断连时可以丢弃，
不会转成玩法对象或补播发射事件。AS2 的 `VisualRandom` 与 C# 事件 RNG 均独立于战斗 RNG。
源码、资源导出、夹具或候选不能单独证明净性能收益与游戏内观感。
正式列车的 `combat-fx-assets-current` 检查图集、源闭包、动画适配和光源预设；
检查仅需 Python 标准库。完整重新导出另需已安装的 Java/FFDec 与 Pillow。
