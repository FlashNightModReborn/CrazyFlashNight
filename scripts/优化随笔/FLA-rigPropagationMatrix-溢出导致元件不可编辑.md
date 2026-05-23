# FLA rigPropagationMatrix 16.16 定点整数溢出 — 元件坐标轴歪斜 / 编辑闪退 / 无法另存

**文档角色**：Adobe Animate FLA 的 Asset Warp Rig 缓存溢出失败模式，canonical 复盘 + 可复用修复脚本。
**首次发生 / 定案日期**：2026-05-23。**实例文件**：`贝斯动画ex3version.fla`（仅本次受损者；非仓库内文件）。

---

## 0. 一句话结论

Animate 元件突然出现「**坐标轴歪斜非正交** + **进该元件就闪退/卡死** + **无法另存 XFL**」三件套同时发生时，第一假设是：该元件的 motion tween 帧上挂的 `rigPropagationMatrix` 缓存属性发生了 16.16 定点整数溢出，部分分量饱和到 `INT32_MIN`（`-2147483648`）或同量级，渲染时炸出 NaN/Inf。

修复方式：解包 FLA → 在 LIBRARY 下所有 XML 中剥离任何分量 `|v| > 6,553,600` 的 `rigPropagationMatrix` 属性 → 重打 ZIP。Animate 下次保存会自动重建剩余缓存，零功能损失。

---

## 1. 背景：rigPropagationMatrix 是什么

Adobe Animate（2020+ 引入 Asset Warp Rig）在 `DOMFrame` 上、对 `tweenType="motion"` 的补间帧挂一个 JSON 内联属性：

```xml
<DOMFrame index="473" tweenType="motion" motionTweenSnap="true" keyMode="22017"
  parentLayerIndex="3"
  rigPropagationMatrix='{"a":65399,"b":-2906,"c":2906,"d":65399,"tx":0,"ty":0}'>
```

- 用于**把对一个 rig 关键帧的编辑沿补间传播到中间帧**
- 6 个分量都是 **16.16 定点整数**（`a=65536` ≡ `1.0×` scale）
- 合法量级：`|a|, |d| ≤ ~65536`（rig 几乎没人放 100× 缩放）
- **仅作者期缓存**，**不参与运行时渲染**（渲染走 `DOMSymbolInstance/<Matrix>`，那是 6 位浮点字符串）
- 关键性质：**可丢失重建**。Animate 第一次保存会按需 lazy 重算。

---

## 2. 失败模式

### 2.1 用户感知到的三件套

| 症状 | 内部原因 |
|---|---|
| 进入元件后视图坐标轴明显倾斜（标尺线不再正交） | 元件内某帧矩阵奇异退化，绘制管线把它当全局世界变换 |
| 选/拖任何对象立刻闪退或卡死 | hit-test / 包围盒计算对该矩阵做 `inv`/`det`，得 NaN/Inf |
| 「无法将文档另存为 *.xfl」 | XFL 序列化对矩阵做 sanity check 抛错 |

### 2.2 损坏值的特征

典型的爆掉之后的属性：

```xml
<DOMFrame index="479" keyMode="15872" parentLayerIndex="3"
  rigPropagationMatrix='{"a":-2147483648,"b":-2147483648,
                        "c":-2147483648,"d":-2147483648,
                        "tx":-2147483648,"ty":-2147483648}'>
```

中间过渡帧通常**先**出现单个分量越界（例如 `"a":-1351837824` / `"b":1087619328`），到某一帧才全部塌缩为 INT32_MIN。

### 2.3 触发条件（推断）

- 元件已挂 Asset Warp Rig
- 在 rig 上反复做**大角度旋转 + 大缩放**的 motion tween 编辑
- 多次撤销/重做或在同一段补间上反复改 anchor

Animate 在补间细化时对 `rigPropagationMatrix` 做累积矩阵乘，临时变量没做 saturate / clamp，越界一次后污染随补间扩散到相邻帧、相邻层。

### 2.4 传染性

一旦一个元件爆了，**整个 FLA 同 rig 谱系的其它元件全都可能被波及**。本次实例数据：

| 元件 | 损坏帧数 / 总 rig 帧数 |
|---|---|
| 技能 | 540 / 2911 |
| 被击 | 149 / 625 |
| 贝斯技能 | 101 / 465 |
| 平a | 89 / 465 |
| 起身 | 17 / 193 |
| 走路 | 11 / 162 |
| 跑步 | 11 / 162 |
| 跑步 复制 | 2 / 117 |
| 击飞 | 1 / 18 |
| 死亡？ | 1 / 18 |
| **合计** | **922** |

「技能」元件内 35 层中重灾分布：`贝斯鞋`(228) > `贝斯`(162) > `贝斯完整头`(69) > `贝斯右手`(41) > `贝斯左手`(33)。说明溢出从腿部 rig 蔓延到全身。

---

## 3. 验证方法

### 3.1 FLA 是什么

FLA 是一个 OPC-style ZIP 包，第一条 entry 是 `mimetype`（值 `application/vnd.adobe.xfl`，必须 **STORED 不压缩**），其余 DEFLATE 压缩。结构：

```
mimetype
DOMDocument.xml         主文档（场景层级 + 时间轴）
PublishSettings.xml
LIBRARY/<分类>/<元件名>.xml    每个元件一份 XML
META-INF/metadata.xml
bin/M N <id>.dat        Animate 内部缓存
```

### 3.2 解包要点

- **Info-Zip / 大多数 \*nix unzip 工具不认 GBK 文件名**，对中文文件名/路径会乱码（CP437 / CP936 混乱）
- 用 **.NET `System.IO.Compression.ZipFile.ExtractToDirectory`** 解，PowerShell 一行：

```powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($fla, $dst)
```

- 原始 FLA 可能尾部有 ~54 字节 trailer（Animate 自家加的元数据），.NET API 会无视并正确解出全部 entry

### 3.3 定位损坏

正则扫所有 `LIBRARY/**/*.xml`：

```regex
rigPropagationMatrix='\{([^}]+)\}'
```

提取大括号内每个 `"<key>":<int>`，任意分量绝对值 > `6553600`（= 100× scale 量级）即视为损坏。

---

## 4. 修复脚本（可复用）

### 4.1 剥离损坏属性

`fix_rig.py`：

```python
"""
Strip corrupted rigPropagationMatrix attributes from FLA library XMLs.
"""
import re
import sys
from pathlib import Path

THRESHOLD = 6_553_600  # |16.16 fixed| > 100x scale -> garbage
RIG_RE = re.compile(r"\s*rigPropagationMatrix='\{([^}]+)\}'")
NUM_RE = re.compile(r'"[a-z]+":(-?\d+)')


def is_bad(matrix_str: str) -> bool:
    for m in NUM_RE.finditer(matrix_str):
        if abs(int(m.group(1))) > THRESHOLD:
            return True
    return False


def fix_file(path: Path) -> int:
    text = path.read_text(encoding="utf-8")
    removed = 0

    def repl(m):
        nonlocal removed
        if is_bad(m.group(1)):
            removed += 1
            return ""
        return m.group(0)

    new_text = RIG_RE.sub(repl, text)
    if removed:
        path.write_text(new_text, encoding="utf-8")
    return removed


def main(root: str):
    total = 0
    for xml in Path(root).rglob("*.xml"):
        n = fix_file(xml)
        if n:
            print(f"  {xml.relative_to(root)}: stripped {n}")
            total += n
    print(f"Total: {total} attributes stripped")


if __name__ == "__main__":
    main(sys.argv[1])
```

调用：`python fix_rig.py <extracted_root>/LIBRARY`

### 4.2 重打 ZIP

`pack_fla.py`：

```python
"""
Repack extraction into a valid FLA. mimetype must be first + STORED.
"""
import os
import sys
import zipfile
from pathlib import Path


def pack(src_dir: str, out_fla: str):
    src = Path(src_dir)
    skip = {"fix_rig.py", "pack_fla.py"}
    with zipfile.ZipFile(out_fla, "w", zipfile.ZIP_DEFLATED, allowZip64=True) as z:
        mimetype = src / "mimetype"
        if mimetype.exists():
            z.write(mimetype, "mimetype", compress_type=zipfile.ZIP_STORED)
        for root, dirs, files in os.walk(src):
            dirs.sort()
            for fn in sorted(files):
                if fn in skip:
                    continue
                if fn == "mimetype" and Path(root) == src:
                    continue
                full = Path(root) / fn
                rel = full.relative_to(src).as_posix()
                z.write(full, rel, compress_type=zipfile.ZIP_DEFLATED)
    print(f"Wrote {out_fla} ({os.path.getsize(out_fla):,} bytes)")


if __name__ == "__main__":
    pack(sys.argv[1], sys.argv[2])
```

调用：`python pack_fla.py <extracted_root> <out.fla>`

### 4.3 完整流程

```powershell
# 1) 备份
Copy-Item original.fla original_BACKUP.fla

# 2) 解包到临时目录
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory(
    "original.fla", "C:\temp\fla_fixed")

# 3) 剥离损坏项
python fix_rig.py C:\temp\fla_fixed\LIBRARY

# 4) 重打
python pack_fla.py C:\temp\fla_fixed C:\temp\original_FIXED.fla

# 5) 用 Animate 打开 _FIXED.fla,第一次保存即重建剩余缓存
```

---

## 5. 验证修复成功的检查点

- 解包后 `mimetype` 应当是第一条 entry，长度 25，STORED
- `LIBRARY/**/*.xml` 中再正则搜 `rigPropagationMatrix='\{[^}]*-?2147483648` 应当 0 命中
- Animate 打开后跳到原本歪斜的元件最后一帧，坐标轴恢复正交
- 能正常框选/拖拽
- 第一次 Ctrl+S 不再弹「无法另存」对话框

本次实例修复后 922 条损坏属性全清，原 277 个 ZIP entry 数保持不变，文件从 8,519,469 B 压到 8,456,204 B（净减约 63 KB）。

---

## 6. 预防

1. **已挂 Warp Rig 的元件，避免大角度（>180°）+ 大缩放（>3×）反复 motion tween 编辑**——这是触发 16.16 累积溢出的标准路径
2. 视图首次出现轻微歪斜苗头**立刻 Ctrl+Z 撤销，不要继续保存**——一旦保存，污染随相邻补间扩散到其它帧/层，难以局部回退
3. 定期对重要的 rig-heavy FLA 跑一次「健康检查」：解包后 grep `LIBRARY/**/*.xml | rigPropagationMatrix.*-?2147483648`，0 命中即健康
4. 不要把这个失败模式与「FLA 文件本身损坏」混淆——ZIP 结构、`<Matrix>` 浮点串、`bin/` 缓存通常完好；只有这一项整数缓存爆了

---

## 7. 关键事实速查

- `rigPropagationMatrix` ≠ `<Matrix>`：前者整数缓存可丢，后者浮点权威不可丢
- 16.16 定点：值 `65536` = 缩放 `1.0`，值 `-2147483648` = `INT32_MIN` = 已饱和
- Animate FLA 是 ZIP；`mimetype` 必须首条且 STORED
- FLA 中文文件名解包**只能**用 .NET API，Info-Zip 系工具会乱码
- 修复脚本是「按需」修复，未受损的 rig 帧 100% 保留
