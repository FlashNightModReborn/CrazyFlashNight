# 项目名称：Node.js 服务器与 XMLSocket 通信系统

## 简介

这是一个基于 Node.js 构建的服务器，支持 HTTP 与 XMLSocket 通信，旨在与 ActionScript 2（AS2）客户端进行交互。服务器的模块化设计易于扩展和维护，通过分离不同的任务处理逻辑实现了更高的代码可读性和可维护性。

## 目录结构

```
project-root/
├── server.js          // 主服务器入口
├── config/
│   └── ports.js       // 端口提取与验证逻辑
├── routes/
│   └── httpRoutes.js  // HTTP 路由定义
├── controllers/
│   ├── evalTask.js    // 处理 'eval' 任务
│   ├── regexTask.js   // 处理 'regex' 任务
│   └── computationTask.js // 处理 'computation' 任务
├── services/
│   └── socketServer.js // XMLSocket 服务器逻辑
├── utils/
│   └── logger.js      // Winston 日志配置
└── package.json       // 项目依赖
```

## 模块介绍

### 1. `server.js` - 主服务器文件
该文件是服务器的入口，负责启动 HTTP 服务器并初始化 XMLSocket 服务器。它加载配置、路由、服务等模块，并控制服务器的生命周期。

- **功能**：
  - 启动 HTTP 和 XMLSocket 服务器
  - 处理不同类型的任务请求
  - 提供日志记录与错误处理机制

### 2. `config/ports.js` - 端口管理
该模块负责从指定的字符串（例如 `eyeOf119`）中提取有效的 4 位或 5 位端口，并确保默认端口（例如 3000）被加入端口列表。它还负责验证端口号是否在合法范围（1024 到 65535）内。

- **主要功能**：
  - 提取 4 位和 5 位有效端口
  - 验证端口号的合法性
  - 确保端口列表不包含重复项

### 3. `routes/httpRoutes.js` - HTTP 路由管理
该文件定义了所有 HTTP 路由，例如返回主页内容和关于页面内容。它还包括一个用于返回当前 XMLSocket 端口的特殊路由。

- **主要功能**：
  - `/` 路由：返回“Hello World!”消息
  - `/about` 路由：返回关于页面内容
  - `/getSocketPort` 路由：返回当前正在使用的 XMLSocket 端口

### 4. `controllers/` - 任务处理模块
每种任务类型（如 `eval`、`regex`、`computation`）都有各自的处理器文件，负责处理相应的任务逻辑，并将结果返回给客户端。
后续会根据任务类型进行拓展

#### a. `controllers/evalTask.js`
- **功能**：接收 JavaScript 代码并使用 `vm2` 安全沙箱模块执行代码，返回执行结果。

#### b. `controllers/regexTask.js`
- **功能**：接收文本和正则表达式，使用 `RegExp` 对文本执行匹配操作，并返回匹配结果。

#### c. `controllers/computationTask.js`
- **功能**：接收一个数字数组并计算其总和，返回计算结果。

### 5. `services/socketServer.js` - XMLSocket 服务器模块
该模块实现了 XMLSocket 服务器的核心逻辑，用于与 AS2 客户端建立双向通信。它负责监听 XMLSocket 端口并处理来自客户端的 JSON 消息。

- **主要功能**：
  - 监听 XMLSocket 端口
  - 处理来自 AS2 客户端的消息
  - 支持任务分发，将不同任务类型交给相应的 `controllers` 模块处理
  - 返回处理结果给客户端

### 6. `utils/logger.js` - 日志管理
该模块使用 `winston` 和 `winston-daily-rotate-file` 进行日志记录。所有运行信息、错误、警告都会记录在控制台和日志文件中，日志文件按天轮换，最多保存 14 天。

- **主要功能**：
  - 配置日志记录器
  - 按天轮换日志文件
  - 控制台与文件日志输出

## 工作流程

1. **启动服务器**：运行 `server.js` 文件，服务器从配置文件中提取可用端口并启动 HTTP 服务器，随后尝试启动 XMLSocket 服务器。
2. **HTTP 请求处理**：客户端可以通过 HTTP 路由访问服务器基本信息，例如访问 `/getSocketPort` 获取当前 XMLSocket 端口号。
3. **XMLSocket 连接建立**：AS2 客户端通过从 `/getSocketPort` 获取的端口号建立 XMLSocket 连接，连接成功后，客户端可以通过该端口发送任务请求。
4. **任务处理**：
   - 当 AS2 客户端发送 JSON 格式的任务请求时，服务器会根据任务类型（`eval`, `regex`, `computation`）将其分发到相应的 `controllers` 模块进行处理。
   - 每个任务模块处理完后，会将结果封装为 JSON 格式返回给客户端。
5. **日志记录**：所有请求与任务处理过程中的关键信息都会被记录到日志文件中，便于调试和监控。

## 任务说明

- **`eval` 任务**：通过 `vm2` 沙箱安全执行代码并返回结果，防止恶意代码注入。
  - 请求示例：
    ```json
    {
      "task": "eval",
      "payload": "Math.pow(2, 3)",
      "extra": null
    }
    ```
  - 返回示例：
    ```json
    {
      "success": true,
      "result": 8
    }
    ```

- **`regex` 任务**：通过正则表达式匹配指定文本，并返回匹配结果。
  - 请求示例：
    ```json
    {
      "task": "regex",
      "payload": "hello world",
      "extra": {
        "pattern": "hello",
        "flags": ""
      }
    }
    ```
  - 返回示例：
    ```json
    {
      "success": true,
      "match": ["hello"]
    }
    ```

- **`computation` 任务**：接收一组数字并计算其总和，返回计算结果。
  - 请求示例：
    ```json
    {
      "task": "computation",
      "payload": null,
      "extra": {
        "data": [1, 2, 3, 4]
      }
    }
    ```
  - 返回示例：
    ```json
    {
      "success": true,
      "result": 10
    }
    ```

## 错误处理

- 非 JSON 格式的消息会触发警告并返回错误信息：
  ```json
  {
    "success": false,
    "error": "Expected JSON format"
  }
  ```

- 未知任务类型将返回错误：
  ```json
  {
    "success": false,
    "error": "Unknown task type"
  }
  ```

## 日志

服务器会记录以下关键信息：
- 服务器启动、端口分配信息
- HTTP 请求与 XMLSocket 客户端连接状态
- 各种任务的处理结果
- 错误与警告信息

## 如何运行

1. **安装依赖**：确保你已安装 Node.js，然后在项目根目录运行以下命令安装依赖：
   ```bash
   npm install
   ```

2. **启动服务器**：
   ```bash
   node server.js
   ```

3. **查看日志**：日志文件会保存在 `logs` 目录下，并按日期进行文件轮换。你也可以在控制台查看运行时的日志输出。

