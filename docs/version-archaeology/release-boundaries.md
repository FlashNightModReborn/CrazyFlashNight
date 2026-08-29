# GitHub Releases 稳定发包边界

**文档角色**：记录玩家可下载整包的一手发布证据。功能细目仍回到对应
`versions/*.md` 的视频与源码台账核验。

**核验日期**：2026-08-29

**一手来源**：[GitHub Releases 列表](https://github.com/FlashNightModReborn/CrazyFlashNight/releases)；
元数据通过 GitHub REST API 的公开 `releases` 端点逐项复核。

## 已核验整包

| 玩家版本 | GitHub Release | 发布时间（UTC+8） | 上传资产 | 标签所指提交 | Release 说明 |
|---|---|---:|---|---|---|
| 2.40 | [闪7重置计划 v2.40 整包](https://github.com/FlashNightModReborn/CrazyFlashNight/releases/tag/%E9%97%AA7%E9%87%8D%E7%BD%AE%E8%AE%A1%E5%88%92v2.40%E6%95%B4%E5%8C%85) | 2025-05-27 19:08:46 | `7.v2.40.7z`，354,981,956 bytes | `5b4238450d4702ebc69ce2acaaee022b2b031110` | 链接 2.4 更新视频 |
| 2.50 | [闪7重置计划 v2.50 整包](https://github.com/FlashNightModReborn/CrazyFlashNight/releases/tag/%E9%97%AA7%E9%87%8D%E7%BD%AE%E8%AE%A1%E5%88%92v2.50%E6%95%B4%E5%8C%85) | 2025-05-27 19:13:23 | `7.v2.50.7z`，396,892,255 bytes | `5b4238450d4702ebc69ce2acaaee022b2b031110` | 链接 2.5 更新视频 |
| 2.60 | [闪7重置计划 v2.60 整包](https://github.com/FlashNightModReborn/CrazyFlashNight/releases/tag/%E9%97%AA7%E9%87%8D%E7%BD%AE%E8%AE%A1%E5%88%92v2.60%E6%95%B4%E5%8C%85) | 2025-05-27 19:23:19 | `7.v2.60.7z`，511,383,204 bytes | `5b4238450d4702ebc69ce2acaaee022b2b031110` | 链接 2.6 更新视频 |
| 2.65 | [闪7重置计划 v2.65 整包](https://github.com/FlashNightModReborn/CrazyFlashNight/releases/tag/%E9%97%AA7%E9%87%8D%E7%BD%AE%E8%AE%A1%E5%88%92v2.65%E6%95%B4%E5%8C%85) | 2025-05-27 19:27:27 | `7.v2.65.7z`，619,141,837 bytes | `5b4238450d4702ebc69ce2acaaee022b2b031110` | 链接 2.65 更新视频 |
| 2.66 | [闪客快打7重置计划 2.66 整包](https://github.com/FlashNightModReborn/CrazyFlashNight/releases/tag/%E9%97%AA%E5%AE%A2%E5%BF%AB%E6%89%937%E9%87%8D%E7%BD%AE%E8%AE%A1%E5%88%922.66%E6%95%B4%E5%8C%85) | 2025-05-27 19:31:01 | `7.2.66.zip`，649,485,209 bytes | `5b4238450d4702ebc69ce2acaaee022b2b031110` | 直接列出 3 项修复 |
| 2.71 | [闪客快打7重置计划 2.71 整包](https://github.com/FlashNightModReborn/CrazyFlashNight/releases/tag/%E9%97%AA%E5%AE%A2%E5%BF%AB%E6%89%937%E9%87%8D%E7%BD%AE%E8%AE%A1%E5%88%922.71%E6%95%B4%E5%8C%85) | 2025-10-31 09:17:54 | `7.2.71.zip`，941,638,574 bytes | `591d8633b7ab2a0285bc7594567d3610a3784731` | 链接 2.7 更新视频 |

## 如何解释这些证据

- 上表六个上传资产是现有 GitHub 仓库中可直接核验的玩家整包，因此对应版本的
  “存在稳定发包”可标记为 `release_verified`。
- 2.40、2.50、2.60、2.65、2.66 的标签都指向换仓根提交
  `5b4238450d4702ebc69ce2acaaee022b2b031110`。这不否定上传资产的发包事实，但意味着
  当前 Git 历史不能按这些标签恢复各版本之间的源码差异。
- 上述五个旧包都在 2025-05-27 上传到 GitHub；这个时间更像换仓后的归档时间，不能在
  没有其他材料时改写成它们最初面向玩家发布的日期。
- 2.40、2.50、2.60、2.65 与 2.71 的 Release 说明直接链接同版本更新视频。单版本记录
  可以把视频作为官方更新说明的画面来源，但仍应把“包存在”和“某个镜头展示了什么”分别落证。
- 当前公开列表没有 2.0、2.2、2.3、2.45 或 2.718 整包。没有证据就保留缺口，尤其不得
  为版本号看起来连续而补造 2.710–2.717。

## 后续核验方法

每次稳定发包后，记录以下五项即可形成最小闭环：

1. Release 页面 URL 与标签原文；
2. `published_at`，同时标明时区；
3. 玩家下载资产的文件名与字节数；
4. 标签解析出的完整 Git 提交；
5. Release 说明是直接列改动，还是链接视频/其他更新说明。

不下载整包也能完成以上核验。只有需要验证包内内容或校验值时，才另开受控取证任务。
