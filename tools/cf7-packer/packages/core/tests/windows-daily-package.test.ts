import { afterAll, beforeAll, describe, expect, it } from "vitest";
import fs from "node:fs";
import path from "node:path";
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";

const tool = path.resolve(import.meta.dirname, "../../..");
const repo = path.resolve(tool, "../..");
const sha = (bytes: Buffer | string) => createHash("sha256").update(bytes).digest("hex").toUpperCase();
const q = (s: string) => "'" + s.replace(/'/g, "''") + "'";
let scratch: string;
let bootstrap: Buffer;
function write(root: string, name: string, content: string | Buffer) {
  const file = path.join(root, name);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, content);
  return file;
}
function ps(command: string, timeout = 60_000) {
  return spawnSync("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-EncodedCommand",
    Buffer.from("chcp.com 65001 > $null; $ErrorActionPreference='Stop'; " + command, "utf16le").toString("base64")],
  { encoding: "utf8", timeout, maxBuffer: 4 * 1024 * 1024 });
}
function text(result: ReturnType<typeof ps>) { return result.stdout + result.stderr + (result.error?.message ?? ""); }
function ok(result: ReturnType<typeof ps>) { expect(result.status, text(result)).toBe(0); }
function fixture() { return fs.mkdtempSync(path.join(scratch, "case-")); }

const required = [
  "CRAZYFLASHER7MercenaryEmpire.swf", "CRAZYFLASHER7MercenaryEmpire.bat", "Adobe Flash Player 20.exe",
  "config.toml", "config.xml", "crossdomain.xml", "hotkey_guard.exe", "scripts/asLoader.swf", "fscommand/launch_rag.bat",
  "launcher/web/bootstrap.html", "launcher/web/bootstrap-main.js", "launcher/web/overlay.html",
  "launcher/web/scene-transition.html", "launcher/web/composition-help.html", "launcher/web/composition-intelligence.html",
  "launcher/data/save_repair_dict.json", "launcher/data/save_schema.json", "launcher/data/guidance-catalog.json",
  "launcher/data/tutorial-journeys.json", "launcher/data/scene-transition/catalog.manifest.json",
  "launcher/data/world-lighting/preset.json", "launcher/data/world-lighting/render-schedule.json",
  "launcher/agent-assets/lore/public-companion.v1.json", "fonts/fonts.xml", "fonts/fonts.xsd", "sounds/bgm_list.xml",
  "flashswf/portraits/list.xml", "launcher/scripts/dist/test.js", "tools/dotnet-runtime/installer.exe",
  "tools/rapfi/pbrain-rapfi-windows-avx2.exe", "tools/rapfi/pbrain-rapfi-windows-sse.exe", "data/中文目录/中文数据.xml"
];
function runtime(root: string, extra = false) {
  write(root, "CRAZYFLASHER7MercenaryEmpire.exe", bootstrap);
  write(root, "runtime/CRAZYFLASHER7MercenaryEmpire.Core.dll", "fixture-core");
  write(root, "runtime/CRAZYFLASHER7MercenaryEmpire.Core.exe", "never-executed");
  if (extra) write(root, "runtime/old.dll", "retired-runtime");
  const names = ["CRAZYFLASHER7MercenaryEmpire.exe", "runtime/CRAZYFLASHER7MercenaryEmpire.Core.dll", "runtime/CRAZYFLASHER7MercenaryEmpire.Core.exe", ...(extra ? ["runtime/old.dll"] : [])].sort();
  const rows = names.map(name => {
    const bytes = fs.readFileSync(path.join(root, name));
    return `${name}\t${bytes.length}\t${sha(bytes)}`;
  });
  const identity = { artifactSourceHash: "A".repeat(64), producerRecipeHash: "B".repeat(64), toolchainLockHash: "C".repeat(64) };
  const metadata = { publishMode: "framework-dependent", ...identity, toolchainBaseline: "fixture",
    buildIdentityHash: sha(Object.entries(identity).map(([k, v]) => `${k}\t${v}\n`).join("")),
    payloadClosureHash: sha(rows.join("\n") + "\n") };
  const manifest = "cf7-runtime-manifest-v2\n" + Object.entries(metadata).map(([k, v]) => `${k}\t${v}\n`).join("") + rows.map(r => `file\t${r}\n`).join("");
  write(root, "runtime/cf7-runtime-manifest.tsv", manifest);
  write(root, "config/build/runtime-release-consensus.json", JSON.stringify({ schema: "cf7-runtime-release-consensus.v2", ...metadata, manifestSha256: sha(manifest) }));
}
function payload(root: string) {
  for (const name of required) write(root, name, name.endsWith(".json") ? "{}" : name.endsWith(".xml") ? "<root/>" : "fixture");
  runtime(root);
}
function copyOfficial(root: string) {
  for (const name of ["verify-runtime-bundle-v2.ps1", "runtime-build-common.ps1", "runtime-build-v2-common.ps1"]) {
    write(root, "tools/" + name, fs.readFileSync(path.join(repo, "tools", name)));
  }
}
function auditFixture() {
  const root = fixture();
  const source = path.join(root, "repo");
  const target = path.join(root, "payload");
  payload(source);
  fs.cpSync(source, target, { recursive: true });
  copyOfficial(source);
  return { root, source, target };
}
function audit(source: string, target: string) {
  return spawnSync(process.execPath, [path.join(tool, "scripts/audit-runtime-closure.mjs"), "--repo", source, "--payload", target],
    { encoding: "utf8", timeout: 60_000, maxBuffer: 4 * 1024 * 1024 });
}
function installFixture() {
  const root = fixture();
  const bundle = path.join(root, "bundle");
  const game = path.join(root, "sandbox-game");
  payload(path.join(bundle, "resources"));
  write(bundle, "install.ps1", fs.readFileSync(path.join(tool, "sfx/install.ps1")));
  write(bundle, "CFN-RAG-v3.0.1.exe", bootstrap);
  write(bundle, "CrazyFlasher7StandAloneStarter_Data/Managed/Assembly-CSharp.dll", "new-unity");
  write(game, "CrazyFlasher7StandAloneStarter.exe", "original-shell");
  runtime(path.join(game, "resources"), true);
  write(game, "resources/config.xml", "old-config");
  write(game, "CFN-RAG-v3.0.0.exe", "old-rag");
  write(game, "CrazyFlasher7StandAloneStarter_Data/Managed/Assembly-CSharp.dll", "old-unity");
  const protectedFiles = ["resources/data/rag/agent_saves/slot/agent_tasks.json", "resources/data/task/agent_tasks.json", "resources/saves/player.json", "resources/launcher_user_prefs.json", "resources/original/base.swf", "personal.txt"];
  for (const name of protectedFiles) write(game, name, "player:" + name);
  return { root, bundle, game, protectedFiles };
}
function install(f: ReturnType<typeof installFixture>) {
  return ps(`& ${q(path.join(f.bundle, "install.ps1"))} -GamePath ${q(f.game)} -NoPause -VerifyTimeoutSeconds 1`);
}
function checkPlayers(f: ReturnType<typeof installFixture>) {
  for (const name of f.protectedFiles) expect(fs.readFileSync(path.join(f.game, name), "utf8")).toBe("player:" + name);
}
function buildFixture() {
  const f = auditFixture();
  const fixtureTool = path.join(f.source, "tools/cf7-packer");
  for (const name of ["sfx/install.ps1", "sfx/build-windows-zip.ps1", "scripts/audit-runtime-closure.mjs"]) {
    write(fixtureTool, name, fs.readFileSync(path.join(tool, name)));
  }
  write(fixtureTool, "assets/CrazyFlasher7StandAloneStarter_Data/Managed/Assembly-CSharp.dll", "unity");
  // 只替代昂贵的 npm 上游采集；构建、官方校验、ZipFile、解压和安装均执行生产脚本。
  write(fixtureTool, "package.json", JSON.stringify({ scripts: { pack: "node fixture-pack.cjs" } }));
  write(fixtureTool, "fixture-pack.cjs", `const fs=require('fs'); const a=process.argv; if(!a.includes('--require-worktree')) process.exit(7); const out=a[a.indexOf('--output')+1]; fs.cpSync(${JSON.stringify(f.target)},out,{recursive:true}); fs.writeFileSync('pack-called',out);`);
  const rag = write(f.root, "CFN-RAG-v3.0.1.exe", bootstrap);
  const out = path.join(f.root, "zip-output");
  return { ...f, fixtureTool, rag, out };
}
function build(f: ReturnType<typeof buildFixture>, args = `-RagExe ${q(f.rag)}`) {
  return ps(`& ${q(path.join(f.fixtureTool, "sfx/build-windows-zip.ps1"))} -Version fixture -OutDir ${q(f.out)} ${args}`, 90_000);
}

describe.skipIf(process.platform !== "win32")("Windows 每日 ZIP 与局部升级（隔离 fixture，不运行游戏）", () => {
  beforeAll(() => {
    const base = "E:\\cf7-daily-tests";
    fs.mkdirSync(base, { recursive: true });
    scratch = fs.mkdtempSync(path.join(base, "case-"));
    const exe = path.join(scratch, "fixture-bootstrap.exe");
    const code = `using System; using System.IO; using System.Threading; public class Probe { public static int Main(string[] a) { if(a.Length!=1 || a[0]!="--verify-only") return 64; if(File.Exists("fixture-timeout")) Thread.Sleep(10000); if(File.Exists("fixture-fail")) return 23; Console.WriteLine("fixture verify-only executed"); return 0; } }`;
    ok(ps(`Add-Type -TypeDefinition ${q(code)} -OutputAssembly ${q(exe)} -OutputType ConsoleApplication`));
    bootstrap = fs.readFileSync(exe);
  }, 60_000);
  afterAll(() => { if (scratch) fs.rmSync(scratch, { recursive: true, force: true }); });

  it("官方 v2 校验通过；runtime、bootstrap、consensus 均与当前仓库一致", () => {
    const f = auditFixture();
    const result = audit(f.source, f.target);
    ok(result);
    expect(text(result)).toContain("RuntimeBundleV2] OK");
  });
  it.each(["runtime/CRAZYFLASHER7MercenaryEmpire.Core.dll", "CRAZYFLASHER7MercenaryEmpire.exe"])("拒绝同大小损坏 %s", name => {
    const f = auditFixture();
    const bytes = fs.readFileSync(path.join(f.target, name)); bytes[bytes.length - 1] ^= 1;
    write(f.target, name, bytes);
    const result = audit(f.source, f.target);
    expect(result.status).not.toBe(0);
    expect(text(result)).toContain("sha256");
  });
  it("拒绝大小错误与多余 runtime 文件", () => {
    const f = auditFixture();
    write(f.target, "runtime/CRAZYFLASHER7MercenaryEmpire.Core.dll", "short");
    write(f.target, "runtime/undeclared.dll", "bad");
    const result = audit(f.source, f.target);
    expect(result.status).not.toBe(0);
    expect(text(result)).toContain("size");
    expect(text(result)).toContain("undeclared deployment file");
  });
  it("即使包内清单自洽，也拒绝与当前仓库不同的旧 runtime", () => {
    const f = auditFixture(); runtime(f.target, true);
    const result = audit(f.source, f.target);
    expect(result.status).not.toBe(0);
    expect(text(result)).toContain("字节不同");
  });
  it("拒绝 consensus 与 manifest 脱钩", () => {
    const f = auditFixture();
    const name = "config/build/runtime-release-consensus.json";
    const record = JSON.parse(fs.readFileSync(path.join(f.target, name), "utf8")); record.manifestSha256 = "0".repeat(64);
    write(f.target, name, JSON.stringify(record));
    expect(text(audit(f.source, f.target))).toContain("manifestSha256 不符");
  });
  it("审计拒绝玩家状态与凭据", () => {
    const f = auditFixture(); write(f.target, "data/rag/player.json", "{}"); write(f.target, "config/.env", "fixture-only");
    const result = audit(f.source, f.target);
    expect(result.status).not.toBe(0); expect(text(result)).toContain("个人数据或凭据");
  });
  it("移除清单内旧 runtime/旧终端，保留玩家文件与原版底座", () => {
    const f = installFixture(); const result = install(f); ok(result);
    expect(text(result)).toContain("exit code=0");
    expect(fs.existsSync(path.join(f.game, "resources/runtime/old.dll"))).toBe(false);
    expect(fs.existsSync(path.join(f.game, "CFN-RAG-v3.0.0.exe"))).toBe(false);
    expect(fs.readFileSync(path.join(f.game, "CFN-RAG-v3.0.1.exe"))).toEqual(bootstrap);
    checkPlayers(f);
  });
  it.each(["fixture-fail", "fixture-timeout"])("bootstrap %s 时拒绝成功并恢复所有覆盖项", flag => {
    const f = installFixture(); write(f.game, "resources/" + flag, "fixture");
    const result = install(f); expect(result.status).not.toBe(0);
    expect(text(result)).not.toContain("[OK] 安装完成");
    expect(text(result)).toContain(flag === "fixture-fail" ? "exit code=23" : "超时");
    expect(fs.readFileSync(path.join(f.game, "resources/runtime/old.dll"), "utf8")).toBe("retired-runtime");
    expect(fs.readFileSync(path.join(f.game, "resources/config.xml"), "utf8")).toBe("old-config");
    expect(fs.readFileSync(path.join(f.game, "CrazyFlasher7StandAloneStarter_Data/Managed/Assembly-CSharp.dll"), "utf8")).toBe("old-unity");
    expect(fs.readFileSync(path.join(f.game, "CFN-RAG-v3.0.0.exe"), "utf8")).toBe("old-rag");
    expect(fs.existsSync(path.join(f.game, "CFN-RAG-v3.0.1.exe"))).toBe(false);
    checkPlayers(f);
    expect(text(install(f))).toContain("上轮安装备份");
  });
  it("未知 runtime 文件阻止升级且不删除玩家文件", () => {
    const f = installFixture(); write(f.game, "resources/runtime/personal.txt", "keep");
    const result = install(f); expect(result.status).not.toBe(0);
    expect(text(result)).toContain("未声明文件"); checkPlayers(f);
    expect(fs.readFileSync(path.join(f.game, "resources/runtime/personal.txt"), "utf8")).toBe("keep");
  });
  it("损坏安装源在任何覆盖发生前被拒绝", () => {
    const f = installFixture(); write(f.bundle, "resources/runtime/CRAZYFLASHER7MercenaryEmpire.Core.dll", "bad");
    expect(install(f).status).not.toBe(0); checkPlayers(f);
    expect(fs.readFileSync(path.join(f.game, "resources/config.xml"), "utf8")).toBe("old-config");
  });
  it("真正生成并解压小 ZIP：中文路径、RAG 字节、闭包与 BAT/PS1 编码通过", () => {
    const f = buildFixture(); ok(build(f));
    const zip = path.join(f.out, "CF7-每日包-fixture.zip");
    const extracted = path.join(f.root, "独立解压");
    ok(ps(`Add-Type -AssemblyName System.IO.Compression.FileSystem; [IO.Compression.ZipFile]::ExtractToDirectory(${q(zip)},${q(extracted)})`));
    expect(fs.existsSync(path.join(f.fixtureTool, "pack-called"))).toBe(true);
    expect(fs.readFileSync(path.join(extracted, "CFN-RAG-v3.0.1.exe"))).toEqual(bootstrap);
    expect(fs.readFileSync(path.join(extracted, "resources/data/中文目录/中文数据.xml"), "utf8")).toBe("<root/>");
    const listing = ps(`Add-Type -AssemblyName System.IO.Compression.FileSystem; $z=[IO.Compression.ZipFile]::OpenRead(${q(zip)}); try { $z.Entries | ForEach-Object { $_.FullName } } finally { $z.Dispose() }`);
    ok(listing);
    const entryNames = listing.stdout.split(/\r?\n/).map(line => line.trim()).filter(Boolean);
    expect(entryNames).toContain("resources/data/中文目录/中文数据.xml");
    expect(entryNames.filter(name => name.includes("\\"))).toEqual([]);
    const bat = fs.readFileSync(path.join(extracted, "安装更新.bat"));
    expect([...bat].every(b => b < 128)).toBe(true);
    expect(bat.toString().replace(/\r\n/g, "")).not.toMatch(/[\r\n]/);
    expect([...fs.readFileSync(path.join(extracted, "install.ps1")).subarray(0, 3)]).toEqual([239, 187, 191]);
  }, 120_000);
  it.each(["missing", "bad-name", "missing-audit", "missing-unity", "missing-official"])("ZIP 前置缺失 %s 必须失败，不调用 pack", kind => {
    const f = buildFixture();
    let args = `-RagExe ${q(f.rag)}`;
    if (kind === "missing") args = "";
    if (kind === "bad-name") { const bad = write(f.root, "terminal.exe", bootstrap); args = `-RagExe ${q(bad)}`; }
    if (kind === "missing-audit") fs.unlinkSync(path.join(f.fixtureTool, "scripts/audit-runtime-closure.mjs"));
    if (kind === "missing-unity") fs.unlinkSync(path.join(f.fixtureTool, "assets/CrazyFlasher7StandAloneStarter_Data/Managed/Assembly-CSharp.dll"));
    if (kind === "missing-official") fs.unlinkSync(path.join(f.source, "tools/verify-runtime-bundle-v2.ps1"));
    const result = build(f, args);
    expect(result.status, text(result)).not.toBe(0);
    expect(fs.existsSync(path.join(f.fixtureTool, "pack-called"))).toBe(false);
    expect(fs.existsSync(path.join(f.out, "CF7-每日包-fixture.zip"))).toBe(false);
  });
  it("不再接受 PackOutput 复用旧目录", () => {
    const f = buildFixture();
    expect(build(f, `-RagExe ${q(f.rag)} -PackOutput ${q(f.target)}`).status).not.toBe(0);
    expect(fs.existsSync(path.join(f.fixtureTool, "pack-called"))).toBe(false);
  });
});
