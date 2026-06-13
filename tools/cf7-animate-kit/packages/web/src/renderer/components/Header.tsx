import type { MotionLevel } from "./motion-utils.js";

type TabId = "an" | "sol";

const MOTION_OPTIONS: Array<{ value: MotionLevel; label: string }> = [
  { value: "off", label: "关闭" },
  { value: "light", label: "轻量" },
  { value: "standard", label: "标准" }
];

const TAB_OPTIONS: Array<{ value: TabId; label: string }> = [
  { value: "an", label: "AN 维护" },
  { value: "sol", label: "SOL 检视/编辑" }
];

interface Props {
  tab: TabId;
  onTabChange: (tab: TabId) => void;
  versions: Record<string, string>;
  motionPreference: MotionLevel;
  onMotionChange: (level: MotionLevel) => void;
  onResetLayout: () => void;
}

export default function Header({
  tab, onTabChange, versions, motionPreference, onMotionChange, onResetLayout
}: Props) {
  return (
    <header className="header app-header">
      <div className="app-title header-title-group">
        <span className="app-mark">CF7</span>
        <span>Animate Kit · 驾驶舱</span>
      </div>

      <nav className="app-tabs" aria-label="主功能">
        {TAB_OPTIONS.map((option) => (
          <button
            key={option.value}
            type="button"
            className={`app-tab ${tab === option.value ? "active" : ""}`}
            onClick={() => onTabChange(option.value)}
            aria-pressed={tab === option.value}
          >
            {option.label}
          </button>
        ))}
      </nav>

      <div className="header-actions">
        <div className="motion-controls" aria-label="动效档位">
          <span className="motion-label">动效</span>
          <div className="motion-toggle" role="group" aria-label="动画强度">
            {MOTION_OPTIONS.map((option) => (
              <button
                key={option.value}
                type="button"
                className={`motion-toggle-btn ${motionPreference === option.value ? "active" : ""}`}
                onClick={() => onMotionChange(option.value)}
                aria-pressed={motionPreference === option.value}
              >
                {option.label}
              </button>
            ))}
          </div>
        </div>
        <button className="btn-small" onClick={onResetLayout} title="恢复默认分栏比例">重置布局</button>
        <span className="app-version" title="Electron / Node">
          E{versions["electron"] ?? "?"} · N{versions["node"] ?? "?"}
        </span>
      </div>
    </header>
  );
}
