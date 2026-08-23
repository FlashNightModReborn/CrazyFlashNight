# FontPack 生成兼容目录

本目录不是 C# / Web 字体映射真源，也不存放字体二进制。Gate E 起，字体资产、下载来源、语义 role 与 preset 统一维护在 [`fonts/fonts.xml`](../../../../fonts/fonts.xml)；Web 投影和本目录的 `font-pack-manifest.json` 均由 `node tools/fontctl/cli.js generate` 从 XML 确定性生成。

`font-pack-manifest.json` 只服务现有 Bootstrap FontPack UI/协议。它携带 schema、Gate、生成器与 XML SHA-256，`generate --check`、Host 启动校验和 production closure 会拒绝漂移，因此不构成第二份人工 inventory。

不要在这里添加字体、role、下载地址或手工修改 manifest。普通维护流程见 [`fonts/README.md`](../../../../fonts/README.md)；运行时通过 exact-set `cfn-fonts.local` handler 按 face-major（每个 face 内 `temporary/custom → temporary/cache → permanent/runtime`）提供 XML 已声明的文件，并复用已验证 byte snapshot。

旧 `jetbrains-mono.woff2` Web 副本已删除，唯一受版本控制的常驻副本位于 [`fonts/permanent/runtime/`](../../../../fonts/permanent/runtime/)。随包许可证位于 [`fonts/licenses/`](../../../../fonts/licenses/)。Flash / AS2 / FLA / XFL 与 `闪7重置版字体/` 始终不在本目录迁移范围内。
