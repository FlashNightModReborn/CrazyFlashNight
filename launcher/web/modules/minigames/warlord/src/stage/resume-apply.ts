import {
  parseStageOuterBinding,
  type StageOuterBindingV1,
} from './outer-authority.js';

const OPAQUE_ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._~-]{0,159}$/;

export interface As2ResumeAppliedV1 {
  schema: 'warlord.as2-resume-apply.v1';
  status: 'applied' | 'frozen';
  inputDigest: string;
  sessionId: string;
  requestId: string;
  stageOuterBinding: StageOuterBindingV1;
}

export type ResumeAppliedSend = (message: As2ResumeAppliedV1) => boolean;

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

export function buildResumeAppliedReceipt(
  resume: unknown,
  binding: unknown,
  status: As2ResumeAppliedV1['status'],
): As2ResumeAppliedV1 | null {
  if (!isRecord(resume) || !isRecord(resume.request)) return null;
  const parsedBinding = parseStageOuterBinding(binding);
  if (!parsedBinding.ok
    || typeof resume.inputDigest !== 'string'
    || !/^sha256:[0-9a-f]{64}$/i.test(resume.inputDigest)
    || typeof resume.request.sessionId !== 'string'
    || !OPAQUE_ID_PATTERN.test(resume.request.sessionId)
    || typeof resume.request.requestId !== 'string'
    || !OPAQUE_ID_PATTERN.test(resume.request.requestId)) return null;
  return {
    schema: 'warlord.as2-resume-apply.v1',
    status,
    inputDigest: resume.inputDigest,
    sessionId: resume.request.sessionId,
    requestId: resume.request.requestId,
    stageOuterBinding: parsedBinding.value,
  };
}

export function canEmitStageGameOver(
  authorityBlocked: boolean,
  phase: string,
  hasResult: boolean,
): boolean {
  return !authorityBlocked && phase === 'GAME_OVER' && hasResult;
}
