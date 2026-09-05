function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function canonicalValueJson(value: unknown): string | undefined {
  if (Array.isArray(value)) {
    const items: string[] = [];
    for (let index = 0; index < value.length; index += 1) {
      items.push(canonicalValueJson(value[index]) ?? 'null');
    }
    return `[${items.join(',')}]`;
  }
  if (isRecord(value)) {
    const properties: string[] = [];
    for (const key of Object.keys(value).sort()) {
      const encoded = canonicalValueJson(value[key]);
      if (encoded !== undefined) properties.push(`${JSON.stringify(key)}:${encoded}`);
    }
    return `{${properties.join(',')}}`;
  }
  return JSON.stringify(value);
}

export function canonicalJson(value: unknown): string {
  // A normal JavaScript object cannot retain ordinal order for integer-shaped
  // property names: JSON.stringify reorders keys such as "12" and "111"
  // numerically. Serialize the already-sorted entries directly so Web and Host
  // hash the same frozen request.
  const json = canonicalValueJson(value);
  if (json === undefined) throw new Error('权威请求包含不可序列化值。');
  return json;
}

export async function sha256Canonical(value: unknown): Promise<string> {
  if (!globalThis.crypto?.subtle) throw new Error('当前 WebView 不支持 SHA-256 权威请求摘要。');
  const digest = await globalThis.crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(canonicalJson(value)),
  );
  return `sha256:${[...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, '0')).join('')}`;
}
