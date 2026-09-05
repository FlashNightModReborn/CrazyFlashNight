import { parseStageOuterBinding, } from './outer-authority.js';
const OPAQUE_ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._~-]{0,159}$/;
function isRecord(value) {
    return value !== null && typeof value === 'object' && !Array.isArray(value);
}
export function buildResumeAppliedReceipt(resume, binding, status) {
    if (!isRecord(resume) || !isRecord(resume.request))
        return null;
    const parsedBinding = parseStageOuterBinding(binding);
    if (!parsedBinding.ok
        || typeof resume.inputDigest !== 'string'
        || !/^sha256:[0-9a-f]{64}$/i.test(resume.inputDigest)
        || typeof resume.request.sessionId !== 'string'
        || !OPAQUE_ID_PATTERN.test(resume.request.sessionId)
        || typeof resume.request.requestId !== 'string'
        || !OPAQUE_ID_PATTERN.test(resume.request.requestId))
        return null;
    return {
        schema: 'warlord.as2-resume-apply.v1',
        status,
        inputDigest: resume.inputDigest,
        sessionId: resume.request.sessionId,
        requestId: resume.request.requestId,
        stageOuterBinding: parsedBinding.value,
    };
}
export function canEmitStageGameOver(authorityBlocked, phase, hasResult) {
    return !authorityBlocked && phase === 'GAME_OVER' && hasResult;
}
//# sourceMappingURL=resume-apply.js.map