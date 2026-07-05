# 长枪副武器重构 Phase A Flash 资产施工单

**目标**：为长枪副武器准备 UI 承载帧。人类在 Flash CS6 / XFL 中施工，agent 在施工后验收。  
**范围**：只改 `flashswf/UI/玩家信息界面` 资产，不改 AS2 运行时逻辑，不改数据 XML。  
**施工前基线**：`python scripts/tools/xfl/audit.py flashswf/UI/玩家信息界面` 当前为 `CLEAN`。

## 1. 施工对象

- XFL：`flashswf/UI/玩家信息界面/玩家信息界面.xfl`
- 符号：`flashswf/UI/玩家信息界面/LIBRARY/sprite/玩家必要信息界面.xml`
- 当前标签：
  - `长枪`：index 12，duration 5
  - `双枪`：index 32，duration 5
  - 当前总长度约 37 帧

## 2. 目标结果

新增标签帧：

```text
name = 长枪副武器
index = 37
duration = 5
```

验收形态：

- 普通 `长枪` 帧保持现状，不出现第二行副武器弹药。
- `双枪` 帧保持现状，不回归。
- 新 `长枪副武器` 帧存在双行弹药显示：
  - `text1` 显示 `子弹数 / 弹夹数`
  - `text2` 显示 `子弹数_2 / 弹夹数_2`
- 新帧保留长枪战技栏 / 战技进度条 / 战技控制器的承载能力，供 Phase 1 的 F 快装控制槽使用。

## 3. 图层施工要求

不要把新帧插入 `长枪` 与 `兵器` 中间。追加在 `双枪` 后面，减少既有帧位移和无关 diff。

| 图层 | 新 `长枪副武器` 帧来源 |
|---|---|
| `Labels Layer` | 新增 label `长枪副武器`，建议 index 37、duration 5 |
| `Script Layer` | 保持现有刷新函数；必要时延展总时长到覆盖新帧 |
| `战技控件` | 复制 / 恢复 `长枪` 帧语义，必须有 `战技进度条`、`战技控制器` 承载 |
| `战技文字 矢量化` | 复制 / 恢复 `长枪` 帧语义 |
| `战技背景` | 复制 / 恢复 `长枪` 帧语义 |
| `战技图标` | 复制 / 恢复 `长枪` 帧语义 |
| `空战技` | 复制 / 恢复 `长枪` 帧语义 |
| `组件` | 复制 `双枪` 帧的 `通用透明组件`，保留 onClipEvent 脚本 |
| `文字` | 复制 `双枪` 帧的 `text1` 和 `text2`，不要只复制 `text2` |
| `图标` | 复制 `双枪` 帧双行弹药图标 |
| `背景` | 复制 `双枪` 帧双行背景 |
| 其他层 | 按 `长枪` 帧语义复制；若长枪帧为空则保持空 |

关键原因：普通 `长枪` 帧的主弹药文本是 `variableName=子弹数 / 弹夹数`，没有 `text1` 实例；`通用透明组件` 会同时写 `_parent.text1.text` 和 `_parent.text2.text`。因此新帧的弹药双行区域必须从 `双枪` 帧成套复制 `text1/text2 + 通用透明组件`。

## 4. 人类施工步骤

1. 用 Flash CS6 打开 `flashswf/UI/玩家信息界面/玩家信息界面.xfl`。
2. 进入符号 `玩家必要信息界面`。
3. 在 `双枪` 帧之后追加 5 帧，创建标签 `长枪副武器`。
4. 按第 3 节图层施工要求复制帧内容。
5. 确认不新增不必要 symbol / linkage。
6. 保存 XFL / FLA；如本地流程需要，导出 UI SWF。
7. 记录是否触碰主 FLA、是否新增 linkage、是否移动共享元件。

## 5. 人类自检

在 Flash CS6 中手动切到三个标签确认：

- `长枪`：没有第二行 `text2`。
- `双枪`：仍有 `text1` / `text2` 双行。
- `长枪副武器`：有 `text1` / `text2` 双行，并且战技控件承载对象存在。

## 6. Agent 验收命令

施工完成后由 agent 执行：

```powershell
chcp.com 65001 | Out-Null
python scripts/tools/xfl/audit.py flashswf/UI/玩家信息界面
python scripts/tools/xfl/rename_a_class.py flashswf/UI/玩家信息界面 --dry-run
python scripts/tools/xfl/rename_a_class.py flashswf/UI/玩家信息界面
python scripts/tools/xfl/fix_includes.py flashswf/UI/玩家信息界面
python scripts/tools/xfl/audit.py flashswf/UI/玩家信息界面
python tools/linkage_scanner/scan_linkage.py --xml-only
```

验收结论只接受两种：

- `资产可供 Phase 1 接入`
- `阻断：列出具体 XFL / linkage / 帧对象问题`

## 7. 不做事项

- 不改 `战技控制器.xml`。
- 不改 `ReloadManager.as`。
- 不改 `TooltipBridge.as` 或 tooltip builder。
- 不手动编辑 SWF。
- 不在 Phase A 接入 `hasLongGunSubWeapon` 动态切帧；那是 Phase 1 的 AS2 工作。
