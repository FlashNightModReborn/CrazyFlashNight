#!/usr/bin/env node
'use strict';
// 有限增量词法检查；不推断类型、可达性、调用图或领域提交是否成功。
const fs = require('fs');
const path = require('path');
const cp = require('child_process');
const crypto = require('crypto');
const ordinary = /^(?:updateProperties|requestPersistentRefresh|applyPersistentSnapshot|refreshPersistentWeaponCaches|projectStats|refreshStats)$/;

function maskLiterals(source) {
  return source.replace(/\/\*[\s\S]*?\*\/|\/\/[^\r\n]*|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'/g,
    value => value.replace(/[^\r\n]/g, ' '));
}
function functionRanges(mask) {
  const ranges = [];
  const re = /\bfunction\s*([\w\u0080-\uffff]*)\s*\([^)]*\)\s*(?::[\w.]+\s*)?\{/g;
  let match;
  while ((match = re.exec(mask))) {
    let depth = 1, end = re.lastIndex;
    for (; end < mask.length && depth; end++) {
      if (mask[end] === '{') depth++;
      else if (mask[end] === '}') depth--;
    }
    const assigned = mask.slice(Math.max(0, match.index - 160), match.index).match(/([\w.\u0080-\uffff]+)\s*=\s*$/);
    ranges.push({start:match.index, end, name:match[1] || (assigned && assigned[1].split('.').pop()) || '(callback)'});
  }
  return ranges;
}
function scriptSegments(source, file) {
  if (file.endsWith('.as')) return [{text:source, offset:0}];
  const segments = [], re = /<script(?:\s[^>]*)?>\s*<!\[CDATA\[([\s\S]*?)\]\]>\s*<\/script>/g;
  let match;
  while ((match = re.exec(source))) segments.push({text:match[1], offset:match.index + match[0].indexOf('<![CDATA[') + 9});
  return segments;
}
function ownerFor(file, owners) {
  return owners.find(row => row.paths.some(pattern => pattern.endsWith('/**')
    ? file.startsWith(pattern.slice(0, -2)) : file === pattern));
}
function scanText(source, file, owners = []) {
  const findings = [], owner = ownerFor(file, owners);
  for (const segment of scriptSegments(source, file)) {
    const masked = maskLiterals(segment.text), ranges = functionRanges(masked);
    const patterns = [
      ['managed_compound', /\b[\w\u0080-\uffff]+\.(?:(?:hp满血值|mp满血值|防御力|伤害加成|空手攻击力)|(?:长枪属性|手枪属性|手枪2属性|刀属性|手雷属性)\.power)\s*(?:\+=|-=|\*=|\/=)/g],
      ['manager_or_lifecycle', /\b(?:StaticInitializer\.initializeUnit|BuffManagerInitializer\.reset|new\s+(?:[\w.]+\.)?BuffManager|[\w\u0080-\uffff]+\.buffManager\.update)\s*\(/g],
      ['full_refresh', /_root\.刷新人物装扮\s*\(/g],
      ['persistent_input', /_root\.(?:全局健身[\w\u0080-\uffff]*|经脉[\w\u0080-\uffff]*|主角被动技能|佣兵是否出战信息|宠物信息|等级)(?:\s*\[[^\]\r\n]*\]){0,2}(?:\.[\w\u0080-\uffff]+)*\s*(?:=(?!=)|\+=|-=|\+\+|--)/g]
    ];
    for (const [kind, re] of patterns) {
      let match;
      while ((match = re.exec(masked))) {
        const containers = ranges.filter(row => row.start <= match.index && row.end > match.index);
        const inStats = containers.some(row => ordinary.test(row.name));
        const ui = /\/ui\/|\/UI\/|\/界面\//.test('/' + file);
        let rule = null;
        if (inStats && kind === 'managed_compound') rule = 'stats_live_final_compound';
        if (inStats && kind === 'manager_or_lifecycle') rule = 'stats_rebuild_or_tick';
        if (kind === 'full_refresh' && (ui || inStats)) rule = 'ui_or_stats_direct_full_refresh';
        const absolute = segment.offset + match.index;
        findings.push({file, line:source.slice(0, absolute).split('\n').length, kind,
          function:containers.length ? containers[containers.length - 1].name : '(frame)',
          rule, severity:rule ? 'error' : 'review_candidate',
          owner:owner ? owner.owner : 'unregistered',
          reason:owner ? owner.reason : '需定位实际 authority 和成功收口；词法命中不等于缺陷',
          excerpt:source.slice(absolute, absolute + 120).split(/\r?\n/)[0]});
      }
    }
  }
  return findings;
}
function git(root, args) { return cp.execFileSync('git', args, {cwd:root, encoding:'utf8', maxBuffer:64*1024*1024}); }
function changedLines(root, base, file) {
  const diff = git(root, ['diff', '--no-ext-diff', '--unified=0', base, '--', file]);
  const lines = new Set();
  for (const match of diff.matchAll(/^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/gm)) {
    const start = Number(match[1]), count = match[2] === undefined ? 1 : Number(match[2]);
    for (let n = 0; n < count; n++) lines.add(start + n);
  }
  return lines;
}
function main(args) {
  const root = path.resolve(__dirname, '../..');
  const option = flag => { const i=args.indexOf(flag); return i < 0 ? null : args[i+1]; };
  const baseline = args.includes('--baseline'), base = option('--base') || 'HEAD';
  const owners = JSON.parse(fs.readFileSync(path.join(__dirname, 'write-owners.json'), 'utf8')).owners;
  const tracked = git(root, ['ls-files', '-z']).split('\0').filter(Boolean);
  const untracked = git(root, ['ls-files', '--others', '--exclude-standard', '-z']).split('\0').filter(Boolean);
  const added = new Set(untracked);
  const candidates = baseline ? tracked.concat(untracked)
    : git(root, ['diff', '--name-only', '-z', base]).split('\0').filter(Boolean).concat(untracked);
  const files = [...new Set(candidates)].filter(file => /^(?:scripts\/.*\.as|flashswf\/.*\.xml)$/.test(file)
    && !/(?:Test\.as|TestLoader\.as|_collapsed_frame\.as)$/.test(file) && fs.existsSync(path.join(root,file)));
  const findings = [], sources = [];
  for (const file of files) {
    const bytes=fs.readFileSync(path.join(root,file)), source=bytes.toString('utf8');
    if(file.endsWith('.xml') && !source.includes('<script')) continue;
    sources.push({file, sha256:crypto.createHash('sha256').update(bytes).digest('hex')});
    const lines = baseline || added.has(file) ? null : changedLines(root, base, file);
    for(const finding of scanText(source,file,owners)) if(lines === null || lines.has(finding.line)) findings.push(finding);
  }
  const errors = findings.filter(row => row.severity === 'error');
  const report = {schema:'cf7.stat-write-review.v1',mode:baseline?'classification_baseline':'incremental',base,
    coverage:'AS2 classes/engine frames and XFL script CDATA; lexical candidates, no reachability/type proof',
    sources,findings,summary:{sourceFiles:sources.length,candidates:findings.length,knownForbidden:errors.length}};
  const output=option('--output'); if(output) fs.writeFileSync(path.resolve(output),JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify({...report.summary,mode:report.mode,output:output||null}));
  for(const row of errors.slice(0,20)) console.error(`${row.file}:${row.line} ${row.rule} (${row.function})`);
  if(!baseline && errors.length) process.exitCode=1;
  return report;
}
module.exports={scanText,maskLiterals,functionRanges,scriptSegments,main};
if(require.main === module) main(process.argv.slice(2));
