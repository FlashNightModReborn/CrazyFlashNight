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
;l,id,kind,x,y,dx,dy,length,halfWidth,energy,r,g,b,nearX,nearY,nearRadius,nearEnergy
```

`s/m/i/a` 是有序出生/贴图回执事件，不能按 latest-wins 丢弃中间 F 包；`l` 是本包的完整装备光源快照，未出现的旧 id 立即移除。native 绘制快照可以更新覆盖。
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
命中特效不自动生成灯。原生 ABI 9 把光与精灵作为同一快照提交，在 256×144 RGBA16F 光场内累加，
世界、天气、弹体与受光精灵共享一次纹理采样，按当前视口/镜头对齐。光场约 288 KiB，无阴影/遮挡深度。
局部增亮从未调暗的源纹理做有界曝光响应，保留纹理细节。普通光照的环境 LUT 不压暗或染蓝枪火暖光；
夜视等矩阵模式仍保留其色向。峰值保持两个游戏 tick 后线性衰减，当前预设寿命为 4–6 tick；
叠加响应上限为 0.78，半径外不受影响，纯黑源不会凭空变成不透明光球。
将 `maximumResponse` 设为 0 并重启可做无灯对照；光源同样随游戏 tick 暂停、切场景和断连清理。

`combat_fx_caps.equipmentLights=2` 与 native 就绪共同开启手电/激光；额外 `equipmentRadialLights=1` 开启常驻径向源，旧能力保持兼容。`kind=1` 为软边锥形手电，`kind=2` 为恒宽激光，方向必须单位化，长度 1–1024、半宽 0.5–512。`kind=0` 的 `length` 表示半径 1–320，方向、半宽和近身尾均须为 0。能量 0–2、RGB 为 0–1；重复 id、非法数值或超量使整包拒绝。Host 仍接受最多 64 条来源记录，AS2 自身先把至多 256 个原始贡献归并/裁剪到最多 16 条实际灯记录，玩家优先、同级保留迟滞。Host 保留仍存活的 id，空位按 id 填入，枪火只用余量；新枪火不会驱逐常驻灯。

身体静态贡献在穿戴时注册、卸载时注销，不设逐件逐帧任务；集中快照验证所有权并更新角色位置，传输重连保留仍有效的身体绑定。动态兵器/手电/激光失去续报超过 2 个游戏 tick 时停止投影；Host 沿用大于 8 tick 的断流清理。暂停冻结计时，可见性/死亡/失效身份仍清除对应投影。

静态身体来源在同一次遍历中完成校验和收集；角色公共检查与镜头参数每包共享，单一来源槽位不再重复进入归属调用链。组成员资格变化使合并参数失效，径向记录缓存固定字段，位置或刀光合并结果变化时更新。缓存不跨越身份或换装检查：同一 tick 内替换物品、同长度原位修改插件、隐藏和死亡仍即时生效；本优化不降低采样频率或实际灯预算。

装备径向光在 AS2 端以普通枪火强度 1.5 标定同角色身体/兵器组合峰值，包含刀光脉冲；异色分灯按当前点光 `(1-r²)²` 衰减的上界约束重叠，仍用原有 kind=0 记录。径向输出色向白色混合 20% 以提升材质辨识，手电/激光和枪火参数保持。该上限不限制其他角色或枪火的独立贡献，场景总响应仍由 `maximumResponse` 控制；这次调整不新增 shader pass 或光源记录。

CPU/GPU 灯记录为 16 个 float：`x,y,length,energy,r,g,b,kind,dx,dy,halfWidth,0,nearX,nearY,nearRadius,nearEnergy`（点光 `kind=0`）。最后四项仅手电可非零，坐标范围 ±1e6、半径 0–320、能量 0–2；半径与能量须同为正或同为 0，无近身光时末四项全 0。Host 兼容旧 13 字段 wire，其近身光为零。

常驻径向记录复用现有 native kind=0 和 ABI 9；生命周期由完整装备快照持有，不经枪火出生事件续命，也不按枪火寿命衰减。全部局部灯仍在同一次 `Draw(lightCount*6)` 中绘制；合并减少来源检查、记录和光场覆盖，不意味着减少了同数量的 drawcall。

定向光按视口与镜头投影，并对低分辨率光场的细束边缘抗锯齿。手电近身光使用连续的径向高斯衰减，前照从近身亮区展开、逐渐归到枪口轴线，并沿纵向持续衰减；没有近身光时仍从枪口出光。一个 quad 覆盖两形并集，两区域以 `A+B-A*B/peak` 有界平滑融合，消除等亮核心与最大值拼接轮廓；整盏灯同进同出并只占一个名额。激光横向使用窄高斯柔光，束首短渐入、末段长渐隐，以保留 AS2 细红束的识别度。它照亮束带覆盖的材质像素，不选择敌人、不做目标全身高亮；当前无墙体遮挡或穿透判定。AS2 保留原有光束显示与生命周期，插件的防御玩法也由 AS2 独立控制，配置见[装备函数合同](../../scripts/逻辑/装备函数/README.md#skill-interaction)。

未支持或能力未就绪时，新实例走旧 AS2 路径；已接管的装饰在超限/断连时可以丢弃，
不会转成玩法对象或补播发射事件。AS2 的 `VisualRandom` 与 C# 事件 RNG 均独立于战斗 RNG。
源码、资源导出、夹具或候选不能单独证明净性能收益与游戏内观感。
正式列车的 `combat-fx-assets-current` 检查图集、源闭包、动画适配和光源预设；
检查仅需 Python 标准库。完整重新导出另需已安装的 Java/FFDec 与 Pillow。
