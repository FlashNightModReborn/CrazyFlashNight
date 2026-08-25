function project(result, mode) {
    return {
        mode,
        winner: result.winner,
        reason: result.reason,
        pieceResults: structuredClone(result.pieceResults),
        finalRngState: result.finalRngState,
    };
}
export function completePlayback(result) {
    // UI consumes the immutable resolver log; it never mutates campaign state.
    for (const _event of result.eventLog) {
        // Intentionally no rule execution here.
    }
    return project(result, 'watched');
}
export function skipPlayback(result) {
    return project(result, 'skipped');
}
//# sourceMappingURL=playback.js.map