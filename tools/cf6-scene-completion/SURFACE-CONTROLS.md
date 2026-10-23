# 原生表面40断言：全新检出的准备

`surface-controls.json` 固定探针点、原生遮罩矩阵、旧SWF SHA-256、长度及Git blob身份。四份旧SWF逐字节对应本地历史提交 `56eb0c15d5dee285692b07eb1028f4ced93088f3`，不从当前资源重建，也不随测试提交大型旧二进制。

前置：本地Git对象库含该提交及四个blob；Python 3.9或以上（仅标准库）。浅克隆或不完整对象库会明确失败；脚本不会联网或自动fetch。完整像素测试另需Windows、真实Flash CS6及仓库规定的编译锁/当前资源闭包，按现有focused runner运行。

```powershell
# 仅准备缺失的历史控制，已有文件必须精确匹配。
python -B -X utf8 tools/cf6-scene-completion/prepare_surface_controls.py
# 只读验证，不创建任何文件。
python -B -X utf8 tools/cf6-scene-completion/prepare_surface_controls.py --check
# 会先执行上述准备，再编译并运行原40条断言。
./scripts/run-cf6-native-surface-tests.ps1 -PythonExecutable python
```

控制文件仍位于AS2原路径 `tmp/cf6-fieldfix-20261023/traversal/old-native/`。现有文件内容不符时保留并拒绝，不覆盖、不删除。全部四份来源和现有目标先验证，之后才排他创建缺失文件。探针JSON还会与未修改的AS2 `rows` 数据逐项比对，避免文档点位与真实测试漂移。

隔离验证可指定一个已存在的空目录：`--output-root <目录>`；其下生成相同相对目录结构，不改变真实测试工作区。脚本无AS2/SWF编辑、编译、发布或网络操作。准备成功只证明历史对照身份，不能替代40条真实Flash像素回执。
