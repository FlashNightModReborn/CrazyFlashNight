/**
 * Browser stub for `node:path` inside the CEP panel bundle.
 *
 * core's `anEnv` (which `import path from 'node:path'`) gets pulled into the
 * bundle by core's `export * as anEnv` barrel (which defeats rollup
 * tree-shaking). The panel NEVER calls anEnv, so this stub is never actually
 * executed — it exists only so the bare `node:path` specifier resolves instead
 * of throwing "Failed to resolve module specifier" in the CEF webview (which
 * would blank the panel). Aliased in vite.config.ts.
 */
const join = (...parts: string[]): string => parts.filter(Boolean).join('/');
const dirname = (p: string): string => p.replace(/[\\/][^\\/]*$/, '');
const basename = (p: string): string => p.replace(/^.*[\\/]/, '');
const stub = { join, dirname, basename, resolve: join, sep: '/' };
export { join, dirname, basename };
export default stub;
