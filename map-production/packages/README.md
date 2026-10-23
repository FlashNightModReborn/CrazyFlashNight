# 地图交付包

每个任务一个目录：`map-production/packages/<task-id>/`。

必需文件：

- `design.md`
- `install.json`
- `manifest.json`
- `environment.proposal.xml`
- `maps/<map-name>/<map-name>.xfl`（CS6 入口标记；同目录含 `DOMDocument.xml` 和 `LIBRARY/`）
- `maps/<map-name>.swf`

`review/` 只放本机预览和接触表，已被 gitignore。没有 CS6 时，`maps/` 可以先只有 XFL，并在结果里标 `pending_publish`。
