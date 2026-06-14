import { dialog, ipcMain } from "electron";
import fs from "node:fs";
import { readSol, writeSol } from "@cf7-animate-kit/core";
import { backupFile } from "@cf7-animate-kit/an-host";
import type { IpcContext } from "./ipc-context.js";
import { buildSolTree, buildSolMeta, applyEdits } from "./sol-model.js";
import type {
  OpenSolResult,
  SolDocument,
  SolSaveRequest,
  SolSavePreview,
  SolSaveResult,
} from "../shared/ipc-types.js";

/** Read a .sol from disk and project it into a renderer document. */
function readDocument(filePath: string): SolDocument {
  const buf = fs.readFileSync(filePath);
  const sol = readSol(buf);
  return {
    filePath,
    meta: buildSolMeta(sol, buf.length),
    tree: buildSolTree(sol),
  };
}

export function registerSolHandlers(ctx: IpcContext): void {
  // --- open a .sol via dialog and project it to a tree ---
  ipcMain.handle("ankit:open-sol", async (): Promise<OpenSolResult> => {
    const win = ctx.getMainWindow();
    if (!win) return { canceled: true };
    const res = await dialog.showOpenDialog(win, {
      title: "打开 SharedObject (.sol)",
      properties: ["openFile"],
      filters: [
        { name: "Flash SharedObject", extensions: ["sol"] },
        { name: "All files", extensions: ["*"] },
      ],
    });
    if (res.canceled || res.filePaths.length === 0) return { canceled: true };
    const filePath = res.filePaths[0]!;
    try {
      return { canceled: false, doc: readDocument(filePath) };
    } catch (err) {
      return { canceled: false, error: String(err) };
    }
  });

  // --- preview a pending save: rebuild + diff, never touch disk ---
  ipcMain.handle("ankit:preview-sol-save", (_e, req: SolSaveRequest): SolSavePreview => {
    try {
      const buf = fs.readFileSync(req.filePath);
      const sol = readSol(buf);
      const outcome = applyEdits(sol, req.edits);
      const rebuilt = writeSol(sol);
      return {
        ok: outcome.ok,
        diff: outcome.diff,
        newFileSize: rebuilt.length,
      };
    } catch (err) {
      return { ok: false, error: String(err), diff: [], newFileSize: 0 };
    }
  });

  // --- save: re-read -> apply -> backup -> writeSol -> overwrite, then reload ---
  ipcMain.handle("ankit:save-sol", (_e, req: SolSaveRequest): SolSaveResult => {
    try {
      const buf = fs.readFileSync(req.filePath);
      const sol = readSol(buf);
      const outcome = applyEdits(sol, req.edits);
      if (!outcome.ok) {
        const firstErr = outcome.diff.find((d) => d.error)?.error ?? "存在无法应用的编辑";
        return { ok: false, error: firstErr };
      }
      const rebuilt = writeSol(sol);

      if (!req.apply) {
        // Dry run: report intended backup target without writing.
        return { ok: true, backupPath: null };
      }

      // ALWAYS back up before overwriting.
      const backup = backupFile(req.filePath);
      fs.writeFileSync(req.filePath, rebuilt);
      return {
        ok: true,
        backupPath: backup.backupPath,
        doc: readDocument(req.filePath),
      };
    } catch (err) {
      return { ok: false, error: String(err) };
    }
  });
}
