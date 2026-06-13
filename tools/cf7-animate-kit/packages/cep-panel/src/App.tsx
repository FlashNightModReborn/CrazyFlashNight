/**
 * App.tsx — CF7 AnimateKit panel root (uplifted shell).
 *  - Header: title + a motion-level toggle (off / light / standard).
 *  - Doctor capability strip (probe: flVersion + capability flags) pinned below.
 *  - A clean tab bar (Linkage / Export / Frame labels); active tab persisted.
 *  - Motion is CSS-driven: the shell publishes a small set of custom properties
 *    and a `motion-<level>` body class; nothing here changes the bridge contract.
 */
import { useMemo, useState } from 'react';
import type { CSSProperties } from 'react';
import { Doctor } from './components/Doctor.js';
import { LinkageTab } from './components/LinkageTab.js';
import { ExportTab } from './components/ExportTab.js';
import { FrameLabelsTab } from './components/FrameLabelsTab.js';
import { AdvancedTab } from './components/AdvancedTab.js';
import { LibraryFramesFiltersTab } from './components/LibraryFramesFiltersTab.js';
import { PresetsBitmapDiagTab } from './components/PresetsBitmapDiagTab.js';
import { getMotionProfile, MOTION_OPTIONS, type MotionLevel } from './components/motion-utils.js';
import { useStoredString } from './hooks/useLocalStorage.js';

type TabId = 'linkage' | 'export' | 'labels' | 'advanced' | 'lff' | 'pbd';

const TABS: ReadonlyArray<{ id: TabId; label: string; icon: string }> = [
  { id: 'linkage', label: 'Linkage', icon: '🔗' },
  { id: 'export', label: 'Export', icon: '🖼' },
  { id: 'labels', label: 'Frame labels', icon: '🏷' },
  { id: 'advanced', label: 'Advanced', icon: '⚙' },
  { id: 'lff', label: '库/帧/滤镜', icon: '🧰' },
  { id: 'pbd', label: '预设/位图/诊断', icon: '🧪' },
];

const VALID_TABS = new Set<TabId>(['linkage', 'export', 'labels', 'advanced', 'lff', 'pbd']);

export function App() {
  const [storedTab, setStoredTab] = useStoredString<TabId>('cf7ak:active-tab', 'linkage');
  const tab: TabId = VALID_TABS.has(storedTab) ? storedTab : 'linkage';

  const [hostReady, setHostReady] = useState(false);

  const [motionPreference, setMotionPreference] = useStoredString<MotionLevel>(
    'cf7ak:motion-level',
    'light',
  );
  const motionProfile = useMemo(() => getMotionProfile(motionPreference), [motionPreference]);
  const motionStyle = useMemo(
    () =>
      ({
        '--motion-settle-ms': `${motionProfile.settleMs}ms`,
        '--motion-emphasis-ms': `${motionProfile.emphasisMs}ms`,
        '--motion-surface-lift': `${motionProfile.surfaceLift}px`,
      }) as CSSProperties,
    [motionProfile],
  );

  return (
    <div className={`app motion-${motionProfile.level}`} style={motionStyle}>
      <header className="app-header">
        <div className="app-header-titles">
          <span className="app-title">CF7 AnimateKit</span>
          <span className={`app-status ${hostReady ? 'app-status-ok' : 'app-status-warn'}`}>
            {hostReady ? 'ready' : 'idle'}
          </span>
        </div>
        <div className="motion-toggle" role="group" aria-label="Motion level">
          {MOTION_OPTIONS.map((o) => (
            <button
              key={o.value}
              type="button"
              className={`motion-toggle-btn ${motionPreference === o.value ? 'active' : ''}`}
              aria-pressed={motionPreference === o.value}
              onClick={() => setMotionPreference(o.value)}
              title={`Motion: ${o.label}`}
            >
              {o.label}
            </button>
          ))}
        </div>
      </header>

      <Doctor onStatus={setHostReady} />

      <nav className="tabbar" role="tablist">
        {TABS.map((t) => (
          <button
            key={t.id}
            role="tab"
            aria-selected={tab === t.id}
            className={`tab ${tab === t.id ? 'tab-active' : ''}`}
            onClick={() => setStoredTab(t.id)}
          >
            <span className="tab-icon" aria-hidden>
              {t.icon}
            </span>
            {t.label}
          </button>
        ))}
      </nav>

      <main className="content">
        {/* Tabs stay mounted-on-demand but keyed so motion re-triggers per switch. */}
        {tab === 'linkage' && <LinkageTab motionMs={motionProfile.settleMs} />}
        {tab === 'export' && <ExportTab motionMs={motionProfile.settleMs} />}
        {tab === 'labels' && <FrameLabelsTab motionMs={motionProfile.settleMs} />}
        {tab === 'advanced' && <AdvancedTab motionMs={motionProfile.settleMs} />}
        {tab === 'lff' && <LibraryFramesFiltersTab motionMs={motionProfile.settleMs} />}
        {tab === 'pbd' && <PresetsBitmapDiagTab motionMs={motionProfile.settleMs} />}
      </main>
    </div>
  );
}
