import { useMemo, useCallback } from "react";
import type { CSSProperties } from "react";
import { AnkitApiProvider, useAnkitApi } from "./contexts/AnkitApiContext.js";
import Header from "./components/Header.js";
import MaintenancePanel from "./components/MaintenancePanel.js";
import SolPanel from "./components/SolPanel.js";
import {
  getMotionProfile, resolveMotionLevel, type MotionLevel
} from "./components/motion-utils.js";
import { useStoredString } from "./hooks/useLocalStorage.js";
import { usePrefersReducedMotion } from "./hooks/usePrefersReducedMotion.js";
import { useLayoutResize } from "./hooks/useLayoutResize.js";

type TabId = "an" | "sol";

const TAB_KEY = "ankit:active-tab";
const MOTION_KEY = "ankit:motion-level";

function Cockpit() {
  const api = useAnkitApi();

  const [tab, setTab] = useStoredString<TabId>(TAB_KEY, "an");

  // Motion preferences (mirrors cf7-packer: stored level, capped by OS setting).
  const [motionPreference, setMotionPreference] = useStoredString<MotionLevel>(MOTION_KEY, "light");
  const prefersReducedMotion = usePrefersReducedMotion();
  const motionLevel = useMemo(
    () => resolveMotionLevel(motionPreference, prefersReducedMotion),
    [motionPreference, prefersReducedMotion]
  );
  const motionProfile = useMemo(() => getMotionProfile(motionLevel), [motionLevel]);
  const motionStyle = useMemo(() => ({
    "--motion-settle-ms": `${motionProfile.settleMs}ms`,
    "--motion-emphasis-ms": `${motionProfile.emphasisMs}ms`,
    "--motion-overlay-opacity": String(motionProfile.overlayOpacity),
    "--motion-surface-lift": `${motionProfile.surfaceLift}px`
  }) as CSSProperties, [motionProfile]);

  const layout = useLayoutResize(motionProfile);

  // Panels persist their own split fractions; broadcast a reset so the active
  // one restores its default + plays a settle animation.
  const handleResetLayout = useCallback(() => {
    window.dispatchEvent(new CustomEvent("ankit:reset-layout"));
    layout.startLayoutSettle();
  }, [layout]);

  if (!api || api.runtime !== "electron") {
    return (
      <div className="app-placeholder">
        <h1>CF7 Animate Kit · 驾驶舱</h1>
        <p>请通过 launch.bat 启动 Electron 环境。</p>
      </div>
    );
  }

  const appClassName = [
    "app",
    `motion-${motionLevel}`,
    layout.isLayoutResizing ? "is-layout-resizing" : "",
    layout.isLayoutSettling ? "is-layout-settling" : ""
  ].filter(Boolean).join(" ");

  return (
    <div className={appClassName} style={motionStyle}>
      <Header
        tab={tab}
        onTabChange={setTab}
        versions={api.versions}
        motionPreference={motionPreference}
        onMotionChange={setMotionPreference}
        onResetLayout={handleResetLayout}
      />

      <main className="app-main">
        {tab === "an" ? (
          <MaintenancePanel api={api} motionLevel={motionLevel} layout={layout} />
        ) : (
          <SolPanel api={api} motionLevel={motionLevel} motionProfile={motionProfile} layout={layout} />
        )}
      </main>
    </div>
  );
}

export default function App() {
  return (
    <AnkitApiProvider>
      <Cockpit />
    </AnkitApiProvider>
  );
}
