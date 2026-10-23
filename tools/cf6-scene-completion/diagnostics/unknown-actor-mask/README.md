# 未知 actor 级 mask：被否定的采样假设

本目录保留本轮创建的旧 40 项实验原字节，改为 `.txt` 防止被当作现役 AS2 或 runner 执行。
`SHA256.json` 记录迁移前后核对过的 SHA-256、字节数及原路径。没有修改断言或把失败改成通过。

R1–R4 的原 source/SWF/trace 回执仍留在本轮 `tmp/cf6-mapfix-20261023/focused-r*/actor-mask-presentation`，未移动或覆盖。
R4 runId `cc83e6dd5d0641f29e695e10cc57b1c7` 使用唯一路径、跨帧稳定后，Compiler 0/0，仍为 27 通过 / 13 失败。
非零世界/人物位置、镜像/缩放情况下，带未知 actor 级外部 mask 的整只 actor 采样为空；原点六项 probe 的正结果不能推广。

现役入口是 `scripts/run-cf6-actor-mask-known-none-tests.ps1`，只验证出生时已有独立身份和实例转发记录的 known-none actor，
允许 actor 内部 man 子树的遮罩；已有或未知 actor 级外部 mask 则取消代理并保留原显示。新合同的通过不覆盖本目录否定结论。