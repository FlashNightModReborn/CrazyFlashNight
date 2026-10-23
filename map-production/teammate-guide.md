# 组员接入与固定提示词

## 1. 一次性准备

1. 安装 Qoder，登录可用账号。
2. 克隆仓库；网络慢时允许浅克隆，但上传前确认工作树完整：

```powershell
git clone --depth 1 https://github.com/FlashNightModReborn/CrazyFlashNight.git
cd CrazyFlashNight
```

3. 用 Qoder 打开仓库根目录，不要只打开 `flashswf/` 或 `map-production/`。
4. 模型选 DeepSeek-Flash，思考强度拉到最大，上下文开到 400k。
5. 如果本机有 Flash CS6，确认 `scripts/setup_compile_env.bat` 已按管理员权限跑过，CS6 正在运行；没有 CS6 也可以接任务，但只能交 XFL，结果标 `pending_publish`。
6. 先读三份文件：
   - `map-production/README.md`
   - `map-production/map-standard.md`
   - `map-production/stage-inventory.md`

## 2. 每次会话开始

```powershell
git pull --ff-only
```

然后按 `map-production/README.md` 的领取规则，立刻领一个任务并推送 claim。不要先画图再领；不要一次领多个任务。可以用 `python tools/map-production/next_task.py` 看下一个可领取任务，但它不会替你创建 claim。

## 3. 固定提示词

把下面整段原样粘贴给 Qoder。把第一行的名字换成组员自己的名字。

```text
你是 CrazyFlashNight 地图生产组员，名字是【你的名字】。工作区是当前打开的 CrazyFlashNight 仓库根目录。

每次会话开始，先执行 git pull --ff-only 拉取最新代码；拉不动就停下来报告网络问题，不要用旧基线硬改。然后读 map-production/README.md、map-production/map-standard.md、map-production/stage-inventory.md 和 map-production/tasks.json。

你的任务只有一个：按 map-production/README.md 的领取规则，立刻领取一个 claimable 的任务，创建 map-production/claims/<task-id>.json，只提交这个 claim 文件并立刻推送到远端。推送被拒时先 fetch；如果远端同一任务已被别人领取，删除自己的 claim，让位给远端，pull 后立刻重新领；不要覆盖远端 claim，不要 reset --hard，不要 force push。claim 推送成功后才开始工作。

工作内容是按 map-standard.md 为一个关卡做 3–5 张主图（主线默认 5 张，短副本 3 张起），交付到 map-production/packages/<task-id>/。必须先写 design.md，再画图；没有设计思路时先基于旧图写一致的设计说明。地图只能用 Flash CS6/XFL 的矢量绘制或拼装，禁止使用 ImageGen 或任何第三方生图工具，也不生成 AI 概念图；需要生图时停下报告。每张图要有可编辑的 SVG/XFL 矢量源、发布后的 SWF、裁边预览和接触表；同时写 install.json、manifest.json 和 environment.proposal.xml。不要新建或修改任何关卡 XML、stage_environment.xml、stage-select 配置或任务数据；本阶段只交地图资源，不做关卡实装。

有 CS6 就用真实 CS6 发布并检查首帧 _root.贴背景图();；没有 CS6 就交 XFL，结果标 pending_publish，不能标完成。每完成一个地图组，创建 map-production/results/<task-id>.json，提交任务包和结果，然后立刻领下一个任务，不要停下来总结。按优先级先做主线诺亚、雪山、雪山内部，再做大学二期、将军/丽丽丝、余烬、剑术大师。

如果任务资料不足、设计无法确定、或需要修改本批范围，创建 blocked 结果并删除自己的 claim，写清原因，然后换下一个任务。不要碰别人的改动，不提交 review/、截图、FFDec 导出、FLA 或临时文件。不要因为“已经有一个阶段完成”就停止；一直领到没有可领取任务为止。收到“继续”就重新拉取、重新领取并接着跑。

开始前先报告：当前 HEAD、你领到的 task id、任务标题、关卡、地图数、参考关。然后直接开工。
```

## 4. 交付检查

提交前逐项确认：

- claim 是自己创建并已推送。
- `design.md` 已写，5 图顺序和左右出口成立。
- 每张图有可编辑的 SVG/XFL 矢量源，没有使用生图或整层栅格化。
- XFL 首帧只有 `_root.贴背景图();`。
- SWF 已发布；没有 CS6 则标 `pending_publish`。
- 预览已按透明边裁切，接触表可读。
- `install.json`、`manifest.json`、`environment.proposal.xml` 齐全。
- 没有修改关卡、环境总表、选关、任务数据。
- `results/<task-id>.json` 已写，状态是 `reviewed` 或 `pending_publish`。
- 只提交自己的任务包、claim/result 和自己的日志。

## 5. 冲突和停止

- claim 冲突：远端赢，本地让位，重新领。
- 代码冲突：只合并自己的任务包和 claim/result；不碰别人的地图、日志和未跟踪文件。
- 设计冲突：写 `blocked`，说明缺什么，不猜剧情。
- 所有任务都被领走或只剩 blocked/draft：停止领取，报告剩余数量和阻塞原因，不要抢别人的任务。
