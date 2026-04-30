// INV-1：修复后必须 bump lastSaved 让 SolResolver 选 shadow（清洁版）。
// 格式与 SaveManager.as packTimestamp() 一致：'yyyy-MM-dd HH:mm:ss'（本地时区表示，
// 但比较是字典序逐字符；只要新值的字典序 > 老值即可触发 SolResolver 选 shadow 分支）。

export function packTimestamp(date: Date = new Date()): string {
  const yyyy = date.getFullYear();
  const mm = String(date.getMonth() + 1).padStart(2, '0');
  const dd = String(date.getDate()).padStart(2, '0');
  const hh = String(date.getHours()).padStart(2, '0');
  const mi = String(date.getMinutes()).padStart(2, '0');
  const ss = String(date.getSeconds()).padStart(2, '0');
  return `${yyyy}-${mm}-${dd} ${hh}:${mi}:${ss}`;
}

/** 把 snapshot 上的 lastSaved bump 到 now（如果没有该字段则新增）。返回新值。 */
export function bumpLastSaved(snapshot: any, now: Date = new Date()): string {
  const ts = packTimestamp(now);
  snapshot.lastSaved = ts;
  return ts;
}
