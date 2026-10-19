# CF7 最小路径预算门禁（阶段 B 候选，未提交/推送/部署）

这组文件可整体放入 `tools/path-budget/`；配套普通只读 CI 候选见
`.github/workflows/path-budget.yml`。施工包另提供 `core.patch`、`workflow.patch` 和二者合并的 `stage-b.patch`；
这些补丁和本次核验记录不作为项目常驻文件。
只用 Python 3.9+ 标准库和已安装 Git，不装项目依赖，不执行业务、Flash、构建、安装或发布脚本。

## 本次配置及结果边界

- 唯一源树政策：原始 Unicode UTF-16，`relative_limit=200`、`root_units=60`、
  `full_visible_limit=240`、`segment_limit=255`。完整路径算 `60+1+relative`，有效相对预算 **179**，不计终止 NUL。
- `policy.json` 是精确配置，不由候选 PR 放宽。`exceptions.json` 是精确历史例外数据。
  本次采用阶段 A 缩路径后的 **空例外集合**，来源提交记为
  `79bb2d888e2e3ce9dba2281b75a2f32f814ed9a6`，绝不沿用旧审计的 178 条债务。
- 已对阶段 A 提供的真实 Git tree/index 输出清单独立扫描：81,821 条，最大179，新增/历史/stale均0。
  结果随交付包 `evidence/after-object-verification.json` 提供。本地对象树通过不等于生产仓库已 apply，也不证明 Windows/Flash 实际兼容。
- 仅阻断从 base 到 head **新出现的精确路径**进入两个退休根（前缀采用保守Unicode casefold匹配，防止ASCII大小写绕过）：
  `tools/cf6-elder-assets/evidence/20261017-calibration` 和
  `tools/cf6-elder-assets/evidence/20261018-loader-size-followup`。
  已存在精确路径的内容更新不受这条规则影响；其它 evidence 根不被笼统禁止。
  这条规则只覆盖被审计 Git 树，不监视未跟踪文件或自动执行封存脚本。

## 可信本地 Git 对象入口（首要可执行交付）

从已审核版本复制本目录到独立可信目录，在空工作目录运行；不要运行候选工作树中的检查器：

```sh
python3 -I -S /trusted/path-budget/git_gate.py \
  --repo /existing/repository-or-bare.git \
  --base FULL_IMMUTABLE_BASE_COMMIT_SHA \
  --head FULL_IMMUTABLE_HEAD_COMMIT_SHA \
  --json /outside-the-repository/path-budget-result.json
```

- `base/head` 只接受完整小写40或64位对象 ID；不是 `HEAD`、分支名、短 SHA 或 shell 表达式。
- 本地对象库需预先含完整 commit/tree 元数据，以及 base/head 的 policy、exceptions 小 blob；无需其它素材 blob。
  本入口**不负责网络获取**。缺对象就报不完整，禁用 promisor lazy fetch、所有 Git 网络协议、replacement objects 和 ambient Git 环境变量。
- 只读 `cat-file` 和 `ls-tree -r -t -z --full-tree`。无 checkout、index/工作树变更、hook、filter、smudge、LFS、递归 submodule 或仓库代码执行。
  每个目录 tree SHA 都按原始 Git 编码重算，绑定 commit→root tree；少目录、少条目、截断、重复条目或非法 UTF-8 不得成为通过。
- policy/例外仅按树内精确路径、regular blob mode读取；限制2MiB并重算 blob hash。候选文件只做严格JSON解析，拒绝重复键、NaN/Infinity。
- 可信 base 配置是比较参考。非可信目标分支可加 `--trust FULL_REVIEWED_MAIN_SHA`，先验证 base 配置/例外没有相对该可信锚扩容。
- 代码必须来自已有明确审核的信任锚；一个完整 SHA 只解决定位，不会自动授予信任。
- 所有工作流目录改动、工具实现改动与两份配置改动分别输出为 `workflow/implementation/configuration` 边界。
  输出标记不会授权执行候选实现，也不是工作流防篡改机制。

## 例外生命周期

例外键为原始精确路径，含 `category/reason/rules`，不绑定内容 SHA，不支持 glob。

| 变化 | 结果 |
|---|---|
| 原精确路径只改内容 | 已有例外可保留 |
| 新增超限或移动后仍超限 | 新精确路径失败，目录后代逐项检查 |
| 缩短/删除路径但保留例外 | stale，要求同批删除 |
| 缩短/删除路径并清例外 | 通过 |
| 删除仍超限路径的例外 | 变成新违规，失败 |
| 新增/修改例外、rules、原因、元数据，或修改policy/退休根 | 不完整/政策拒绝，不能自批扩容 |
| 缺少/格式坏/无法读取baseline | 不完整，不回退到空集合 |

例外政策确需变化，必须独立明确审核并建立新的可信起点；本工具没有生成、扩容或自动修剪baseline的命令。

## 普通 PR/main 只读 CI 候选

工作流不设 `paths` 或 PR 分支过滤。所有 opened/synchronize/reopened/edited/ready_for_review PR（含draft/fork、素材、文档、无扩展名）以及 main push进入同一 job。
它只有 `contents:read`，不使用用户 secrets/PAT/OIDC、self-hosted runner、环境、cache、业务依赖、checkout 或任何第三方 Action。

1. 工作流内联 `ci_bootstrap.py` 的标准库代码，冻结平台事件的仓库和 SHA。
2. PR目标main时，只下载 **event.base.sha** 的已审核三份执行文件；非main目标先冻结同仓main作为执行锚。
   main push使用 **before**，绝不自动回退到 PR head/merge 或 push after中的检查器。
3. 逐层读取 tools/path-budget 的树元数据，验证small blob mode/大小/hash，写入空临时目录。
   随后 `python -I -S` 执行受信 `github_gate.py`。候选 checker/tests/local action 从不执行、import或安装。
4. 获取固定base/head的commit/root tree和全量目录元数据。递归API被截断时，逐层尝试较小完整递归子树，只有仍截断的节点才直接展开；最终重算每个tree SHA。
   不用搜索或PR files接口代替全树。fork head在base仓库404时，仅回退至已核对事件仓库ID的对应fork。
5. 仅读取policy/例外两个bounded JSON blob。未知子模块不展开，明确incomplete；空树、限流、网络/读取失败也不通过。
6. 始终扫描head；平台提供本次merge SHA时，先验证其两个parents精确为本次base/head再另扫集成树。
   merge取不到或parents不符时明确head-only，不宣称最终集成通过；已验证merge的扫描/政策错误不能降级成绿色。
7. 机器可读紧凑JSON保存至临时文件，并以固定 `PATH_BUDGET_REPORT_JSON=` 前缀写入持久运行日志。
   无素材/可执行产物上传。所有路径日志按JSON转义；不插入shell、GitHub annotation或工作流命令。

### Bootstrap 必须显式完成

若将checker与workflow同批首次引入，旧base/before中没有受信执行器，CI将明确 **incomplete/exit2**。
不能为了首次变绿执行候选版，不能从候选label/字段自行宣布可信。建议按现有授权的审核/合入流程，
**先审核 `core.patch` 并建立可信main，再单独审核启用 `workflow.patch`**，随后用新普通/fork PR和main push实测。
core-only阶段未安装workflow时，对应内联源码一致性测试明确skip；其余核心测试照常运行。本文不创建或修改required check、branch protection、ruleset、直推政策或仓库设置。

### 普通 workflow 的抗篡改边界

普通 `pull_request` 的workflow本身来自候选合并版本，PR可以修改内联bootstrap、跳过整个job或伪造同名结果。
**即使它下载base版checker，普通workflow也不是权威防篡改入口。** 改动比较器不能解决自身来源问题。
因此本候选适合作为非required报告/失败信号；正式强制前，另行授权审阅可信required workflow或可信默认分支入口及本仓事件策略，
不能仅将同名普通job标required便宣称抗篡改，也不能扩token权限补洞。
此候选未运行GitHub Actions/fork网络验收；事件审批、禁用、缺run、skip指令、merge queue等平台条件仍需实际确认。
它不支持merge_group，未来启用merge queue须另实现并验证，不可默认声称覆盖。

候选实现自己的测试应在**独立、无凭据、无写token**的环境运行；不可在可信元数据job内执行候选tests。

## 通用核心和投影（为后续接线保留，不等于已挂产物门禁）

`path_budget.py` 保留manifest、NUL Git、JSON归档清单和ZIP中央目录输入，以及真实root、prefix、suffix和already_projected：

```sh
python3 /trusted/path-budget/path_budget.py tree.nul --format git-ls-tree-nul --metadata tree-metadata.json --json result.json
python3 /trusted/path-budget/path_budget.py outputs.json --root 'C:\\short' --prefix obj/candidate --suffix .runtimeconfig.json --json outputs-result.json
python3 /trusted/path-budget/path_budget.py candidate.zip --format zip --already-projected --root-units 60 --json zip-result.json
```

Git路径必须NUL分隔；保留空格、引号、TAB、真实换行及非BMP字符。UTF-16不正规化。实际root带尾分隔符时不重复连接。
已完整投影的条目不重复追加prefix/suffix；源树例外不能用来豁免不同root或产物投影。
ZIP只读中央目录不解压；7z/SFX、未跟踪产物、Unity额外树、真实安装/临时根未因此被验证。
这些通用入口的完整性声明由调用方负责；可信Git对象入口另提供真实元数据校验。

## 测试与退出码

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tools/path-budget -p 'test_*.py' -v
```

测试包括真实本地bare Git SHA-1/SHA-256对象、特殊名字、内容修改、多个后代移动、stale清理、不可扩容、退休根、
完整/截断API、fork身份、小blob损坏、bootstrap不退回候选及候选cwd模块注入隔离。网络由fixtures模拟，不冒充GitHub实测。
施工包另附 `evidence/test-results.txt` 实测记录和 `evidence/after-object-verification.json` 本地Git tree/index输出扫描记录；这些一次性证据不进入项目常驻工具，也不是可变未来源码的授权。

退出码：0=完整且无新增/stale/退休根违规；1=路径/例外清理失败；2=不完整/输入/政策/信任/读取错误。
报告模式保留实际退出码。长路径合格仍不覆盖保留名、大小写碰撞、尾随点空格、NTFS/Flash工具链的其它兼容条件。
