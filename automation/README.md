# Automation 自动化脚本使用指南

本文件夹包含 Crazy Flasher 7 佣兵帝国的自动化启动与环境配置脚本。

---

## 目录

- [第一步：解除系统对脚本的运行限制](#第一步解除系统对脚本的运行限制)
- [第二步：首次配置环境（configure_server.ps1）](#第二步首次配置环境configure_serverps1)
- [第三步：一键启动游戏（start.ps1）](#第三步一键启动游戏startps1)
- [常见问题](#常见问题)
- [全部文件说明](#全部文件说明)

---

## 第一步：解除系统对脚本的运行限制

Windows 默认**禁止运行** PowerShell 脚本。以下两种方法任选其一：

### 方法 A：临时解除（推荐新手使用，仅本次窗口有效）

1. 按 `Win + S`，搜索 `PowerShell`
2. **右键** 点击 "Windows PowerShell" → **"以管理员身份运行"**
3. 输入以下命令后按回车：

   ```powershell
   Set-ExecutionPolicy Bypass -Scope Process
   ```

### 方法 B：永久解除

1. **以管理员身份打开 PowerShell**
2. 输入：

   ```powershell
   Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

---

## 第二步：首次配置环境（configure_server.ps1）

> **只需运行一次。** 该脚本会配置 Flash Player 信任目录。

### 如何运行

1. **以管理员身份打开 PowerShell**
2. 导航到脚本目录：

   ```powershell
   cd "C:\Program Files (x86)\Steam\steamapps\common\CRAZYFLASHER7StandAloneStarter\CrazyFlashNight\automation"
   ```

3. 运行配置脚本：

   ```powershell
   .\configure_server.ps1
   ```

4. 等待脚本执行完毕，按回车关闭窗口。

---

## 第三步：一键启动游戏（start.ps1）

完成第二步的首次配置后，以后每次启动游戏只需运行此脚本。

### 如何运行

1. 打开 PowerShell（普通模式即可，**不需要**管理员权限）
2. 导航到脚本目录：

   ```powershell
   cd "C:\Program Files (x86)\Steam\steamapps\common\CRAZYFLASHER7StandAloneStarter\CrazyFlashNight\automation"
   ```

3. 运行启动脚本：

   ```powershell
   .\start.ps1
   ```

4. 脚本会启动守护进程，守护进程会自动：
   - 启动 Flash Player 加载游戏 SWF
   - 启动内嵌的 V8 总线（替代旧的 Node.js 服务器）
   - 拦截可能干扰游戏的快捷键（Ctrl+Q/W/R 等）

### 快捷方式（可选）

在桌面右键 → **新建** → **快捷方式**，位置填入：

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Program Files (x86)\Steam\steamapps\common\CRAZYFLASHER7StandAloneStarter\CrazyFlashNight\automation\start.ps1"
```

---

## 常见问题

### Q: 提示"无法加载文件，因为在此系统上禁止运行脚本"

请回到第一步解除脚本运行限制。

### Q: 游戏启动后无法连接服务器

守护进程已内嵌 V8 总线，不再需要单独启动 Node.js 服务器。如果仍有连接问题：
1. 检查防火墙是否拦截了 localhost 通信
2. 确保没有其他程序占用端口

### Q: 我的 Steam 不是装在默认路径

将本文档中所有路径中的 `C:\Program Files (x86)\Steam\steamapps\common\CRAZYFLASHER7StandAloneStarter` 替换为你实际的安装路径。可在 Steam 中右键游戏 → **管理** → **浏览本地文件** 找到路径。

---

## 全部文件说明

| 文件 | 用途 |
|------|------|
| `config.toml` | 启动参数配置（分辨率、帧率、画质等） |
| `configure_server.ps1` | 首次环境配置：配置 Flash 信任目录 |
| `start.ps1` | **总入口**：启动守护进程（含游戏 + V8 总线） |
| `start_game.ps1` | 兼容旧入口，等价于 start.ps1 |
| `start_server.ps1` | 已废弃（V8 总线内嵌于守护进程） |
| `publish.ps1` | 开发用：调用 Flash CS6 批量发布 FLA 文件 |
| `test.html` | 开发用：在浏览器中嵌入 SWF 进行测试 |
