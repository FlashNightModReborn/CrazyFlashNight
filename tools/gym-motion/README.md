# 健身房三种动作派生

作者源为 `flashswf/arts/things0/LIBRARY/sprite/Symbol 624.xml`；运行资源在 `launcher/web/assets/gym/`。动作包只负责画面，不处理训练、扣费或保存。

## 生成与校验

在仓库根目录运行；需要 Python、Pillow，以及仓库内锁定的 `tools/ffdec/ffdec-cli.exe`：

```powershell
python tools/build_gym_motion_package.py --repo . --out .
python tools/verify_gym_motion_package.py --repo . --out .
node tools/gym-motion/verify-browser.js
```

前两个脚本也接受其他 `--out <目录>` 来构建或核查隔离副本；`--repo` 必须显式提供。生成器锁定 XFL 作者源、已发布 `things0.swf` 和 FFDec 摘要。校验器重新导出三件器材 SVG/PNG，核对资源哈希、透明覆盖率、源摘要和精确文件集。相同输入在隔离目录重建，8/8 文件 SHA-256 一致。浏览器脚本用两套已有角色穿搭及当前玩家示例穿搭逐项检查三种动画的可见像素、帧推进和关闭后资源释放，截图存入 `tmp/gym-motion-full/`。

当前运行包为 8 文件、680,495 字节。三段均为 30 fps、26 层，播放原帧序，不补循环接缝：

| 器材 | 原时间轴帧索引 | 循环帧数 | 关键帧曝光 | 直接实例 |
| --- | --- | ---: | ---: | ---: |
| 哑铃 | `[1, 78)` | 77 | 103 | 99 |
| 深蹲杠铃 | `[79, 154)` | 75 | 159 | 153 |
| 木人桩 | `[155, 282)` | 127 | 588 | 583 |

人物皮肤复用 `launcher/web/assets/dressup/manifest.json`。`GymMotionRenderer.preparePortrait(portrait, stationId)` 和 `canRenderPortrait(portrait, stationId)` 对具体站点、具体外观核验；省略 `stationId` 兼容木人桩先导。器材切换时销毁旧画布、建立新画布。

## 器材填充来源

原 `xfl-ui-svg` 将同一填充面的不连续 Edge 片段直接拼接，造成器材主体透明缺口。H1 运行包改用锁定的 `things0.swf` 中 FFDec DefineShape 3209/3210/3211；同时用 XFL `shape/Symbol 621/622/623` 的摘要、填充色和尺寸绑定作者源。已发布 SWF 只作为编译参照，不代替可编辑 XFL。

| XFL 元件 | SWF 字符 ID | 4 倍 PNG 尺寸 | alpha≥128 像素 |
| --- | ---: | ---: | ---: |
| `shape/Symbol 621` | 3209 | 504×265 | 81,316 |
| `shape/Symbol 622` | 3210 | 1277×392 | 198,147 |
| `shape/Symbol 623` | 3211 | 340×841 | 176,692 |

哑铃直接用 Symbol 621，深蹲直接用 Symbol 622，木人桩直接用 Symbol 623，三段都包含 `主角肢体素材/Symbol 3`。Symbol 3 的阴影来自 XFL SVG，AS2 飞行位移未执行；空 `AdjustColorFilter` 按恒等处理。Flash 像素一致性、当前玩家外观和首尾姿势跳变仍需人类及游戏内验证。
