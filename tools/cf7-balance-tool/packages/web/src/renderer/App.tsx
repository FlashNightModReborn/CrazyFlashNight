import rawFieldUsageReport from "../../../../reports/field-usage-report.json";

import type { FieldScanReport, FieldUsageRecord } from "@cf7-balance-tool/core";

const fieldUsageReport = rawFieldUsageReport as FieldScanReport;

const 已确认边界 = [
  ["插件范围", "v1 仅做 CRUD，不做插件数值引擎"],
  ["公式输出", "只读参考值，不回写 XML"],
  ["前端语言", "中文默认，后续再补多语言能力"],
  ["变更追踪", "以 Git diff 为主，changelog 为辅助输出"]
] as const;

const 模块看板 = [
  {
    标题: "字段扫描",
    状态: "已接线",
    说明: `首轮扫描已覆盖 ${格式化数字(fieldUsageReport.totals.files)} 个 XML 文件。`
  },
  {
    标题: "XML 读写",
    状态: "下一步",
    说明: "下一阶段将进入 round-trip 解析与回写，目标是最小 diff。"
  },
  {
    标题: "插件系统",
    状态: "CRUD 边界",
    说明: "当前仅处理结构保真读写与查询编辑，不进入插件数值建模。"
  },
  {
    标题: "桌面壳",
    状态: "中文默认",
    说明: "Electron 壳已接入首轮报告，后续继续接 diff 与校验面板。"
  }
] as const;

const 高频未分类字段 = fieldUsageReport.usage
  .filter((item) => item.classification === "unknown")
  .slice(0, 6);

const 高频已识别字段 = fieldUsageReport.usage
  .filter((item) => item.classification !== "unknown")
  .slice(0, 6);

const 扫描指标 = [
  { 标签: "扫描文件", 数值: 格式化数字(fieldUsageReport.totals.files) },
  { 标签: "字段名", 数值: 格式化数字(fieldUsageReport.totals.fields) },
  {
    标签: "字段出现次数",
    数值: 格式化数字(fieldUsageReport.totals.occurrences)
  },
  {
    标签: "未分类字段",
    数值: 格式化数字(fieldUsageReport.totals.unknownFields)
  }
] as const;

export function App() {
  const runtime = window.cf7Balance?.runtime === "electron" ? "桌面模式" : "预览模式";
  const versions = window.cf7Balance?.versions;

  return (
    <main className="app-shell">
      <section className="hero">
        <div className="hero-copy">
          <p className="eyebrow">闪客快打 7 · 佣兵帝国</p>
          <h1>数值平衡工作台</h1>
          <p className="lede">
            面向 XML 数据、CLI 自动化和桌面编辑器的统一工作台。当前前端默认使用中文，
            并已接入首轮字段扫描结果，后续将继续推进 XML round-trip 与差异审阅能力。
          </p>
        </div>

        <div className="runtime-panel">
          <span className="runtime-badge">{runtime}</span>
          <dl>
            <div>
              <dt>Node</dt>
              <dd>{versions?.node ?? "待接线"}</dd>
            </div>
            <div>
              <dt>Electron</dt>
              <dd>{versions?.electron ?? "待接线"}</dd>
            </div>
            <div>
              <dt>报告生成时间</dt>
              <dd>{格式化时间(fieldUsageReport.generatedAt)}</dd>
            </div>
          </dl>
          <p className="runtime-hint">
            数据来源：<code>reports/field-usage-report.json</code>
          </p>
        </div>
      </section>

      <section className="module-grid">
        {模块看板.map((card) => (
          <article className="module-card" key={card.标题}>
            <div className="module-topline">
              <h2>{card.标题}</h2>
              <span>{card.状态}</span>
            </div>
            <p>{card.说明}</p>
          </article>
        ))}
      </section>

      <section className="content-grid">
        <article className="panel">
          <div className="panel-header">
            <p>已确认边界</p>
            <h3>当前 v1 范围</h3>
          </div>
          <div className="decision-table">
            {已确认边界.map(([label, value]) => (
              <div className="decision-row" key={label}>
                <span>{label}</span>
                <strong>{value}</strong>
              </div>
            ))}
          </div>
        </article>

        <article className="panel">
          <div className="panel-header">
            <p>扫描概览</p>
            <h3>首轮字段基线</h3>
          </div>
          <div className="metric-grid">
            {扫描指标.map((metric) => (
              <div className="metric-card" key={metric.标签}>
                <span>{metric.标签}</span>
                <strong>{metric.数值}</strong>
              </div>
            ))}
          </div>
          <p className="report-note">
            当前扫描器是 Phase 0 的词法级清点器，已经足够做字段库存与缺口识别，但还不是
            round-trip 解析器。
          </p>
        </article>
      </section>

      <section className="content-grid content-grid-lower">
        <article className="panel">
          <div className="panel-header">
            <p>待补齐</p>
            <h3>高频未分类字段</h3>
          </div>
          <div className="field-list">
            {高频未分类字段.map((item) => (
              <FieldRecordCard key={item.field} item={item} emphasize="warning" />
            ))}
          </div>
        </article>

        <article className="panel">
          <div className="panel-header">
            <p>已识别</p>
            <h3>高频字段样本</h3>
          </div>
          <div className="field-list">
            {高频已识别字段.map((item) => (
              <FieldRecordCard key={item.field} item={item} emphasize="normal" />
            ))}
          </div>
        </article>
      </section>
    </main>
  );
}

function FieldRecordCard({
  item,
  emphasize
}: {
  item: FieldUsageRecord;
  emphasize: "warning" | "normal";
}) {
  return (
    <article className={`field-card field-card-${emphasize}`}>
      <div className="field-card-topline">
        <h4>{item.field}</h4>
        <span>{item.classification === "unknown" ? "未分类" : 翻译分类(item.classification)}</span>
      </div>
      <div className="field-meta">
        <span>出现 {格式化数字(item.occurrences)} 次</span>
        <span>{item.entityKinds.join(" / ")}</span>
      </div>
      <p className="field-sample">{item.samplePaths[0]}</p>
    </article>
  );
}

function 翻译分类(value: FieldUsageRecord["classification"]): string {
  switch (value) {
    case "numeric":
      return "数值";
    case "nested-numeric":
      return "嵌套数值";
    case "string":
      return "字符串";
    case "boolean":
      return "布尔";
    case "attribute":
      return "属性";
    case "item-level":
      return "物品级字段";
    case "passthrough":
      return "透传";
    case "computed":
      return "派生";
    default:
      return "未知";
  }
}

function 格式化数字(value: number): string {
  return new Intl.NumberFormat("zh-CN").format(value);
}

function 格式化时间(value: string): string {
  return new Intl.DateTimeFormat("zh-CN", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit"
  }).format(new Date(value));
}