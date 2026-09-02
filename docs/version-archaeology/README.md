# 版本考古与更新记录证据规范

**文档角色**：历史版本证据、玩家向更新记录和后续更新视频脚本的维护规范。

**最后核对代码基线**：commit `7db6e154276176e1f46744847615c21b43b3abed`（2026-08-30）。

这里保存逐版本的考古记录。启动器中的当前版本号仍由
`launcher/web/config/version.js` 提供；本目录不是第二份运行版本号真源。

## 必须分开的四件事

| 事实 | 能证明什么 | 不能自动证明什么 |
|---|---|---|
| 公开前瞻视频 | 当时公开展示或说明过某项内容 | 视频发布当日已有稳定包，或展示内容全部进入源码 |
| 找回的视频制作稿 | 当期制作团队计划讲解、录制的条目、专名与限制语 | 公开视频实际逐字说法，或稿内条目已经进入源码/稳定包 |
| 源码提交 | 某项改动已经进入对应 Git 提交 | 玩家已经收到该改动，或该提交就是稳定发包 |
| 稳定发包锚点 | 某个标签、整包、校验值或正式发布记录对应玩家包 | 相邻提交区间内每项改动都属于该包，除非能够继续核验 |

历史记录只写证据能够支持的强度。不得把“前瞻展示”“进入源码”和“稳定发包”
合并成一个模糊的“已更新”，也不得补造不存在的中间版本号。

## 单版本记录结构

每份 `versions/*.md` 固定包含：

1. **状态摘要**：视频、转写、源码区间和稳定发包边界分别是什么状态。
2. **玩家向草稿**：只放已有直接证据的功能条目；每条都带来源和时间码或提交。
3. **证据台账**：记录原始来源、观察方式和证据边界。
4. **未知项**：列出仍需转写、旧仓库、整包或人工核字才能解决的问题。
5. **视频脚本素材**：把可复用的章节顺序与镜头锚点保留下来，但不把草稿冒充发包文案。

状态词保持小而明确：

- `preview_visual_verified`：公开视频画面或画面文字已复核。
- `video_script_recovered`：找回的当期视频制作稿已逐页核对；它仍不是公开音轨逐字稿。
- `preview_transcript_verified`：完整音轨或公开字幕已经带时间戳复核。
- `pending_transcription`：尚无可用的完整转写；不得根据简介补功能。
- `source_verified`：有具体提交和 diff 支持“进入源码”。
- `release_verified`：有稳定包、标签或等价发布锚点支持“交付给玩家”。
- `unknown`：现有材料不能回答。

## 低负载取证顺序

默认从最小网络和计算成本开始：

1. 读取 Bilibili `view`、`player/v2` 和合集元数据，取得标题、日期、时长、
   `aid`、`cid`、公开字幕与章节。简介只作为简介证据。
2. 若没有字幕，先取 `videoshot` 故事板。它通常远小于完整视频，并可直接证明
   画面标题、章节卡和被展示的界面；故事板索引必须逐条核验，不能默认等间隔。
3. 如果维护者找回原视频制作稿，先核对文件摘要、OOXML 元数据、页数、修订/批注和配图，
   再把玩家条目与“待定、未完善、仅修改器可见”等限制语提炼进单版本记录。原始大体积
   DOCX 不因被找回就自动入库，除非另行满足仓库二进制资产治理。
4. 只有故事板和制作稿仍不足以回答时，才取最低码率音轨到系统临时目录。媒体、模型缓存和
   中间 WAV 不进入仓库。
5. 机器转写只是草稿。人名、专有名词、数值和否定句必须回到音轨或画面二次核验，
   之后才能标记 `preview_transcript_verified`。
6. 最后再映射 Git。提交时间早于或晚于视频都不能单独推出发包边界。

以下命令展示元数据和最低码率音轨的取得方式。播放地址带短期签名，不写入文档：

```powershell
chcp.com 65001 | Out-Null
$bvid = 'BV1iU2WYnEPj'
$cid = '26202998308'
$headers = @{
    'User-Agent' = 'Mozilla/5.0'
    'Referer' = "https://www.bilibili.com/video/$bvid"
}

$view = Invoke-RestMethod -Headers $headers `
    -Uri "https://api.bilibili.com/x/web-interface/view?bvid=$bvid"
$player = Invoke-RestMethod -Headers $headers `
    -Uri "https://api.bilibili.com/x/player/v2?bvid=$bvid&cid=$cid"
$play = Invoke-RestMethod -Headers $headers `
    -Uri "https://api.bilibili.com/x/player/playurl?bvid=$bvid&cid=$cid&fnval=16&qn=16"
$audio = $play.data.dash.audio | Sort-Object bandwidth | Select-Object -First 1

$archaeologyTemp = Join-Path ([IO.Path]::GetTempPath()) `
    ('cf7-version-archaeology-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $archaeologyTemp | Out-Null
$audioPath = Join-Path $archaeologyTemp 'source-low.m4a'
Invoke-WebRequest -Headers $headers -Uri $audio.baseUrl -OutFile $audioPath
ffmpeg -hide_banner -loglevel error -i $audioPath `
    -ar 16000 -ac 1 -c:a pcm_s16le `
    (Join-Path $archaeologyTemp 'source-16k-mono.wav')
```

## 轻量维护契约

版本记录与更新视频提纲在以下两个节点维护，不引入逐提交填表：

1. **稳定发包**：创建或更新 GitHub Release 的同一发包批次，必须更新
   [稳定发包边界](release-boundaries.md)、对应 `versions/<version>.md` 和
   [系列索引](series-index.md)。至少记录 Release URL、标签、发布时间、资产名/大小、
   3–8 条玩家变化与一份可录制的视频提纲。
2. **玩家可见更新提交**：当一个功能列车完成、准备对外称为“本次更新”时，在当前开发版本
   记录中追加玩家变化、代表提交和分镜。相关的多次 WIP/修复提交可在收口提交一次批量登记，
   不要求每个中间提交分别维护文档。

纯重构、测试、文档、构建、签名、部署 receipt 或不改变玩家体验的修复，不单独生成更新条目；
如果它们最终支撑一个玩家可见功能，只由该功能的收口记录统一引用。这个契约维护内容真源，
不创建新的发包状态机、逐字验收或额外人工门。

## 发布到玩家页面前的检查

- 玩家能否看出这条是“前瞻展示”“源码进入”还是“稳定交付”。
- 每个确定陈述是否至少有一个可回到原始材料的锚点。
- 是否把视频标题、简介或提交标题误当成完整更新清单。
- 是否因为旧仓库缺失而猜测提交区间。
- 是否把开发阶段号或 E 阶段展开规则倒推到过去不存在的版本。

## 当前记录

- 稳定包边界：[GitHub Releases 稳定发包边界](release-boundaries.md)
- 汇总入口：[2.x 系列索引与玩家页投影](series-index.md)
- 单版本证据：[2.0](versions/2.0.md)、[2.2](versions/2.2.md)、
  [2.3](versions/2.3.md)、[2.4](versions/2.4.md)、[2.45](versions/2.45.md)、
  [2.5](versions/2.5.md)、[2.6](versions/2.6.md)、[2.65](versions/2.65.md)、
  [2.66](versions/2.66.md)、[2.7](versions/2.7.md)、[2.71](versions/2.71.md)、
  [2.718](versions/2.718.md)

合集目前没有 2.1 更新前瞻，因此索引保留缺口。新增版本时先建立单版本证据，再更新系列索引；
播放器历史页与更新视频都从同一份已核验证据投影，避免各自维护一套文案。
