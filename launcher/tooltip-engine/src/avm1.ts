namespace TooltipEngine {
    /** Narrow coercions used by migrated content rules, from agentsDoc/as2-anti-hallucination.md.
     * They are not a Flash runtime or an equipment-calculation implementation. */
    export function as2Number(value: any): number {
        if (value == null) return NaN;
        if (typeof value === 'string' && value.trim().length === 0) return NaN;
        if (typeof value === 'object') {
            const primitive = String(value);
            return primitive.trim().length === 0 ? NaN : Number(primitive);
        }
        return Number(value);
    }
    export function as2IsNaN(value: any): boolean { return Number.isNaN(as2Number(value)); }
    export function as2IsFinite(value: any): boolean { return Number.isFinite(as2Number(value)); }
    /** AVM1 array-to-text keeps explicit null and missing entries as words. */
    export function as2String(value: any): string {
        if (!Array.isArray(value)) return String(value);
        const parts: string[] = [];
        for (let i = 0; i < value.length; i++) parts.push(as2String(value[i]));
        return parts.join(',');
    }
    export function as2Less(left: any, right: any): boolean {
        return typeof left === 'string' && typeof right === 'string'
            ? left < right : as2Number(left) < as2Number(right);
    }
    export function as2Greater(left: any, right: any): boolean { return as2Less(right, left); }
    export function as2LessEqual(left: any, right: any): boolean { return !as2Greater(left, right); }
    export function as2GreaterEqual(left: any, right: any): boolean { return !as2Less(left, right); }
    export function as2Equal(left: any, right: any): boolean {
        if (left == null || right == null) return left == null && right == null;
        if (typeof left === 'number' && typeof right === 'number') {
            // AVM1's observed reflexive NaN equality. Distinct boxed/register NaN provenance
            // is not representable on JSON and remains an explicit fresh-oracle gap.
            return left === right || (Number.isNaN(left) && Number.isNaN(right));
        }
        if (typeof left === typeof right) return left === right;
        if (typeof left === 'object' || typeof right === 'object') return left == right;
        const a = as2Number(left), b = as2Number(right);
        return !Number.isNaN(a) && !Number.isNaN(b) && a === b;
    }
    export function as2NotEqual(left: any, right: any): boolean { return !as2Equal(left, right); }
    /** Projection clone + LiteJSON serialize reverses twice, preserving original insertion.
     * Native data objects are JSON-only; prototype properties are excluded at the boundary. */
    export function as2Keys(value: any): string[] {
        return value == null ? [] : Object.keys(value).reverse();
    }
    export function as2FromCharCode(...values: number[]): string {
        return String.fromCharCode(...values).replace(/\u0000/g, '');
    }
}
