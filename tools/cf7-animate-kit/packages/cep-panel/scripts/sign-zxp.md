# 可选：自签 ZXP 打包（给非开发素材师"一键安装"门面）

默认推荐路径是 **folder-copy + PlayerDebugMode**（见 panel README / 操作手册 §5），零签名摩擦、与 dev 同产物。
仅当你想要一个双击安装的 `.zxp` 时再走本流程。**注意：自签证书不被信任，目标机通常仍需开 PlayerDebugMode**，
ZXP 只买"安装门面"，不解除 debug 标志依赖（只有付费可信代码签名证书才能解除，超出本工具范围）。

## 前置

- 先 `npm run build`，确保 `dist/` 是自包含扩展（含 `CSXS/manifest.xml`、`host/index.jsfl`、`.debug` 可删）。
- 取得 Adobe 的 `ZXPSignCmd`（CEP-Resources/ZXPSignCMD），放进 PATH 或本目录。

## 步骤

```bat
:: 1) 生成自签证书（一次性）
ZXPSignCmd -selfSignedCert CN Shanghai CF7Studio AnimateKit yourpassword cert.p12

:: 2) 签名 dist/ -> AnimateKit.zxp（-tsa 时间戳，防签名随证书过期）
ZXPSignCmd -sign dist AnimateKit.zxp cert.p12 yourpassword -tsa http://timestamp.digicert.com
```

发布物 = `AnimateKit.zxp`。素材师用 Anastasiy ZXPInstaller / ExManCmd 安装；若仍停在加载失败，
回退到 `install/enable-debug.bat` + `install/install-dev.bat` 的 folder-copy 路径。

> 发布前**务必**先按 `packages/jsfl-host/README.md` 在目标 Animate 版本上 smoke-test 各 JSFL 函数。
