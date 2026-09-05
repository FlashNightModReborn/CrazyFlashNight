import { sha256Canonical } from '../core/canonical.js';
export function computeRulesDigest(definition) {
    return sha256Canonical(definition);
}
export function computePresentationDigest(presentation) {
    return sha256Canonical(presentation);
}
export async function computeMapContractDigests(definition, presentation) {
    const [rulesDigest, presentationDigest] = await Promise.all([
        computeRulesDigest(definition),
        computePresentationDigest(presentation),
    ]);
    return Object.freeze({ rulesDigest, presentationDigest });
}
//# sourceMappingURL=digest.js.map