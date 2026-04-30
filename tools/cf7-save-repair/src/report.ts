// 修复报告：markdown（人类可读）+ JSON（程序消费）。

import type { ItemDecision, RepairPlan, ApplyResult } from './repair.js';

export function renderMarkdown(plan: RepairPlan, applied?: ApplyResult): string {
  const sc = plan.scan;
  const lines: string[] = [];
  lines.push('# Save Repair Report');
  lines.push('');
  lines.push('## 扫描结果');
  lines.push(`- 总 fffd 字段数：**${sc.total}**`);
  lines.push(`- L0 阻塞（人工）：${sc.byLayer.L0}`);
  lines.push(`- L1 字典对齐（命中即修，未命中保留占位）：${sc.byLayer.L1}`);
  lines.push(`- L2 字典对齐（命中即修，未命中静默丢弃）：${sc.byLayer.L2}`);
  lines.push(`- L3 静默丢弃：${sc.byLayer.L3}`);
  lines.push('');

  lines.push('## 修复 plan');
  lines.push('| # | path | layer | spot | kind | broken | action | 候选 |');
  lines.push('|---|---|---|---|---|---|---|---|');
  plan.decisions.forEach((d, i) => {
    const candStr = d.candidates.length === 0
      ? '—'
      : d.candidates
          .slice(0, 3)
          .map((c) => `${c.value} *(${c.source}@${c.confidence.toFixed(2)})*`)
          .join('<br>');
    lines.push(
      `| ${i + 1} | \`${d.item.path}\` | ${d.item.layer} | ${d.item.spot} | ${d.item.kind}` +
        ` | ${escapeMd(d.item.brokenString)} | ${actionLabel(d)} | ${candStr} |`,
    );
  });
  lines.push('');

  if (applied) {
    lines.push('## 应用结果');
    lines.push(`- 已修复：${applied.applied}`);
    lines.push(`- 占位：${applied.preserves}`);
    lines.push(`- 丢弃：${applied.drops}`);
    lines.push(`- 待人工：${applied.skippedManual}`);
    if (applied.bumpedLastSaved)
      lines.push(`- lastSaved 已 bump → \`${applied.bumpedLastSaved}\` (INV-1)`);
    lines.push('');
  }

  if (plan.manualRequired > 0) {
    lines.push('## ⚠️ 仍需人工介入');
    lines.push(`共 ${plan.manualRequired} 项无法自动修复（L0 字段或 L1 多候选）。`);
    lines.push('请用 archive-editor 或手工修改对应 path。');
    lines.push('');
  }

  return lines.join('\n');
}

function actionLabel(d: ItemDecision): string {
  switch (d.action.kind) {
    case 'fix_value':           return `✅ fix → \`${escapeMd(d.action.newValue)}\``;
    case 'rename_key':          return `✅ rename key → \`${escapeMd(d.action.newKey)}\``;
    case 'drop_value':          return '🗑 drop value';
    case 'clear_value':         return '🧹 clear (置空)';
    case 'drop_key':            return '🗑 drop key';
    case 'preserve_placeholder': return '📌 placeholder';
    case 'manual_required':     return '⚠️ manual';
  }
}

function escapeMd(s: string): string {
  return s.replace(/\|/g, '\\|').replace(/\n/g, ' ');
}

export function renderJson(plan: RepairPlan, applied?: ApplyResult): unknown {
  return {
    scan: {
      total: plan.scan.total,
      byLayer: plan.scan.byLayer,
    },
    manualRequired: plan.manualRequired,
    willBumpLastSaved: plan.willBumpLastSaved,
    decisions: plan.decisions.map((d) => ({
      path: d.item.path,
      layer: d.item.layer,
      spot: d.item.spot,
      kind: d.item.kind,
      brokenString: d.item.brokenString,
      action: d.action,
      candidates: d.candidates,
    })),
    applied: applied ?? null,
  };
}
