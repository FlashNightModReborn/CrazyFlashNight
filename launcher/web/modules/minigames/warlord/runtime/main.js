import { WarlordSession, } from './app/warlord-session.js';
export const WARLORD_RUNTIME_VERSION = 'warlord-sandtable-phase-c.as2';
export function mount(root, initData) {
    if (!(root instanceof HTMLElement))
        throw new Error('warlord mount requires an HTMLElement root');
    return new WarlordSession(root, initData);
}
//# sourceMappingURL=main.js.map