# things.xfl A类符号重命名冲突报告

## 处理结果

- **已重命名**: 690 个 A 类符号（从 `Symbol NNN` 改为 `linkageIdentifier`）
- **`DOMDocument.xml` 修复**: 690 处 `Include` 引用已同步更新
- **`asset_source_map.xml`**: 已重新生成
- **剩余冲突**: **16** 个（含 1 个真正的 linkageId 交换 + 15 个储备符号）

---

## 1. 真正的 linkageId 交换冲突（需 Flash CS6 手动处理）

### `1.枪械相关/长枪/Symbol 3710`

- **旧 A 类文件**: `1.枪械相关/长枪/Symbol 3710.xml`
  - `name`: `1.枪械相关/长枪/Symbol 3710`
  - `linkageIdentifier`: `图标-M202火箭发射器`
- **目标文件已存在**: `1.枪械相关/长枪/图标-M202火箭发射器.xml`
  - `name`: `1.枪械相关/长枪/图标-M202火箭发射器`
  - `linkageIdentifier`: `图标-M134`
- **问题**: 两个符号的 linkageIdentifier 似乎被历史性地交换了（copy-paste 错误）。
- **建议**: 在 Flash CS6 中打开 `things.fla`，检查这两个符号的内容和 linkageIdentifier，手动修正。

---

## 2. 储备符号冲突（保留原文件，暂不处理）

以下 15 个 `废弃NPC套装` 目录下的符号已从 Git 恢复并保留。它们**无外部引用、不在 `DOMDocument.xml` 中**，但作为储备资源以防将来有用。由于目标文件名已被占用，暂时无法自动重命名：

| 旧文件 | linkageIdentifier | 目标文件已存在 |
|--------|-------------------|----------------|
| `废弃NPC套装/Symbol 3563.xml` | `图标-pig装墨绿军用下装` | ✅ |
| `废弃NPC套装/Symbol 3564.xml` | `图标-pig装墨绿军用鞋` | ✅ |
| `废弃NPC套装/Symbol 3569.xml` | `图标-pig装牛皮手套` | ✅ |
| `废弃NPC套装/Symbol 3573.xml` | `女装-pig装警装帽子` | ✅ |
| `废弃NPC套装/Symbol 3575.xml` | `女装-pig装警装上装` | ✅ |
| `废弃NPC套装/Symbol 3577.xml` | `女装-pig装警装下装` | ✅ |
| `废弃NPC套装/Symbol 3579.xml` | `女装-pig装警装下装` | ✅ |
| `废弃NPC套装/Symbol 3581.xml` | `女装-pig装头` | ✅ |
| `废弃NPC套装/Symbol 3582.xml` | `女装-pig装墨绿军用帽` | ✅ |
| `废弃NPC套装/Symbol 3584.xml` | `女装-pig装墨绿军用屁股` | ✅ |
| `废弃NPC套装/Symbol 3586.xml` | `女装-pig装墨绿军用小腿` | ✅ |
| `废弃NPC套装/Symbol 3587.xml` | `女装-pig装墨绿军用左大腿` | ✅ |
| `废弃NPC套装/Symbol 3588.xml` | `女装-pig装墨绿军用右大腿` | ✅ |
| `废弃NPC套装/Symbol 3590.xml` | `女装-oldpig装帽子` | ✅ |
| `废弃NPC套装/Symbol 3591.xml` | `女装-oldpig装帽子` | ✅ |

> **注意**: 这些符号的 `linkageIdentifier` 和目标文件名之间也可能存在历史 copy-paste 错误，需要将来在 Flash CS6 中统一核查。目前保留原 `Symbol` 文件名，不影响现有库的编译。
