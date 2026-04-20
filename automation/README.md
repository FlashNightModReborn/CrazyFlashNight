# Automation 自动化脚本使用指南

**文档角色**：启动与运行自动化入口。  
**最后核对代码基线**：commit `9f8f0c225`（2026-04-20）。

本目录只负责 **运行与启动自动化**。  
Flash CS6 编译 smoke、JSFL、trace、截图与计划任务细节，统一放在 [scripts/FlashCS6自动化编译.md](../scripts/FlashCS6自动化编译.md)。

## 1. 这个目录负责什么

- 首次环境准备（Flash 信任目录等）
- 一键启动游戏 / Launcher
- 兼容旧入口脚本的过渡封装
- 运行期常见问题的快速排查

## 2. 首次配置

### PowerShell 执行策略

Windows 默认可能禁止本地脚本执行。常用做法：

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

如果只想对当前窗口生效：

```powershell
Set-ExecutionPolicy Bypass -Scope Process
```

### 首次运行 `configure_server.ps1`

```powershell
cd "<项目根目录>\\automation"
.\configure_server.ps1
```

用途：

- 配置 Flash trust
- 校正启动所需的本地环境前置项

## 3. 日常启动

```powershell
cd "<项目根目录>\\automation"
.\start.ps1
```

脚本负责：

- 启动 Guardian Launcher
- 走当前默认运行链路
- 使用内嵌总线与现有宿主架构

### 兼容旧入口

- `start_game.ps1`：兼容旧入口，当前等价于 `start.ps1`
- `start_server.ps1`：已废弃，不再代表当前架构

## 4. 改代码后的常用动作

### 改 Launcher

```powershell
chcp.com 65001 | Out-Null
powershell -File ..\launcher\build.ps1
```

### 改 Flash / AS2

不要把本目录当成编译 smoke 入口；改用：

```powershell
chcp.com 65001 | Out-Null
powershell -ExecutionPolicy Bypass -File ..\scripts\compile_test.ps1
```

### 调导弹 / 追踪参数

离线调优 `MissileMovement.as` / `missileConfigs.xml` 时，优先用专用模拟器先筛参数：

```powershell
chcp.com 65001 | Out-Null
python ..\tools\missile-tuning-sim\run_sim.py audit --verbose
python ..\tools\missile-tuning-sim\run_sim.py compare --configs interceptor cruise pressureSlow --velocity 20 --use-prelaunch
python ..\tools\missile-tuning-sim\run_sim.py scan --base-config cruise --objective loiter --use-prelaunch --grid initialSpeedRatio=0.25,0.3 rotationSpeed=1.1,1.2 preLaunchFrames.min=18,20
```

适用边界：

- 用于离线比较预设、轨迹与“持续施压”指标
- `loiter` 目标适合慢巡航 / 滞空型导弹，`--grid` / `--set` 支持 `preLaunchFrames.min=18` 这类嵌套字段
- 默认按“已指定攻击目标”路径模拟，不替代游戏内最终手感复核

## 5. 常见问题

### 启动脚本无法执行

- 先检查 PowerShell 执行策略
- 再确认脚本路径是否位于当前项目根

### 启动后无法正常连总线

- 优先用 `tools/cfn-cli.sh status` 或 `tools/cfn-cli.ps1 status` 看当前总线状态
- 必要时看 `launcher/README.md` 的运行与诊断章节

### 机器路径与默认路径不同

- 不要手改文档里的旧绝对路径示例去推断工程结构
- 以当前项目根目录为基准运行脚本

## 6. 文件说明

| 文件 | 用途 |
|------|------|
| `config.toml` | 运行时配置 |
| `configure_server.ps1` | 首次环境准备 |
| `start.ps1` | 当前总入口 |
| `start_game.ps1` | 兼容旧入口 |
| `start_server.ps1` | 已废弃的旧入口 |
| `publish.ps1` | 开发态批量发布辅助脚本 |

## 7. 相关文档

- 启动 / 运行与子系统细节：[`launcher/README.md`](../launcher/README.md)
- 测试矩阵：[`agentsDoc/testing-guide.md`](../agentsDoc/testing-guide.md)
- Flash 编译 smoke：[`scripts/FlashCS6自动化编译.md`](../scripts/FlashCS6自动化编译.md)
- 离线导弹调优：[`tools/missile-tuning-sim/README.md`](../tools/missile-tuning-sim/README.md)
