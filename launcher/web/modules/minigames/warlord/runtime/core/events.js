export function addGameEvent(state, event) {
    state.nextEventOrdinal += 1;
    const full = {
        ...event,
        eventId: `g${state.nextEventOrdinal}`,
        strategicRound: state.strategicRound,
        commandSequence: state.commandSequence,
    };
    state.eventLog.push(full);
    return full;
}
//# sourceMappingURL=events.js.map