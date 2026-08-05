# Prime Magic 19

已完成的 19 阶质数幻方离线编译器与 Web orbit runtime。交付包含 8 张真实完整 seed；每张均由原 361 个互异质数经行列双置换得到，19 行、19 列和两条主对角线都严格等于 `190000361`。

## 核心结果

| 项目 | 结果 |
| --- | --- |
| 输入 | 有效质数半幻方；对角残差 `(-25098,+92520)` |
| 完整 seed | 8 张正式 seed + 1 张独立 VNS witness |
| seed00 canonical SHA-256 | `a5e002e9047e02dba2608428ef7416493a0b1ce9148e6e77f3d57be04084413d` |
| seed00 binary SHA-256 | `5867419cf02b32838f4fd5f369a031a4d552b99153e2f78ee897019fcf6fce61` |
| 单 seed 轨道 | 精确 `743,178,240` 个状态 |
| 8 seed 总轨道 | 精确 `5,945,425,920` 个不交状态 |
| TypeScript 热路径 | Median `1.091 µs`，P99 `1.572 µs`（Node/V8，本机） |
| WASM | 不需要 |

## 目录

- `seeds/`：8 组 JSON、1460-byte PM19 binary、逐 seed 验证报告、manifest 与 checkpoint。
- `python/prime_magic/compiler.py`：路线 A 两阶段 seed compiler。
- `python/prime_magic/verify.py`：不导入 compiler 的独立确定性验证器。
- `python/verify_manifest.py`：整库 SHA/格式/数学不变量复核。
- `runtime/`：TypeScript orbit engine、Worker、WebGL2 demo、测试与基准。
- `reports/AUDIT_REPORT.md`：主审计报告与最终十项决策。
- `reports/MATHEMATICAL_PROOFS.md`：双置换等价归约、运行时不变量、群阶与稳定子证明。
- `reports/ORBIT_AND_TRADES.md`：trade 完整枚举、增量公式、连通性边界。
- `reports/PERFORMANCE_REPORT.md`：离线、Node、浏览器基准状态和渲染比较。
- `reports/code_audit/review.md`：独立反例驱动代码复审与唯一剩余规格差距。

## 一键复核

Python 主实现仅依赖标准库，建议 Python 3.11+：

```bash
export PYTHONPATH="$PWD/python"
python -m unittest discover -s python/tests -v
python python/verify_manifest.py seeds/manifest.json \
  --source fixtures/prime_semimagic_19.json \
  --output reports/manifest_verification.json
python python/cross_validate_seed00.py
```

生成或从 checkpoint 恢复 8 张正式 seed：

```bash
export PYTHONPATH="$PWD/python"
python -m prime_magic.compiler fixtures/prime_semimagic_19.json \
  --output-dir seeds --seed 20260805 --count 8 --workers 1 \
  --outer-attempts 64 --assignment-restarts 128 --assignment-steps 256 \
  --involution-restarts 128 --involution-steps 512 \
  --checkpoint seeds/checkpoint.json --log reports/compiler_runs.jsonl
```

若已有 checkpoint，编译器会复核已完成 artifact 的路径、file SHA 与独立验证报告后跳过完成 job。checkpoint 是 seed-job 粒度；中断发生在单个 in-flight 搜索内时会重做该 job。当前实例 P99 search 约 0.293 s；若把 exact tail 扩为小时级任务，需要继续实现 DFS frontier/PRNG 节点级恢复。

TypeScript：

```bash
cd runtime
npm ci
npm run test:all
BENCH_REPORT=../reports/node_runtime_benchmark.json npm run bench
npm run demo
```

打开 `http://127.0.0.1:4173/` 查看 WebGL2 demo，或打开 `/web/benchmark.html` 运行 Chromium main/Worker、DOM、Canvas2D、WebGL2 与内存/GC 基准。

## 运行时边界

运行时不搜索、不判质数、不失败重试，也不逐帧复算行列。它只从已验证 seed 均匀抽取数学上保证合法的坐标群元素，并搬运 361 个 U32。默认建议真实棋盘 10 Hz；锁定 5 Hz；故障/重洗 20–30 Hz；视觉 shader 独立运行于 60–144 Hz。

当前云端 Chromium 因安全策略不能访问容器 localhost，所以浏览器/GPU 数字被明确标为未测；可执行基准页已经交付，Node 数据没有冒充浏览器数据。另一个明确限制是 checkpoint 只恢复已完成 seed job，不恢复 in-flight 搜索状态。
