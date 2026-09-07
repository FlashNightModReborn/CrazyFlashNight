param(
    [switch]$Help
)
# Legacy publisher retired: use the shared C# asset candidate workflow.
chcp.com 65001 | Out-Null
Write-Host '旧地图图块发布器已退役。请在地图内容工作台的素材库按已发现的发布元件与源摘要提取候选，再统一应用；不会直接覆写地图数据或图片。'
if ($Help) { exit 0 }
exit 2
