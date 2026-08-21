# C# / Web 字体目录

`fonts/` 是 C# / Web 运行时字体的唯一人类维护入口。Gate E 已完成：`fonts.xml` 是 runtime authority，Web 与 Native HUD 都只消费语义 role，打包层只收常驻资产并排除整个临时目录；Flash / AS2 / FLA / XFL 不在本合同内。

## 最省事的试用流程

1. 把 TTF / OTF / WOFF / WOFF2 放进 `temporary/custom/`。文件名要与 `fonts.xml` 中目标 asset 的 `file` 相同；整个 `temporary/` 都不会进入 Git。
2. 若是新字体，在 `fonts.xml` 增加 asset、face 和下载信息；业务处只改 role 或 preset 的 `<use face="..."/>`，不要修改 CSS/C# 字体族名。
3. 运行：

   ```powershell
   node tools/fontctl/cli.js validate
   node tools/fontctl/cli.js scan
   node tools/fontctl/cli.js generate
   node tools/fontctl/cli.js resolve --role web.intelligence.title --explain
   ```

4. Web 页面重开即可重新取字体；Native 字体选择按进程冻结，修改后重启游戏。

文案可以直接维护 XML/JSON，不需要 Electron 工具、编译 C# 或理解物理 family。普通映射变化只改 XML并重生成投影。

## 目录

```text
fonts/
  fonts.xml                    # asset → face → role → preset/context 真源
  fonts.xsd                    # 人类可编辑结构约束
  licenses/                    # 随常驻字体分发的许可证/版权声明
  permanent/runtime/           # 版本化常驻字体
  temporary/                   # 整体 gitignored
    custom/                    # 文案、开发者、玩家手工覆盖
    cache/                     # 下载器唯一写入位置
    generated/                 # 可删除的本地报告（预留）
```

运行时来源顺序固定为：

```text
temporary/custom → temporary/cache → permanent/runtime → system/generic fallback
```

custom 仍要通过格式/容器探针；cache 与 permanent 必须精确匹配 XML 的 bytes 和 SHA-256。下载只写唯一 staging，验证后再原子发布到 cache；网络、损坏文件或缺字都不能阻断游戏启动。

## 常驻与按需集合

当前只把两项高频、离线价值明确的字体设为 `residency="permanent"`：

| asset | 用途 | 大小 |
|---|---|---:|
| `jetbrains-mono` | Web terminal、动态 Canvas 等宽文本 | 92,380 bytes |
| `source-han-serif-cn-regular` | 情报档案正文、Native HUD 中文 | 11,626,108 bytes |

重黑标题、文楷与手写体共 12 项保持 `on-demand`，由 `fontctl sync` 或 Launcher FontPack 下载到 cache。`validate` 会拒绝常驻文件缺失、哈希漂移、未登记字体或把 on-demand 文件误放进 permanent。

两项常驻字体均按 SIL Open Font License 1.1 分发，版权声明和完整许可文本位于 `licenses/`。许可证字段只记录工程事实，不替代发行前法律复核。

## 语义隔离

消费者使用 `web.intelligence.title`、`web.task.title`、`native.hud.body`、`native.combat.number` 等 role，不直接使用 “思源宋体” 或 “JetBrains Mono”。情报的整篇风格使用 `intelligence.diary`、`intelligence.weary` 等 preset；多个 preset 按传入顺序叠加，后者覆盖前者。

raw family 只允许作为以下显式边界留存：

- `compatibility`：例如旧 tooltip 数据的 `MS Mincho` / `Fixedsys`，进入 Web 前映射到 legacy role；
- `system-owned`：操作系统或 CSS generic fallback；
- `path-glyph`：PlayerInfo 等程序化路径字形；
- `migrate`：迁移债务，Gate E 生产审计必须为零。

## 生成物与命令

`node tools/fontctl/cli.js generate` 从 XML 确定性生成：

- `launcher/web/generated/font-catalog.json`：Host/Web 共享规范化投影，并绑定 XML SHA-256；
- `launcher/web/generated/font-catalog.css`：`@font-face` 与 role CSS 变量；
- `launcher/web/generated/font-catalog.js`：role、preset、Canvas、预热和 compatibility API；
- `launcher/web/assets/fonts/font-pack-manifest.json`：旧 Bootstrap FontPack 协议所需的 XML 同源兼容投影。

提交前使用 `generate --check` 拒绝漂移。完整命令、退出码和验证入口见 [`tools/fontctl/README.md`](../tools/fontctl/README.md)。

## 边界

- `launcher/web/assets/fonts/` 只容纳由 `fontctl generate` 维护的兼容 manifest，不得再放字体二进制或手写第二份 inventory。
- 旧 `%LOCALAPPDATA%/CF7FlashNight/fonts/` 导入路径已退役；运行时只解析根目录的 `custom → cache → permanent`。
- `runtime-fonts` 打包层收录 XML/XSD、许可证、README 和 `permanent/runtime/`，严格排除 `temporary/**`。正式部署状态只以 runtime consensus 与标准入口证据为准。
- `闪7重置版字体/`、Flash、AS2、FLA、XFL 明确不扫描、不迁移、不新增工具投资。
