declare module 'node:fs' {
  export function mkdirSync(path: string, options?: { recursive?: boolean }): string | undefined;
  export function writeFileSync(path: string, data: string | Uint8Array, options?: { encoding?: string } | string): void;
  export function readFileSync(path: string, options?: { encoding?: string } | string): string | Uint8Array;
}

declare module 'node:vm' {
  export function runInNewContext(code: string, context: Record<string, unknown>): unknown;
}

declare module 'node:path' {
  export function resolve(...paths: string[]): string;
  export function join(...paths: string[]): string;
  export function dirname(path: string): string;
}

declare module 'node:test' {
  export interface TestContext {
    name: string;
  }
  export type TestFunction = (name: string, fn: (context: TestContext) => void | Promise<void>) => void;
  export const test: TestFunction;
  export const describe: TestFunction;
  export const it: TestFunction;
  const defaultTest: TestFunction;
  export default defaultTest;
}

declare module 'node:assert/strict' {
  interface AssertStrict {
    (value: unknown, message?: string | Error): asserts value;
    ok(value: unknown, message?: string | Error): asserts value;
    equal<T>(actual: T, expected: T, message?: string | Error): void;
    notEqual<T>(actual: T, expected: T, message?: string | Error): void;
    deepEqual(actual: unknown, expected: unknown, message?: string | Error): void;
    notDeepEqual(actual: unknown, expected: unknown, message?: string | Error): void;
    throws(fn: () => unknown, expected?: RegExp | ((error: unknown) => boolean)): void;
    doesNotThrow(fn: () => unknown): void;
    match(actual: string, expected: RegExp, message?: string | Error): void;
  }
  const assert: AssertStrict;
  export default assert;
}

declare const process: {
  cwd(): string;
  argv: string[];
  env: Record<string, string | undefined>;
  stdout: { write(text: string): void };
  stderr: { write(text: string): void };
  exitCode?: number;
};
