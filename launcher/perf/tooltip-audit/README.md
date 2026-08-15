# Tooltip 全量语料与排版审计

这个入口验证“实际可输入的文本”在 Web 注释排版中的约束，不用手写的几个短样例替代物品库。

## 运行

在仓库根目录依次执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-tooltip-corpus-audit.ps1 -TimeoutSeconds 999
node tools/parse-tooltip-corpus.js
node launcher/perf/tooltip-audit/runner.js
```

第一步通过临时 `TestLoader.as` 事务加载正式 `EquipmentConfig`、全部 `ItemData` 和正式插件表，调用真实 `TooltipComposer`，输出：

- 每个基础物品；
- 每件装备的每个合法 tier；
- 每件装备一条合法 1 插件与 3 插件路径，用于覆盖宿主差异和三行堆叠形态；
- 每个正式插件定义至少一条实际合法安装路径，依赖插件会搜索最多 3 层前置；
- 实际 `introHTML`、`descHTML` 以及作者输入长度。

第二步严格校验行协议、连续编号、分类汇总、插件定义覆盖为 100% 和 `composeFailures=0`。这不是声称穷举插件排列的笛卡尔积：每个插件的作者全文由基础“插件材料”注释覆盖，每个定义另有合法安装态，所有装备再有 1/3 插件堆叠形态；布局安全由可滚动上限和非命中合同保证，不依赖恰好撞中最长排列。第三步在真实 `panels.css`、`tooltip.js` 和 `skills-render.js` 中测量全部物品语料与 `data/skills/skills.xml`：

- `1024×576`、`1366×768`、`1920×1080`；
- 完整与紧凑两种密集网格；
- 无后缀、平衡元数据、情报页数、K 商城锁定 + 平衡四种实际 Web 外部输入；
- 视口闭合、源格命中、dense profile、滚动、stacked、相邻格覆盖及最高样本。
- 同一全物品语料在三个视口下的 pinned 固定检视器闭合、独立命中与自身滚动容量。

结果写入忽略目录 `tmp/tooltip-audit/report.json` 和 `report.md`。覆盖相邻格本身不是失败：`dense-inspect` 的浮层不参与 hit-test；源格无法继续命中、浮层越出视口或 profile 漂移才是硬失败。

当前工作树的 fresh 结果为 3652 条物品语料、插件定义 105/105、87648 次 dense 物品测量和 396 次技能测量；视口越界、鼠标热点失守、pointer-events/profile 错误均为 0。106 次需要 dense owner 转发滚动，78286 次覆盖相邻格；后者验证了“不要靠动态避让消灭视觉覆盖，而要让 dense 浮层退出输入平面”的设计前提。同一语料另执行 10956 次 pinned 检视器测量，195 次需要检视器自身滚动，视口越界与 pointer-events/profile 错误同为 0。

## 源码诊断结论

旧实现并不存在一个“等注释慢慢避让”的异步计时器：`followMouse()` 会在每次 owner 的 move 事件里同步重算位置。用户快速扫格时真正的失效链是：浮层本身可命中并覆盖下一格 → 下一格收不到 enter/move → 原 owner 也不再持续收到用于重定位的 move → 140ms 复合 hover grace 又保留旧浮层。慢速移动通常能在被截获前多触发几次重排，所以会看到左右换位和闪烁。因而“与快速操作相关”的观察成立，但根因是 hit-test/event starvation 与逐点重排耦合，不是浏览器来不及播放避让动画。

区域级锚点只能稳定视觉位置，不能单独修复输入面；若浮层仍可命中，它覆盖相邻格时问题反而更明显。现役解法把两件事拆开：dense 允许视觉覆盖但强制 `pointer-events:none`，owner 切换始终由原网格完成；真正需要指针进入、滚动或操作的内容则迁到固定检视器。

## 外部输入与消费者清单

| 层 | 审计内容 | 约束 |
|---|---|---|
| AS2 物品源 | 正式 `ItemData` 1600 项，经真实 `TooltipComposer` 生成 intro/desc；包含作者 description、技能、生命周期、来源、材料与插件材料全文 | 不以 Web mock 文案代替 |
| 实例变化 | 574 个合法 tier、1098 个单插件宿主、279 个三插件宿主；105/105 插件各有合法安装态 | 不声称穷举插件排列；任一未覆盖定义直接失败 |
| Web 追加文本 | balance metadata、情报页数、KShop 等级锁定 + balance，以及无后缀基线 | 四种后缀与全部物品做笛卡尔测量 |
| 技能源 | `data/skills/skills.xml` 的 66 条真实输入 | 与物品相同的三视口、两密度几何门 |

| Profile | 现役消费者 |
|---|---|
| `dense-inspect` | Character 已装备/候选、KShop 目录/库存、NPC、合成、仓库、装备调制、Loot 主格、佣兵装备、Skills、Intelligence、Tasks 物品、Arena 对手装备 |
| `simple-tooltip` | Arena 自定义编辑短提示、Loot organizer 短提示、佣兵/战宠卡片或技能短提示、Arena 对手技能摘要 |
| `pinned-inspector` | KShop 商品显式激活后的右侧固定详情；普通 hover 不得覆盖 |

共享 `PanelTooltip` 之外还存在三类窄用途宿主：启动引导页 `BootTooltip`（作者短文、300ms 延迟、textContent、pointer-events none）、刘海性能曲线 `spark-tooltip`（最多三行实时数值、pointer-events none），以及 production HTML/JS 中的 148 处 native `title` 属性绑定。它们不接收 AS2 物品/技能正文，也不承担滚动阅读；静态门会排除 `var title = ...` 之类局部变量，并禁止 dense consumer 把 `introHTML/descHTML` 回退到 native title。native title 只允许控件名、坐标、路径或阻塞原因，不能成为长说明 fallback。地图 canvas feedback 属于瞬态操作反馈，不是 DOM tooltip。

静态门逐文件要求 dense/simple profile 显式出现，并禁止 dense consumer 继续自管 `showAtMouse/followMouse/hideHover`。每个 panel/view 持有 scope；整树替换前 `releaseTree`，close/rebind 时 dispose，迟到 rich 回包不能复活 detached owner。

## 设计判定

- “1 秒区分操作与阅读”成立，但只对**实际溢出的 dense 正文**启动；短内容不播空进度。明显快速位移重置进度，键盘 PageUp/PageDown 可立即进入。
- dense 检视不把鼠标吸进浮层；滚轮由仍在底层的 owner 转发，离开、换格、拖拽抑制或 Esc 即退出。这给出了无缝且确定的 scan ↔ inspect 转换。
- 需要长时间逐段阅读时，不把 dense 自动升级成粘住屏幕的状态；由玩家显式激活 pinned inspector，再以 close/Esc/outside click 退出。这样“路过”和“留下”不会共享含糊的退出规则。
- 把装备区视作整体、在稳定侧栏展示，是面向密集布局的空间分区，不是次等妥协；只要详情与当前 selection/owner 有明确关联，它比围着每个格子动态左右避让更符合现役约束。

## 证据边界

`run-tooltip-corpus-audit.ps1` 只在编译器 0 error / 0 warning、没有 32K retry、且日志出现同一随机 `runId` 的唯一 BEGIN / DONE / END 闭包后落盘。超时或异步闭包不完整会保留 `scripts/compile_state_uncertain.marker`，必须先确认 Flash、JSFL 和旧 test player 已静止并检查迟到日志，不能直接删除闸门。
