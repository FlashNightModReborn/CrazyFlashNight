import type { BrowserWindow } from "electron";
import type { FSWatcher } from "node:fs";
import type { PackConfig, PackerEngine } from "@cf7-packer/core";

/**
 * IPC handler 共享上下文。
 * main.ts 创建实例，各 handler 模块通过 register(ctx) 访问。
 */
export interface IpcContext {
  readonly configPath: string;
  readonly toolRoot: string;
  getMainWindow: () => BrowserWindow | null;
  getConfig: () => PackConfig;
  sendToRenderer: (channel: string, data: unknown) => void;

  /** 打包引擎运行状态（可变） */
  engine: PackerEngine | null;
  engineRunning: boolean;
  readonly knownOutputDirs: Set<string>;

  /** 配置文件 watcher（由 ipc-watch-handler 设置，will-quit 时清理） */
  configWatcher?: FSWatcher | undefined;
  /** 上次自写配置文件的时间戳，用于 watcher 自写抑制（R1） */
  lastConfigWriteAt: number;
}
