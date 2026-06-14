# 清室边界 / Code Review Checklist

cf7-animate-kit 保留醉尘仙破解包里**合法、离线、本地的 AN 维护功能**与**通用 `.sol`/AMF0 编解码技术**，
**丢弃一切触及联网 / 身份 / 授权 / DRM `.sol` / hosts 的内容**，且全部从零依公开规范重写。

任何 PR 合入前对照本清单逐条核验。命中任一"禁止项"即拒绝合入。

## 禁止项（出现即拒绝）

- [ ] **联网**：`fetch` / `XMLHttpRequest` / `URLRequest` / `net`/`http(s)` 客户端 / WebSocket / DNS / 任何对外请求或遥测。
      （唯一例外：`packages/web/launch.bat` 与 `cep-panel` 文档里**下载 Electron** 属构建基建，不是 app 运行时功能。）
- [ ] **远程授权 / 在线复检**：任何 verify/version/activation 端点、COMPLETE-listener 校验、心跳。
- [ ] **MAC 算号 / keygen**：`MD5(MAC + …)`、`consum_code` 的 mod-10 校验、`recomm_code` 推导、任何机器绑定激活码生成。
- [ ] **DRM `.sol` 伪造**：合成 `ZCXGZS_*` / 醉尘仙四字段（mac/recomm/active/consum）激活 blob；"离线生成激活 sol"/"一键激活"。
- [ ] **hosts / DNS / 防火墙**：写 `0.0.0.0 <域名>`、`ipconfig /flushdns`、提权屏蔽授权服务器。
- [ ] **复用反编译代码**：import / 拷贝 / 链接 `tmp/zuichenxian-plugin-analysis/` 下任何 `.swf` / `Setup*.py` / `MainTimeline.as` /
      DoSWF 解包例程 / `ZCX_Sol_Generator` 片段；保留作者串、DoSWF 壳、反 dump 填充。

## 允许项（明确在范围内）

- [ ] **AN 维护**：装/删/更新插件 SWF、清缓存、`jvm.ini` 改内存、收侧边、开目录、SharedObject 诊断（`core/AnEnv` + `an-host`）。
- [ ] **通用 `.sol`/AMF0 编解码**：读写**游戏自身存档**与任意 `.sol`（`core/AmfCodec`），依公开 AMF0 规范，对 Rust `flash_lso` oracle 校验。
- [ ] **创作提速**：XFL 解析/lint/查重（`core/authoring` + `cli art`）、CEP 面板 + JSFL 文档自动化（`cep-panel` + `jsfl-host`）。

## 守护性测试（已落地，勿删）

- `packages/core/tests/an-env.test.ts › machineInfoSafe`：断言机器诊断 `containsMachineId===false`，且 JSON 中**无 MAC 模式 / 无 active_code / 无 consum_code**。
- `packages/core/tests/amf0.test.ts`：`.sol` 编解码字节级 + Rust 金标 JSON 双 oracle —— 证明编解码是通用 AMF0 而非任何特定 DRM 格式。

## 机器信息的边界

`an doctor` / `machineInfoSafe` 输出的"机器信息"是**人类可读诊断**（OS/Animate 版本/路径），
**显式不含任何硬件标识**（无 MAC、无卷序列号、无激活种子）。任何向其加入硬件 id 的改动都越界。
