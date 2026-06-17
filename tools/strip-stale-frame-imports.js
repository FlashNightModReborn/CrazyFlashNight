// [已退役 / RETIRED 一次性脚本 · 2026-06-16] 使命已完成（两目标文件已剥净，幂等下重跑只会 SKIP）。
//   保留备查，**勿作常驻守门工具**，**勿扩 COVERED 白名单去剥别的 import**——通用 import 治理走
//   lint-frame-imports.js / stage-wrap-frame.js。退役说明见 docs/asLoader-README.md §1 文件地图。
//
// 一次性修正脚本（2026-06-16）：frame36 折叠中间态里两个子文件带「无分号 import」，
// stage-wrap/lint 旧正则只认带分号 import → 静默漏剥，import 泄进 staged 函数体（违反 C3 单一联合头不变量）。
// 这两个包 org.flashNight.naki.RandomNumberEngine.* 已在 scripts/asLoaderManifest/frame36.as 联合头(L30) 覆盖，
// 故此处剥除冗余 import，让实际源状态与 lint --fold-specific 的「子文件无残留 import」报告一致。
// 安全护栏：只剥 COVERED 白名单内（已确认被联合头覆盖）的包；其余 import 保留待人工核对。
// BOM 逐字节保留。幂等：已无可剥 import 则 SKIP。
var fs = require("fs");
var path = require("path");

var REPO = path.resolve(__dirname, "..");
var BOM = Buffer.from([0xEF, 0xBB, 0xBF]);
// 与 stage-wrap-frame.js 修正后的 IMPORT_RE 同源（分号可选、末尾仅吃水平空白、标识符分段式防贪婪吞 .*）
var IMPORT_RE = /^[ \t]*import\s+([A-Za-z_][\w$]*(?:\.[\w$]+)*(?:\.\*)?)[ \t]*;?[ \t]*\r?\n?/gm;

var TARGETS = [
  "scripts/逻辑/单位函数/单位函数_fs_aka_玩家模板迁移.as",
  "scripts/逻辑/单位函数/单位函数_lsy_敌人模板迁移.as"
];
// 已确认存在于 frame36.as 联合头的包（剥除后解析仍由联合头兜底）
var COVERED = { "org.flashNight.naki.RandomNumberEngine": true };

TARGETS.forEach(function (rel) {
  var abs = path.join(REPO, rel);
  var raw = fs.readFileSync(abs);
  var hasBom = raw.length >= 3 && raw[0] === 0xEF && raw[1] === 0xBB && raw[2] === 0xBF;
  var text = hasBom ? raw.slice(3).toString("utf8") : raw.toString("utf8");

  var stripped = [], kept = [];
  IMPORT_RE.lastIndex = 0;
  var out = text.replace(IMPORT_RE, function (whole, id) {
    var dot = id.lastIndexOf(".");
    var pkg = /\.\*$/.test(id) ? id.slice(0, -2) : (dot >= 0 ? id.slice(0, dot) : "");   // 默认包(无点)→ ""，不造垃圾包名
    if (pkg && COVERED[pkg]) { stripped.push(id); return ""; }
    kept.push(id);
    return whole;
  });

  if (stripped.length && out !== text) {
    var body = Buffer.from(out, "utf8");
    fs.writeFileSync(abs, hasBom ? Buffer.concat([BOM, body]) : body);
    console.log("[STRIP] " + rel + " ← " + stripped.join(", ") + (hasBom ? "  (BOM 保留)" : "  (⚠ 无 BOM)"));
  } else {
    console.log("[SKIP ] " + rel + " (无 COVERED import 可剥)");
  }
  if (kept.length) console.log("        ⚠ 保留未覆盖 import: " + kept.join(", "));
});
