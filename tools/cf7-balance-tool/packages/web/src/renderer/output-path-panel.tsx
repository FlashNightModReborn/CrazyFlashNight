import type { ChangeEvent } from "react";

import {
  OUTPUT_PATH_FIELDS,
  type OutputPathSettingKey,
  type OutputPathSettings
} from "../shared/output-path-settings";

const TEXT = {
  title: "\u8f93\u51fa\u8def\u5f84",
  hintDesktop:
    "\u652f\u6301\u76f8\u5bf9 tools/cf7-balance-tool \u6839\u76ee\u5f55\u6216\u7edd\u5bf9\u8def\u5f84\u3002\u4fdd\u5b58\u540e\u684c\u9762\u52a8\u4f5c\u4f1a\u7acb\u5373\u5207\u6362\u5230\u65b0\u4f4d\u7f6e\u3002",
  hintPreview: "\u5f53\u524d\u662f\u9884\u89c8\u6a21\u5f0f\uff0c\u4ec5\u5c55\u793a\u9ed8\u8ba4\u8f93\u51fa\u8def\u5f84\u3002",
  activePath: "\u5f53\u524d\u751f\u6548",
  settingsFile: "\u914d\u7f6e\u6587\u4ef6",
  pendingHint: "\u672a\u4fdd\u5b58\u6539\u52a8\u4ec5\u5f71\u54cd\u8868\u5355\uff0c\u4e0d\u4f1a\u6539\u53d8\u684c\u9762\u52a8\u4f5c\u7684\u771f\u5b9e\u8f93\u51fa\u4f4d\u7f6e\u3002",
  save: "\u4fdd\u5b58\u8def\u5f84\u914d\u7f6e",
  reset: "\u6062\u590d\u9ed8\u8ba4\u8def\u5f84",
  workingSave: "\u6b63\u5728\u4fdd\u5b58\u8def\u5f84...",
  workingReset: "\u6b63\u5728\u6062\u590d\u9ed8\u8ba4\u8def\u5f84...",
  copySettings: "\u590d\u5236\u914d\u7f6e\u8def\u5f84",
  revealSettings: "\u5b9a\u4f4d\u914d\u7f6e\u6587\u4ef6",
  browse: "\u6d4f\u89c8"
} as const;

export function OutputPathPanel({
  canCopyPath,
  canManage,
  canRevealPath,
  draftSettings,
  resolvedSettings,
  settingsFile,
  busyAction,
  hasPendingChanges,
  onChange,
  onBrowse,
  onCopyPath,
  onRevealPath,
  onReset,
  onSave,
  formatPath
}: {
  canCopyPath: boolean;
  canManage: boolean;
  canRevealPath: boolean;
  draftSettings: OutputPathSettings;
  resolvedSettings: OutputPathSettings;
  settingsFile: string;
  busyAction: "save" | "reset" | null;
  hasPendingChanges: boolean;
  onChange: (key: OutputPathSettingKey, value: string) => void;
  onBrowse: (key: OutputPathSettingKey, currentValue: string) => Promise<void>;
  onCopyPath: (targetPath: string) => Promise<void>;
  onRevealPath: (targetPath: string) => Promise<void>;
  onReset: () => Promise<void>;
  onSave: () => Promise<void>;
  formatPath: (value: string) => string;
}) {
  const canEdit = canManage && busyAction === null;

  return (
    <section className="detail-section">
      <div className="detail-section-header">
        <h4>{TEXT.title}</h4>
      </div>
      <p className="panel-caption">{canManage ? TEXT.hintDesktop : TEXT.hintPreview}</p>

      <div className="output-path-grid">
        {OUTPUT_PATH_FIELDS.map((field) => (
          <label className="output-path-field" key={field.key}>
            <span>{field.label}</span>
            <div className="output-path-input-row">
              <input
                disabled={!canEdit}
                onChange={(event: ChangeEvent<HTMLInputElement>) =>
                  onChange(field.key, event.currentTarget.value)
                }
                spellCheck={false}
                value={draftSettings[field.key]}
              />
              <button
                className="mini-button mini-button-ghost"
                disabled={!canEdit}
                onClick={() => void onBrowse(field.key, draftSettings[field.key])}
                type="button"
              >
                {TEXT.browse}
              </button>
            </div>
            <small>
              {TEXT.activePath}\uff1a{formatPath(resolvedSettings[field.key])}
            </small>
          </label>
        ))}
      </div>

      <div className="output-path-meta">
        <span>
          {TEXT.settingsFile}\uff1a{formatPath(settingsFile)}
        </span>
        <div className="artifact-actions">
          <button
            className="mini-button mini-button-ghost"
            disabled={!canCopyPath}
            onClick={() => void onCopyPath(settingsFile)}
            type="button"
          >
            {TEXT.copySettings}
          </button>
          <button
            className="mini-button"
            disabled={!canRevealPath || !canManage}
            onClick={() => void onRevealPath(settingsFile)}
            type="button"
          >
            {TEXT.revealSettings}
          </button>
        </div>
      </div>

      {hasPendingChanges ? <p className="panel-caption">{TEXT.pendingHint}</p> : null}

      <div className="bridge-actions">
        <button
          className="action-button"
          disabled={!canManage || !hasPendingChanges || busyAction !== null}
          onClick={() => void onSave()}
          type="button"
        >
          {busyAction === "save" ? TEXT.workingSave : TEXT.save}
        </button>
        <button
          className="action-button action-button-ghost"
          disabled={!canManage || busyAction !== null}
          onClick={() => void onReset()}
          type="button"
        >
          {busyAction === "reset" ? TEXT.workingReset : TEXT.reset}
        </button>
      </div>
    </section>
  );
}

