# Automation 自动化脚本使用指南

本文件夹包含 Crazy Flasher 7 的自动化启动与环境配置脚本。如果你从未使用过 PowerShell，请从头阅读本指南。

---

## 目录

- [前置知识：什么是 PowerShell 脚本](#前置知识什么是-powershell-脚本)
- [第一步：解除系统对脚本的运行限制](#第一步解除系统对脚本的运行限制)
- [第二步：首次配置环境（configure_server.ps1）](#第二步首次配置环境configure_serverps1)
- [第三步：一键启动游戏和服务器（start.ps1）](#第三步一键启动游戏和服务器startps1)
- [常见问题](#常见问题)
- [全部文件说明](#全部文件说明)

---

## 前置知识：什么是 PowerShell 脚本

PowerShell 是 Windows 自带的命令行工具。本项目的 `.ps1` 文件就是 PowerShell 脚本。

**如何打开 PowerShell：**

1. 按下键盘 `Win + S`（或点击任务栏搜索框）
2. 输入 `PowerShell`
3. 在搜索结果中找到 **Windows PowerShell**

> 注意：不要选择 "PowerShell ISE"，选择普通的 **Windows PowerShell** 即可。

---

## 第一步：解除系统对脚本的运行限制

Windows 默认**禁止运行** PowerShell 脚本。如果你直接双击 `.ps1` 文件，可能会看到如下错误：

```
无法加载文件 ……，因为在此系统上禁止运行脚本。
```

你需要先解除这一限制。**以下两种方法任选其一：**

### 方法 A：临时解除（推荐新手使用，仅本次窗口有效）

1. **以管理员身份打开 PowerShell**
   - 按 `Win + S`，搜索 `PowerShell`
   - 在搜索结果中，**右键** 点击 "Windows PowerShell"
   - 选择 **"以管理员身份运行"**
   - 如果弹出"用户账户控制"对话框，点击 **"是"**

2. 在打开的蓝色窗口中输入以下命令，然后按回车：

   ```powershell
   Set-ExecutionPolicy Bypass -Scope Process
   ```

3. 此窗口现在可以运行任何脚本。**关闭窗口后设置自动失效**，不会影响系统安全性。

### 方法 B：永久解除（适合需要反复使用的用户）

1. **以管理员身份打开 PowerShell**（步骤同方法 A）

2. 输入以下命令，然后按回车：

   ```powershell
   Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

3. 如果提示确认，输入 `Y` 后回车。

> `RemoteSigned` 策略的含义：允许运行本地脚本，但从网上下载的脚本需要数字签名。这是一个安全且实用的折中选项。

---

## 第二步：首次配置环境（configure_server.ps1）

> **只需运行一次。** 该脚本会自动安装 Node.js 并配置 Flash Player 信任目录。

### 这个脚本做了什么？

1. 自动下载并安装 **Node.js v20.12.2**（本地服务器运行所需）
2. 将游戏目录添加到 **Flash Player 信任列表**（解决本地运行的安全限制）

### 如何运行

**此脚本必须以管理员身份运行。** 请按照以下步骤操作：

1. **以管理员身份打开 PowerShell**（方法见第一步）

2. 输入以下命令导航到脚本目录（复制粘贴即可，在 PowerShell 中右键即为粘贴）：

   ```powershell
   cd "C:\Program Files (x86)\Steam\steamapps\common\CRAZYFLASHER7StandAloneStarter\resources\automation"
   ```

   > 如果你的 Steam 安装在其他位置，请将路径替换为你实际的游戏安装目录下的 `resources\automation` 文件夹路径。

3. 运行配置脚本：

   ```powershell
   .\configure_server.ps1
   ```

4. 等待脚本执行完毕。你会看到类似以下输出：

   ```
   Checking for Node.js installation...
   Node.js is not installed. Installing now...
   Downloading Node.js v20.12.2 from official website...
   Download completed. Starting installation...
   Node.js has been installed.
   Setting up Flash Player trust directory...
   Trust settings updated.
   Configuration process completed. Press Enter to exit.
   ```

5. 按回车关闭窗口。配置完成。

### 如何确认配置成功？

打开一个新的 PowerShell 窗口（无需管理员），输入：

```powershell
node -v
```

如果输出 `v20.12.2`，说明 Node.js 安装成功。

---

## 第三步：一键启动游戏和服务器（start.ps1）

完成第二步的首次配置后，以后每次启动游戏只需运行此脚本。

### 如何运行

1. 打开 PowerShell（普通模式即可，**不需要**管理员权限）

2. 导航到脚本目录：

   ```powershell
   cd "C:\Program Files (x86)\Steam\steamapps\common\CRAZYFLASHER7StandAloneStarter\resources\automation"
   ```

3. 运行启动脚本：

   ```powershell
   .\start.ps1
   ```

4. 脚本会自动启动游戏和本地服务器，你会看到：

   ```
   Starting the game...
   Game started successfully.
   Starting the server...
   Server started successfully.
   Both the game and server have been started successfully.
   ```

### 快捷方式（可选）

如果你不想每次都打开 PowerShell 输入命令，可以创建一个快捷方式：

1. 在桌面右键 → **新建** → **快捷方式**
2. 在"位置"一栏输入：

   ```
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Program Files (x86)\Steam\steamapps\common\CRAZYFLASHER7StandAloneStarter\resources\automation\start.ps1"
   ```

3. 点击"下一步"，给快捷方式起一个名字（例如 `启动CF7`），点击"完成"
4. 以后双击这个快捷方式即可一键启动

---

## 常见问题

### Q: 双击 .ps1 文件后用记事本打开了，而不是运行脚本

Windows 默认将 `.ps1` 文件关联到文本编辑器。这是正常的安全设计。请按照上面的步骤，在 PowerShell 窗口中用 `.\脚本名.ps1` 的方式运行脚本。

### Q: 提示"无法加载文件，因为在此系统上禁止运行脚本"

你还没有解除脚本运行限制。请回到 [第一步](#第一步解除系统对脚本的运行限制) 按照说明操作。

### Q: 提示"不是内部或外部命令"

- 如果是 `node` 命令报错：Node.js 没有安装成功，请重新运行 `configure_server.ps1`
- 如果是脚本文件报错：请确认你已经 `cd` 到了正确的目录

### Q: 弹出"用户账户控制"窗口问是否允许

这是 Windows 的安全提示。`configure_server.ps1` 需要管理员权限来安装 Node.js 和配置信任目录。点击 **"是"** 即可继续。

### Q: 游戏启动后无法连接服务器

请确认：
1. `start.ps1` 输出了 "Server started successfully"
2. 没有其他程序占用服务器端口
3. 防火墙没有拦截 Node.js 的网络请求

### Q: 我的 Steam 不是装在默认路径

将本文档中所有路径里的：
```
C:\Program Files (x86)\Steam\steamapps\common\CRAZYFLASHER7StandAloneStarter
```
替换为你实际的游戏安装路径即可。

你可以在 Steam 中右键游戏 → **管理** → **浏览本地文件** 来找到你的安装路径。

---

## 全部文件说明

| 文件 | 用途 |
|------|------|
| `config.toml` | 启动参数配置（分辨率、帧率、画质等） |
| `configure_server.ps1` | 首次环境配置：安装 Node.js + 配置 Flash 信任目录 |
| `start.ps1` | **总入口**：同时启动游戏和服务器 |
| `start_game.ps1` | 启动 Flash Player 加载游戏 SWF |
| `start_server.ps1` | 启动本地 Node.js 服务器 |
| `publish.ps1` | 开发用：调用 Flash CS6 批量发布 FLA 文件 |
| `test.html` | 开发用：在浏览器中嵌入 SWF 进行测试 |
