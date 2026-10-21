# CF7 军警犬与盗贼犬 V6 离线美术候选

本包只交制式军警犬、盗贼撕咬犬。军阀后续独立，V5已发内容保持不变。当前为本轮精修和离线检查后的候选，等待用户视觉终验；不是已经Flash编译、装配或实机发布的资源。

## 文件与版本

- 两犬各13常规＋25死亡阶段，共76运行时SVG，另有24个editable-clipped死亡编辑源，不额外计作运行时槽。
- 26常规中，本轮有19件内容发生精修，7件沿用V5并纳入动作复核：军警改11/留2，盗贼改8/留5。逐件哈希与版本记录保留，不说所有文件都是本轮重新绘制。
- 24件含犬体身份的死亡槽均同步V6并重新输出；26个纯血迹槽按合同原样复用，逐字节验证。
- 运行时SVG独立可解析、Flash局部像素、(0,0)原点；没有clipPath/filter/image/text/script。裁切源经Skia贝塞尔布尔运算展开为path，未以位图或自动描摹替代。

## 直接看图

- previews/overview/two-dogs-standing.png：同一站立帧、同尺度两犬展示。
- previews/overview/two-dogs-action-comparison.png：收口、扑咬、跑动对照。
- previews/overview/two-dogs-joint-details.png：头颌/耳根/肩颈/脚掌放大。
- previews/overview/two-dogs-death-comparison.png：死亡阶段关键帧对照。
- previews/01-military-full/interactive/index.html、previews/02-raider-full/interactive/index.html：完整离线时间轴页。

每犬7条时间轴494帧，按时间轴去重44个犬体摆放状态，左右88个透明PNG；两犬合计176张全部独特状态透明图，含源定义空白。镜头按时间轴固定，不逐帧居中。预览包不重复携带场景SVG，全部运行时分件SVG仍在资产包；场景SVG可由附带脚本无损重生，报告采样链接指向实际透明PNG。

## 重要边界

口腔与待机是明确待装配点：原rig收口/待机仍开口，独立头颌间的内腔仍可透背景。当前改善牙床、唇线、牙列与关节，不声称已实现完全闭嘴或所有角度不透明内壁。后续内腔/表情/时间轴方案须另行装配验证，详见ASSEMBLY-NOTES.md。

死亡使用原阶段断裂包络与破损牙列，圆冠、断齿或排列与normal的逐齿差异有记录；并非每颗牙齿都逐一精确复刻。a0/a1阶段完整保留；a2第56–89帧源无犬体，末帧透明清理控制器不在离线页执行，不能当作漏绘或AS2已验证。

军警/盗贼尾巴仅扩展单刚性件，尾根不动。路径相对固定原点的最远半径实测约1.888/1.536倍源图，接近约1.9/1.5目标；不是只扩大viewBox。

已做的证据分别列于qa：纯矢量/原点/源哈希、normal-death版本同步、独立字节重建、完整帧映射、全状态真实Inkscape栅格、展开A/B、实际看图和返修记录。HTML脚本在模拟DOM中检查帧切换、镜像与分支；真实Chromium交互本环境此前在启动前被阻挡，本轮不重复升级尝试，未声称真实浏览器已验收。Flash/CS6、AS2伤害/碰撞/声音、外层翻滚物理、真实游戏均未执行。

## 使用与分发

见REBUILD-README.md。source-contract为原始交接的必要只读子集，逐项保留来源SHA；SCOPE.json限定本轮两犬而不改原合同或骨架。分件对应表PART-MAPPING.csv、逐件coverage.json与SHA256SUMS.json可核查。

三个独立标准ZIP分别为Assets资产包、军警Preview、盗贼Preview，每包小于20MB，无二进制分卷。解压到同一父目录，合并成CF7-Two-Dogs-V6。全部三包合并后可验证根SHA256SUMS.json，哈希只针对文件内容，不包含扩展属性。Windows接入者应使用独立新资源身份，不能直接按历史槽编号覆盖原共享库。
