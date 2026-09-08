# 物品素材工作台

游戏入口：**其他 → 工具 → 物品素材工作台**。画师使用 Web 界面，Agent 使用 `cli.py`；二者调用同一个 `core.py`，共享选择、导出、校验、应用和撤回行为。

## 画师与 Agent 共用帮助

在工作台标题栏点 **帮助**，阅读“画师上手 / Agent 协作 / 常见问题”。页面与仓库共用 [同一份操作指南](../../launcher/web/help/asset-workbench.md)，不另维护一套界面文案；本文件负责环境与实现契约。

帮助内可复制 CLI 示例或当前物品、来源 SWF、任务 ID 与日志目录。返回按钮或 Escape 回到原工作台并保留选择；“关闭工作台”结束面板。阅读帮助期间暂停预览动画，返回后恢复；已经开始的后台任务继续。

真实画师负责完成自己素材的生成、对比、应用与实际场景体验。Agent 负责诊断、修复和机器回归，技术测试不代替画师实操验收。新增素材体验仍可用 **3XD的素材.swf** 中的大赦、mini14、杠杆式霰弹枪。

工作台使用游戏面板的完整可用区域，以共享的 `1024×576` 逻辑画布等比缩放；不保留普通弹窗的四周边距。

目录采用连续滚动，底部仅显示筛选后的总件数。目录变化时批量更新文字行；选中物品或刷新任务状态只更新选择标记，保留滚动位置与焦点。目录、帮助正文和诊断区滚动条复用工作台配色，不增加滚动轮询。

本轮支持工作台内部的显式预览刷新。**自动监听发布、刷新其他消费者缓存、CS6 发布包装均不在范围内**。已打开的其他面板或 NativeHud 可能仍使用旧缓存；需要验证它们时重新启动游戏。工作台不读写游戏存档。

## 环境

- Windows，Python **3.11+**，安装本目录 `requirements.txt` 中的 Pillow。
- 项目中的 `tools/ffdec/ffdec.bat` 和 `ffdec.jar`，以及 Java 8 或更新版本；大图标库建议使用 64 位 Java。优先使用 `JAVA_HOME` / PATH，随后查找本机 Adobe Animate、Adoptium、Java、CS6 的 JRE；仅修改本次子进程的环境。64 位 Java 的 FFDec 堆上限默认 2 GB，32 位仍为 1 GB；保留显式 `FFDEC_MEMORY` 设置。这是导出期间的按需上限，不是常驻预留内存。
- 项目本身的物品 XML、来源索引、已发布 SWF 和现有 dressup 基础人物资源。首次构建完整基础资源仍使用离线 dressup 工具；工作台按物品增量导出。

Host 在标准用户 Python 安装目录和 PATH 中寻找 `python.exe`，排除 WindowsApps 商店占位程序。未安装依赖时，面板显示诊断并禁用生成。安装依赖示例：`python -m pip install -r tools/asset-workbench/requirements.txt`。

## 共享内核与文件边界

```text
物品 XML + 来源索引 + 已发布 SWF
              ↓
  GUI → Host 固定命令适配器 ─┐
  CLI ─────────────────────┴→ core.py
                               ↓
          离线图标 / dressup 导出器 + FFDec
                               ↓
       tmp 中的候选图片、报告、生成前后预览
                               ↓ 显式应用
       icons / dressup 图片、清单、来源索引
```

- 图标内核继续使用 `tools/bake-icons-offline.py`，装扮内核继续使用 `tools/bake-dressup-offline.py`；保留它们的 CLI 作为底层专项入口。旧 AS2 `IconBaker` / 位图分块传输 / C# `IconBakeTask` 及三个旧菜单已退役，`icon_bake` 不再注册。
- 图标导出包含动画帧。局部预览复用 `Icons.createPreview(host, entry, options)`，显式传入当前或候选条目；支持浏览器原生播放的动画 WebP、PNG 序列和独立计时的嵌套图层。不会替换全局图标清单或刷新其他消费者；切换素材和关闭面板会销毁预览、取消局部帧调度并卸载图片。
- 物品范围来自 `data/items/list.xml`，同时包含品质变体图标；来源冲突不自动选择。来源扫描生成本机候选索引，在应用素材时一并写入 canonical `data/items/asset_source_map.xml`。
- 候选绑定源 SWF、相关 XML、导出配方、来源索引和现有输出摘要；导出或应用前发现变化必须重新生成。图片、帧、有限数值注册点、导出报告与候选字节均需通过检查。
- 应用保留其他物品、技能以及嵌套动画图层。只清理本次所选项不再引用、且全清单也无人引用的旧图片，没有全目录 purge。
- 所有写入使用项目级互斥锁、逐文件原子替换与持久备份。发生进程/磁盘中断后，下一个写入操作恢复未完成事务；应用完成但状态尚未更新的任务会对账。生成进程退出可由“刷新任务”识别。任务 ID 可重复查询和提交同一选择，不可改绑其他物品。
- GUI 仅能发送 `catalog/rescan/start/status/apply/undo/cancel/close`，Host 验证来源、当前面板实例和精确字段，拒绝路径或命令注入。`asset-workbench.local` 只映射本机任务目录。关闭面板会释放请求回调、任务轮询和动画；没有常驻 watcher。
- 图标导出器对每次 FFDec 调用设 120 秒超时；Windows 超时时先结束批处理及其 Java 子进程树，使用临时文件收集输出，避免孤儿进程持有输出管道而一直等待。整个素材任务仍保留 15 分钟上限和显式取消。

## CLI

从项目根目录执行；标准输出是一条 UTF-8 JSON。`start` 返回后在独立进程导出，`bake` 等待生成结束，两者均只生成候选。

日常命令示例、GUI 对应表和画师反馈接续流程统一维护在 [共用指南的 Agent 协作部分](../../launcher/web/help/asset-workbench.md)。

`api` 从 stdin 接收 `{op,item?,kind?,jobId?}`。Host 使用此入口，不通过 shell 拼接参数。`start` 可提供一个 32 位小写十六进制 `jobId`，在请求结果未知时查询同一任务。

dressup 导出器增加可选 `--asset-map <索引快照>` 和 `--skip-basic-assets`。前者同时控制索引构建和实际导出查找；后者只跳过基础人体重复导出，仍导出所选装扮。原有调用的默认行为保持不变。

## 验证与本地体验

快速事务测试：`python -X utf8 -B tools/asset-workbench/test_core.py`。覆盖选择幂等、来源/输出/候选漂移、并发排斥、技能和嵌套引用保留、完整撤回、写入失败和中断恢复。原生请求边界测试为 `AssetWorkbenchTaskTests`，使用 Launcher 的 SDK 解析器运行。

图标播放回归：`node tools/test-icon-preview.js`、`node tools/test-asset-timeline.js`、`node tools/test-icons-layered-periods.js`；覆盖当前/候选 URL、静态首帧、序列停留时长、嵌套图层独立周期与裁切、销毁和全局清单隔离。

图标导出进程回归：`python -X utf8 -B tools/test-icon-process-timeout.py`；使用真实短期子进程验证退出码、UTF-8 输出、超时有界和 Windows 批处理子进程清理。导出器相关既有门为 `tools/test-icon-normalization.py`、`tools/test-icon-animation-candidate-filter.py`、`tools/test-icon-animated-budget.py`。

浏览器实测：`python -X utf8 -B tools/asset-workbench/dev_server.py`，打开 `http://127.0.0.1:18764/`。这个仅绑定回环的开发页使用生产面板容器、实际 GUI 和同一内核，会按显式按钮操作项目文件；不是假的成功响应。浏览器验证不等于游戏原生入口验收。

开发体验通过根目录 `本地开发启动.cmd` 启动，它调用现役 `automation/dev.ps1`，按当前源码身份复用或构建隔离候选，不依赖某台机器的临时目录。正式发布后，画师直接从平常的游戏入口进入 **其他 → 工具 → 物品素材工作台**。人的验收重点是图片是否正确、人物握持/注册点是否合理，以及操作是否顺手；候选构建和自动检查不能代替这部分判断。

本轮三步体验、已有验证、预备候选的基线限制和本机证据见 [体验交接](ACCEPTANCE.md)。
