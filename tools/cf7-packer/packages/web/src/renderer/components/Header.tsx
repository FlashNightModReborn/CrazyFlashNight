import type { PackerConfigSummary } from "../../shared/ipc-types.js";
import type { MotionLevel } from "./motion-utils.js";

const MOTION_OPTIONS: Array<{ value: MotionLevel; label: string }> = [
  { value: "off", label: "关闭" },
  { value: "light", label: "轻量" },
  { value: "standard", label: "标准" }
];

interface HeaderProps {
  config: PackerConfigSummary | null;
  motionPreference: MotionLevel;
  onMotionChange: (level: MotionLevel) => void;
  onResetLayout: () => void;
  onForceReload?: () => void;
}

export default function Header({ config, motionPreference, onMotionChange, onResetLayout, onForceReload }: HeaderProps) {
  return (
    <header className="header">
      <div className="header-title-group">
        <h1>CF7 发行打包工具</h1>
        {config && <span className="config-name">{config.name}</span>}
      </div>
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
        {onForceReload && (
          <button className="btn-small" onClick={onForceReload} title="强制重载配置和预览">
            重载
          </button>
        )}
        <button className="btn-small" onClick={onResetLayout}>重置布局</button>
      </div>
    </header>
  );
}
