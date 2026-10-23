# CF6 七个人形的真实 RSL 尺寸探针

独立 host 使用四个实际角色共享库，生成七个无存档测试单位，通过生产 `EnemyPropertiesLoader` 读取并合并属性目录，经现役 `_root.加载游戏世界人物` 与敌人初始化模板完成初始化。每个单位切到声明站姿，至少等待两帧后停止子时间线并测量身体像素；不取真实游戏单位，不写存档。

```powershell
python -X utf8 tools/cf6-body-scale/prepare.py
python -X utf8 tools/cf6-body-scale/prepare.py --check
powershell -NoProfile -ExecutionPolicy Bypass -File tools/cf6-body-scale/run-tests.ps1
```

最后一条必须由当前持有 CS6 队列的操作者串行执行，沿用 focused runner 的备份、锁、marker 与恢复合同。目标是 `scripts/tmp-cf6-body-scale-host/Cf6BodyScaleNativeHost.xfl`，其余共享 TestLoader 操作由 runner 管理。

预期输出 `Cf6BodyScaleLiveProbe: 7 measured, 0 failed` 和 `Cf6BodyScaleNativeTest Tests Passed: 21` / `Tests Failed: 0`。其中7项验证实际像素体高，14项经各单位真实方向入口验证左右换向后仍使用自身比例，不受根对象缓存或其他单位体型污染。夹具核对世界、实例名、普通身份token、初始化版本、等级与真实满血数值。具名武器仅在夹具测量期间隐藏并在finally中恢复；只读探针保留完整man矩阵与遮罩，使用4倍栅格、alpha≥128测量实际身体高度，拒绝空图和裁边。靶值与固定容差见 `measurement-contract.json`；失败实测不得通过放宽容差改写为成功。像素尺寸仍不代签玩家体感验收。

`rsl-identities.json` 由准备程序生成并核对输入快照；输入共享库改变时必须先核对来源并更新 `../cf6-prop-layout/generated/body-scale-probe-inputs.json`，不能直接忽略 SHA 差异。生产模板前置辅助函数复用冻结的 `../cf6-field-combat/TestLoader.as.template`，生成器只读该文件并去掉原测试入口，再接入本 suite；不会执行 field-combat 测试或写其源文件。
