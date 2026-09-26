# 首批子弹视觉源

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

当前 `bullet_visual_caps` 仅协商**影子采样**。AS2 仍绘制所有子弹并持有碰撞、
伤害、随机数和生命周期；连接后的 F 包可追加 `\x05` 段，格式为
`epoch|frame|normalCount|chainCount|overflow;style,x,y,rotation,xscale,yscale,alpha;...`。
最多 256 个可见实例，Host 对长度、数量、数值和连接代次严格检查并汇总传输
成本。当前数据不进入原生画面。建立原生绘制、资源就绪与显示所有权恢复路径后，
再逐实例启用接管；影子统计或资源导出不能作为迁移完成、净收益或实机观感证明。
