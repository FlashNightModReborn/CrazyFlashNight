import { useEffect, useRef } from "react";
import type { PackerIpcApi, PackerLogEvent, PackerProgressEvent } from "../../shared/ipc-types.js";
import type { MotionLevel } from "../components/motion-utils.js";
import { isProgressOnlyLog } from "../utils/helpers.js";

export interface LogEntry {
  id: number;
  event: PackerLogEvent;
}

let logId = 0;

export function nextLogId(): number {
  return ++logId;
}

export function usePackerEvents(
  api: PackerIpcApi | undefined,
  logs: LogEntry[],
  setLogs: React.Dispatch<React.SetStateAction<LogEntry[]>>,
  setProgress: React.Dispatch<React.SetStateAction<PackerProgressEvent | null>>,
  motionLevel: MotionLevel
) {
  const logEndRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!api) return;
    const offLog = api.onLog((event) => {
      if (isProgressOnlyLog(event)) return;
      setLogs((prev) => [...prev.slice(-500), { id: nextLogId(), event }]);
    });
    const offProgress = api.onProgress((event) => {
      setProgress(event);
    });
    return () => { offLog(); offProgress(); };
  }, [api, setLogs, setProgress]);

  useEffect(() => {
    logEndRef.current?.scrollIntoView({ behavior: motionLevel === "standard" ? "smooth" : "auto" });
  }, [logs, motionLevel]);

  return { logEndRef };
}
