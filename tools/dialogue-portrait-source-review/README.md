# 对话立绘同名双源复核页

这个工具从当前三份事实源自动求交集：

- `flashswf/portraits/list.xml` 中会被 Flash 对话框优先加载的外部肖像；
- `flashswf/UI/对话框界面/LIBRARY/对话框肖像.xml` 中的内嵌时间轴标签；
- `launcher/web/assets/dialogue-portraits/manifest.json` 中 Web 当前实际采用的来源。

它优先读取 `launcher/web/assets/dialogue-portraits/{external,internal}` 中的生产 PNG；权威裁决后已从生产闭包清除的落选源，则读取完整烘焙留下的 `tmp/dialogue-portrait-source-review/candidates/` 忽略提交缓存。两份预览会嵌入一个可离线打开的 HTML，供维护者逐项选择权威源、备注、暂缓和导出 JSON。页面不会修改 manifest、PNG、SWF 或 XFL；导出的 JSON 也只是后续修复的输入证据。

## 生成与使用

```powershell
node tools/dialogue-portrait-source-review/build-review.js
```

生成文件位于：

```text
tmp/dialogue-portrait-source-review/review.html
```

直接用浏览器打开即可。浏览器允许本地存储时，选择会按当前 `sourceDigest` 保存在 localStorage；源文件或预览 PNG 变化后，新页面使用新的存储键，不会静默沿用旧批次选择。页面支持导出阶段性或完整的 `cf7.dialogue-portrait-source-authority-decisions.v1` JSON，并会在导入时拒绝来源闭包不匹配的旧文件。

## 校验

```powershell
node --check tools/dialogue-portrait-source-review/build-review.js
node --check tools/dialogue-portrait-source-review/test-review.js
node tools/dialogue-portrait-source-review/test-review.js
node tools/dialogue-portrait-source-review/build-review.js --check
```

`--check` 只确认已经生成的 HTML 与当前源闭包完全一致，不会重写文件。`tmp/` 仍是本地工作产物，不应提交。

## 范围边界

这里审计的是会共同进入 dialogue portrait manifest 的两类来源。`launcher/web/assets/profiles/` 的任务卡缩略图属于另一条消费链，不被计作第三个权威源。此工具也不会自动根据“Flash 当前”标签代替人作选择。

## 应用裁决

复核完成后，将完整决策转录到同目录的 `authority-policy.json`。生产烘焙器会逐名读取这份策略；新增同名项没有明确裁决、策略含已经消失的旧项、最终 manifest 没有采用所选来源，或碰撞报告不完整时都会失败。内嵌肖像的 SWF character ID 从当前 `ExportAssetsTag` 动态解析，不再依赖易漂移的硬编码 ID。

烘焙器还会把烘焙前的现有输出作为语义基线：内嵌肖像只有外围全透明画布发生变化、alpha 包围盒与可见 RGBA 完全一致时，复用既有 PNG，避免无视觉变化的 Git 二进制膨胀。权威裁决完成后，磁盘 PNG 集合会被收敛到 manifest URI 精确集合，落选来源不会残留为死资产；完整烘焙会把这些落选预览另存到上述 `tmp` 缓存，以便后续复核。需要显式指定另一份已验证基线时使用 `--semantic-baseline-dir <dir>`；该参数只影响 no-op 复用，不覆盖权威源裁决。

应用前先运行：

```powershell
python tools/test-dialogue-portrait-authority.py
```

然后按 `agentsDoc/testing-guide.md` 的 Dialogue Portraits 行执行完整候选与正式烘焙。更新策略本身不代表生产 manifest 已刷新。
