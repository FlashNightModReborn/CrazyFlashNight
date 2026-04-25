"""把崩溃前 stdout 日志里的 [run] 行抢救成 partial.json，供 recover.js 出报表。
2026-04-25 死机后用这条恢复 idle/mouse-burst/panel-gobang 共 35 行数据。

用法：
    python launcher/perf/tools/salvage-from-log.py <log-file> <reportDir>
"""
import json
import re
import sys
from pathlib import Path

if len(sys.argv) != 3:
    print(__doc__)
    sys.exit(2)

log_path = Path(sys.argv[1])
report_dir = Path(sys.argv[2])
report_dir.mkdir(parents=True, exist_ok=True)

# 行格式：
# [run] panel-gobang × backdrop-filter-targeted ... cpu/s=1.689 cv=0.199 runs=5 (28037ms)
pat = re.compile(
    r'^\[run\] (?P<scenario>[\w-]+) × (?P<ablation>[\w-]+) \.\.\. '
    r'cpu/s=(?P<cpu>[\d.]+) cv=(?P<cv>[\d.]+) runs=(?P<runs>\d+) '
    r'\((?P<dt>\d+)ms\)'
)

rows = []
for line in log_path.read_text(encoding='utf-8').splitlines():
    m = pat.match(line.strip())
    if not m:
        continue
    rows.append({
        'scenario': m.group('scenario'),
        'ablation': m.group('ablation'),
        'sampleSec': 3.0,
        'repeats': int(m.group('runs')),
        'cv': float(m.group('cv')),
        'cpuPerSec': float(m.group('cpu')),
        # 缺字段以 0 占位（视觉验收靠截图）
        'scriptPerSec': 0,
        'layoutsPerSec': 0,
        'recalcsPerSec': 0,
        'layoutDurationPerSec': 0,
        'recalcDurationPerSec': 0,
        'longTasks': 0,
        'rafFps': 0,
        'rafMeanMs': 0,
        'compositeFrames': 0,
        'paintUsPerFrame': 0,
        'rasterUsPerFrame': 0,
        'taskDuration': float(m.group('cpu')) * 3.0,
        'scriptDuration': 0,
        'screenshot': 'screenshots/' + m.group('scenario') + '__' + m.group('ablation') + '.png',
        'video': None,
        'errors': 0,
    })

partial = report_dir / 'partial.json'
partial.write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding='utf-8')
print(f'salvaged {len(rows)} rows → {partial}')
