# 地图生产任务台

这是本批次地图生产的唯一任务入口。任务定义在 `tasks.json`，人类可读关卡清单在 `stage-inventory.md`，制作规范在 `map-standard.md`，绘制流程与守则在 `map-drawing-sop.md`。

> 本流程暂不写入 `AGENTS.md`，不做全局自动注入。等流程跑通后，由用户明确指示其他 Qoder 阅读本文件；在此之前不要把本文件加进 `AGENTS.md` 路由。

**当前进度**：任务台、规范、SOP、校验和矢量转换工具已建立；第一轮样张已按 SOP 重绘，改用现有地图的复用元件替换简笔装饰，产物仍在 `tmp/map-production-draft/ML-NOAH-005/`（已忽略，不入库），等待人工复核。流程确认后再按领取协议正式建包。

**当前范围**：只做没有任务、且没有重置过的战斗关卡地图。已有任务、已重置关卡、所有二层、地下2层、异界战场、坠毁战舰、亡灵沙漠、沙漠虫洞、旧副本、外交据点、地铁站深处全部不做。

## 目录

```text
map-production/
  README.md                  # 本文件：任务台与领取协议
  map-standard.md            # 地图资产、环境片段、审阅和安装契约
  map-drawing-sop.md         # 取证、复用、新绘细度、图层与验收流程
  stage-inventory.md         # 人类可读的关卡清单与优先级
  tasks.json                 # 静态任务定义，只由维护者更新
  claims/<task-id>.json      # 当前领取，一个任务一个文件
  results/<task-id>.json     # 完成/阻塞结果，一个任务一个文件
  logs/<agent>.md            # 每个组员自己的日志，一人一个文件
  packages/<task-id>/        # 地图交付包
```

不要新建第二份任务状态表。状态由 `claims/` 和 `results/` 派生；`tasks.json` 只描述任务本身，不写“谁在做”。

## 领取规则

1. 先拉最新：`git pull --ff-only`。拉不动就停下来报告网络问题，不用旧基线硬改。
2. 读 `tasks.json`，按 `priority`、`wave`、`id` 顺序找第一个 `claimable: true`、没有 `claims/<id>.json`、没有完成结果的任务。
3. 立刻创建 `claims/<id>.json`：

```json
{
  "taskId": "ML-NOAH-005",
  "agent": "你的名字",
  "startedAt": "2026-10-20T21:00:00+08:00",
  "branch": "map/ML-NOAH-005",
  "status": "claimed",
  "packageDir": "map-production/packages/ML-NOAH-005"
}
```

4. 只提交这个 claim 文件并立刻推送。提交信息用：`claim: ML-NOAH-005 诺亚-指挥部大厅`。
5. 推送被拒时：
   - 先 `git fetch origin`，再看远端同一 claim 文件。
   - 远端已有别人领取：删除自己刚建的 claim 文件，`git pull --ff-only`，立刻重新选任务。不要覆盖远端领取，不要 `reset --hard`。
   - 远端只是别的任务/别的文件更新：正常合并或 `git pull --ff-only` 后重推自己的 claim。
6. claim 推送成功后，才开始写 `design.md` 和地图。

## 做完和放弃

完成后创建 `results/<id>.json`：

```json
{
  "taskId": "ML-NOAH-005",
  "agent": "你的名字",
  "status": "reviewed",
  "branch": "map/ML-NOAH-005",
  "packageDir": "map-production/packages/ML-NOAH-005",
  "commit": "<提交哈希>",
  "checks": {
    "design": true,
    "swf_published": true,
    "preview_reviewed": true,
    "environment_proposal": true,
    "no_stage_or_env_edits": true
  },
  "notes": "5 图已发布，环境建议片段已写；等待人工复核。"
}
```

允许的 `status`：

- `reviewed`：地图组已完成并通过自审；还没进关卡。
- `blocked`：设计或资料不够，写清阻塞原因；同时删除自己的 claim，让任务重新可领。
- `pending_publish`：没有 CS6，XFL 已交但 SWF 未发布；不算完成。

完成结果只提交 `results/<id>.json` 和任务包，不改 `tasks.json`。人工复核通过后另开安装/实装任务。

## 日志

每个组员只写自己的 `logs/<agent>.md`，不碰别人的日志。建议每次只追加：

```text
## 2026-10-20 21:00 ML-NOAH-005
- 领取，读了旧图和规范。
- 5 图顺序：前厅 / 值班廊 / 指挥大厅 / 通讯档案 / 撤离通道。
- 待定：地图 3 的二层平台碰撞。
```

## 任务选择顺序

1. 主线诺亚 15 关（`ML-NOAH-*`）。
2. 主线雪山 12 关（`ML-SNOW-*`）。
3. 主线雪山内部 12 关（`ML-SNOWIN-*`）。
4. 大学二期 8 个地图组（`SQ-UNIV-*`）。
5. 将军/丽丽丝 4 个地图组（`SQ-GEN-*`、`SQ-LILITH-001`）。
6. 余烬 15 个可领取地图组；`SQ-EMBER-016` 是待设计草稿，暂不领。
7. 剑术大师 1 个地图组（`SQ-SWORD-001`）。

全部可领取任务都被领走时，停止领取并报告，不要抢别人的 claim。

## 工具

```powershell
# 看下一个可领取任务
python tools/map-production/next_task.py

# 校验某个任务包的结构（不检查美术质量）
python tools/map-production/validate_package.py ML-NOAH-005

# SVG 矢量源转 XFL（会在 background-bake 层注入首帧脚本，并生成 PublishSettings）
python tools/map-production/svg_to_xfl_map.py <源.svg> <输出目录> --name <地图名>
```

`next_task.py` 只读，不创建 claim；claim 仍按上面的协议手动创建并推送。


## 地图组工作顺序

1. 读 `map-standard.md` 和任务对应参考关。
2. 写 `design.md`：5 图顺序、地标、出口、碰撞和参考图。
3. 做 XFL 和 SWF。
4. 生成裁边预览和接触表。
5. 写 `install.json`、`manifest.json`、`environment.proposal.xml`。
6. 自审：没有改关卡、环境总表、选关和任务数据。
7. 提交任务包和 `results/<id>.json`。

## 禁止

- 不使用 ImageGen 或任何第三方生图工具生成正式地图或概念图。
- 不修改 `data/stages/**`、`data/environment/stage_environment.xml`、`launcher/web/modules/stage-select-data.js`、`data/task/**`。
- 不提交 `review/`、截图、FFDec 导出、FLA、临时 SWF。
- 不整图复制旧图，不把换色当重制。
- 不覆盖别人的 claim，不删除远端 claim，不 force push。
- 不把“已编译”说成“已进关卡”；本阶段没有 runtime 验收。
