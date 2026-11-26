# 闪2大机器人：坦克形独立单位

**归属**：Issue [#271](https://github.com/FlashNightModReborn/CrazyFlashNight/issues/271)，供闪客快打2肉鸽消费的前置单位。
当前为可测试原型；编译、原生图形、战斗行为、同级斗兽和真人体验分别验证，不能互相代签。

## 已确认边界

- 首版处理坦克形，不制作人形、变形、肉鸽关卡、剧情或正式掉落。
- 普攻及加特林、激光、站桩全弹、移动全弹全部接入。全弹只重复内部循环段，默认三轮，前摇和收招各一次。
- 出招时刚体、免疫外力击退并锁定左右朝向，正常承伤；完成、取消及死亡恢复原先持有的标志。
- 死亡第 12 帧触发一次本机物理爆炸亡语（`空手攻击力 × 2.0`、`Z轴攻击范围 = 80`，不继承 CF6 老头核爆或全屏比例伤害），并配合本机分件、私有机械爆裂和标准碎片运动落地。
- 原稿说明“全弹发射还包含那十个榴弹炮”属于玩法输入，不是运行文字；原始回包保留，运行库排除这条缺字体的编辑注释。
- 黑铁是初版强度参照。阶段5、档次27只是计算预算，**不是闪2肉鸽章节／等级裁定，也不是五五开胜率已验证**。注册表默认展示等级不代表投放等级。

## 本轮验证

原生专项 **4867 passed / 0 failed**（`39b5e8ac` SWF，Compiler `0/0`），轻量视觉探针 **8 passed / 0 failed**，离线校验 **10/10 OK**，XFL 审计 `CLEAN`，SWF 闭包与 48 处 `blendMode` 摆放校验通过，Arena 单位目录与 tooltip 清单 `--check` 均为最新。上一轮黑铁同级换边试验（`cf2-bi37-1117-r3`，`53.61% / 23.35%`）绑定重构前的 `f2be0b79` SWF，**尚未在本轮 `39b5e8ac` 新版本上重跑**，仍待独立实战复测与真人体验验收。

精确资源身份、体积、本轮验证摘要、历史对照索引和未验证项见[原型交付验证快照](../../docs/CF2大机器人-坦克形原型交付验证-2026-11-17.md)。日常体验仍用仓库根的 `本地开发启动.cmd`；本轮没有提交、推送或推广正式 runtime。

## 真源和装配

- 冻结回包：[CF2大机器人-issue271](../../flashswf/arts/new/Codex素材源稿/CF2大机器人-issue271/)，`archive-origin.json` 绑定 RAR 与全部解包成员。
- 唯一游戏编辑工程：[Codex大机器人素材](../../flashswf/arts/new/Codex大机器人素材/)。原稿为冻结输入，不与游戏工程并行编辑。
- [spec.json](spec.json) 管理身份、动作区段、初版参数和几何（含原稿场景参照比例 `0.45`、`tankMeleeAreas` 三段框、`grenadeMuzzles` 十管炮口、转身死区与冷却、`deathPower: 2.0`）；[TankBossAI.as](TankBossAI.as) 编入本资源，不新增 asLoader 类或启动逻辑。
- [motion-samples.json](motion-samples.json) 是绑定原包和采样脚本摘要的原生姿态输入，不是另一份美术编辑工程。Animate 24 在隔离副本中执行 `convertToKeyframes` 与 `getRigMatrixAtFrame × element.matrix`；不能用普通显示树的父矩阵连乘代替 Animate 图层绑定。
- [build.py](build.py) 保留原画、遮罩、`add`/`lighten` 混合模式实例与位图填充；绑定层使用原生逐帧矩阵，未绑定特效保留 XML 补间，`跑步走路` 缺失的 `PuppetShape_1` 腰部软管由同帧 `theboss底盘` + `(483.5, -48.25)` 恢复为 `示例用管线`。`技能` 时间轴按四段动作剔除空白隔离帧（45 / 103 / 178）并切片至 `动作切片/{gatling,laser,barrage,mobile}` 从第 1 帧起播，`area` 初始透明度与可见性压零，并显式归零 `x轴攻击范围` 与 `unitAI.data.xrange`。供体脚本不进入游戏；重建前核对完整输出集合及 SHA-256，发现外部编辑即拒绝覆盖。
- 命名端口与画稿共用原生取样：
  - 激光端口收集全部 `Symbol 195` 光束图层（`L13..L22`），沿真实光束路径均布 6 个紧凑接触盒（单盒 `280×200` 原稿 px ≈ `126×90` 舞台 px），覆盖光束主体与地面／对空交点，不再只保留单个交点盒，也不退回半屏 AABB。
  - 原稿的“机枪手”是两帧复用件（第 1 帧为枪，第 2 帧为斧；站桩全弹交换两手），机枪端口按实际枪帧选取。加特林与移动全弹时上身扭转向后射机枪、炮塔向正前方开火（按炮塔 `firstFrame==9` 后坐对齐，发射 `"巴雷特子弹"` 配 `巴雷特枪火`/`战术巴雷特击中特效`/`弹坑`）。
  - 10 管 `"榴弹"` 绑定至 `"theboss炮塔"` 上的真实炮口坐标，以 `速度Y < 0` + 水平速度梯度向前抛出抛物线；普攻三段判定框 `[23, 26, 47]` 依次覆盖后砸、腹底拖曳、前挑；所有技能均不翻转车体，改为前后向分区决策与带冷却转身。
- 私有 MovieClip 载体的末级库名和时间轴名保持全库唯一。仅目录不同、itemID 不同不足以避免本例 CS6 的载体并轨；还须核对实际 SWF 时间轴长度及原生图形，不以静态引用检查替代。
- [mount.py](mount.py) 经 `things-new.fla` 第四帧挂载本库，只改两个 XML 并新增本库导入声明；其他 ZIP 本地记录逐字节保留，原 FLA 自动保存在任务 `tmp/`。
- [balance.py](balance.py) 调用仓库怪物公式，只维护本单位属性和注册记录；不修改公式或把临时预算写成制作组人工固定值。

原生 XFL 含原作者的逐帧位图填充，不能据“只有几个 DOMBitmapInstance”判断其余位图未使用。
缓存、XML、完整性和体积以 `native-manifest.json` 为准；当前运行 SWF 由 CS6 压缩产生，不手工修改。

## 验证入口

仓库根 PowerShell，先 `chcp.com 65001`：

```powershell
python -B -X utf8 tools/cf2-boss-assets/build.py --build
python -B -X utf8 tools/cf2-boss-assets/build.py --check
python -B -X utf8 tools/cf2-boss-assets/balance.py --write
python -B -X utf8 tools/cf2-boss-assets/balance.py
python -B -X utf8 tools/cf2-boss-assets/tests.py
python -B -X utf8 scripts/tools/xfl/audit.py flashswf/arts/new/Codex大机器人素材
scripts/compile_test.ps1 -Target 'flashswf/arts/new/Codex大机器人素材/Codex大机器人素材.xfl' -PublishOnly -VerifySwf 'flashswf/arts/new/Codex大机器人素材.swf' -TimeoutSeconds 300
```

共享挂载变化时：

```powershell
python -B -X utf8 tools/cf2-boss-assets/mount.py --write
python -B -X utf8 tools/cf2-boss-assets/mount.py
scripts/compile_test.ps1 -Target 'flashswf/arts/things-new.fla' -PublishOnly -VerifySwf 'flashswf/arts/things-new.swf' -TimeoutSeconds 300
python -B -X utf8 tools/linkage_scanner/scan_linkage.py --xml-only
node tools/derive-arena-unit-catalog.js
node tools/derive-arena-unit-catalog.js --check
node tools/derive-arena-unit-param-presets.js --check
python -B -X utf8 tools/build-tooltip-catalog.py --check
```

单位登记或敌人属性清单变化后也须执行以上校验，确认装备注释源数据与敌人显示名解析通过。重启消费者后另核对未再报告 `tooltip_catalog_stale`。

原生行为与图形：

```powershell
scripts/run-cf2-tank-boss-tests.ps1
scripts/run-cf2-tank-boss-tests.ps1 -Capture
scripts/run-cf2-tank-visual-probe.ps1
scripts/run-cf2-tank-visual-probe.ps1 -Capture
python -B -X utf8 tools/cf2-boss-assets/decode-capture.py <本轮trace> <新目录>
python -B -X utf8 tools/cf2-boss-assets/decode-capture.py <轻量探针trace> <新目录> --probe
python -B -X utf8 tools/cf2-boss-assets/verify.py
```

不带 `-Capture` 只检查图形非空，不输出可解码像素。完整行为夹具调用真实碰撞器、伤害结算和碎片物理，但未运行完整投射物飞行或正式游戏入口时，不据此宣称实战／玩家体验通过。

行为 runner 使用持锁、备份和恢复 scratch 的现有 focused 入口，隔离虚拟单位，不读取玩家槽位。
轻量探针只诊断原生图形和装配，不代替真实伤害、碎片物理或强度验收。失败和无 Complete 的记录保留在 `tmp/cf2-boss/`，
不能清空未知 marker 后直接重跑；遵守 [CS6 恢复合同](../../scripts/FlashCS6自动化编译.md#read-only-player-recovery)。

## 原稿更新时重新采样

正常构建直接消费冻结采样，不需要启动 Animate。原包或采样算法变化时，使用本机已有 Animate 2024，只做原生作者期采样，**不在 Animate 编译 SWF**：

```powershell
tools/cf2-boss-assets/sample-motion.ps1 -RunJsflChoice
python -B -X utf8 tools/cf2-boss-assets/sample-motion.py --check-report <本轮job目录>
python -B -X utf8 tools/cf2-boss-assets/sample-motion.py --import-report <本轮job目录>
```

该入口拒绝借用既有 Animate；`-RunJsflChoice` 仅在已目视确认本机“打开 JSFL 文件”的默认选项是“作为命令运行”后使用，不勾选“不再显示”。原稿复制到获准的用户临时目录，仅剥离脚本和那条编辑注释。原包与全部冻结成员在采样前后仍须一致。

作者期包装器可能因编辑器未退出返回失败，即使 `status.txt` 已为本轮 `complete`；这不允许盲重跑。先保留完整 job、原始报告与退出事实，确认旧进程确已消失，再只读 `--check-report`；核对通过后才能显式 `--import-report`。采样校验拒绝错动作、错零件和异常矩阵，仅剔除原生转关键帧时对**已结束且无绑定**图层补出的尾部，逐行记入 `normalization`，运行工程继续保留该层原始跨度。

## 黑铁原型对照

`arena-plan.js <显式配置.json>` 只生成隔离 Worker 的不可变输入，要求精确候选、合法资源根和只读种子。默认 37 级交换红蓝各一场；等级仅为原型测试，不是肉鸽投放等级。双方均调用固定敌人模板，不套人物模板的蓝方生命 ×3 补偿，不覆盖任何面板、技能或命中结算；必须复核实际出生数据，不能把计划写成实战或完全面板等价的证明。

普通榴弹目前是可拦截 UnitBullet，会进入世界单位层。发射包显式保留真实 `产生源`，由现有 Arena 派生来源合同核对并接管辅助实体；不能给子弹手贴标定白名单、换掉榴弹模板或放宽污染判定。

计划通过现有 `node tools/arena-calibration/run-worker-experiment.js --plan <plan>` 执行。它创建专用克隆槽、核对实际 runtime／资源闭包和非目标 JSON／SOL，正常收尾；不读写生产标定目录，不触发正式 runtime 推广。失败、超时或未知写按原 Worker 合同保留，不因胜负重放。
