'use strict';
const fs = require('node:fs');
const path = require('node:path');

// Keep the old descriptor across rotation, so unread receipts cannot disappear
// when launcher.log becomes launcher.log.1. Carry incomplete UTF-8 lines verbatim.
class LogTracker {
  constructor(paths, journal = null) {
    this.files = paths.map(file => ({ path: file, fd: null, offset: 0, carry: Buffer.alloc(0) }));
    this.journal = journal;
    this.lastScene = 0;
    this.taskSyncSeen = false;
    for (const file of this.files) this.open(file, true);
  }
  open(file, watermark = false) {
    if (!fs.existsSync(file.path)) return;
    file.fd = fs.openSync(file.path, 'r');
    const stat = fs.fstatSync(file.fd);
    file.identity = stat.dev + ':' + stat.ino + ':' + stat.birthtimeMs;
    file.offset = watermark ? stat.size : 0;
    file.carry = Buffer.alloc(0);
  }
  read(file, records) {
    const stat = fs.fstatSync(file.fd);
    if (stat.size < file.offset) { file.offset = 0; file.carry = Buffer.alloc(0); }
    if (stat.size === file.offset) return;
    const start = file.offset - file.carry.length;
    const fresh = Buffer.alloc(stat.size - file.offset);
    const read = fs.readSync(file.fd, fresh, 0, fresh.length, file.offset);
    file.offset += read;
    const bytes = Buffer.concat([file.carry, fresh.subarray(0, read)]);
    let begin = 0, end;
    while ((end = bytes.indexOf(10, begin)) >= 0) {
      const line = bytes.subarray(begin, end).toString('utf8').replace(/\r$/, '');
      if (line.trim()) records.push({ path: file.path, identity: file.identity, offset: start + begin, line });
      begin = end + 1;
    }
    file.carry = bytes.subarray(begin);
  }
  poll() {
    const records = [];
    for (const file of this.files) {
      if (file.fd === null) this.open(file);
      if (file.fd === null) continue;
      this.read(file, records);
      if (fs.existsSync(file.path)) {
        const stat = fs.statSync(file.path);
        if (file.identity !== stat.dev + ':' + stat.ino + ':' + stat.birthtimeMs) {
          this.read(file, records);
          fs.closeSync(file.fd); file.fd = null;
          this.open(file); this.read(file, records);
        }
      }
    }
    for (const record of records) {
      if (record.line.includes('task_sync')) this.taskSyncSeen = true;
      const match = /event=world_lighting_state .*?scene=(\d+) ready=true/.exec(record.line);
      if (match) this.lastScene = Math.max(this.lastScene, Number(match[1]));
    }
    if (this.journal) {
      const critical = records.filter(r => /scene_transition|SceneEntry|world_compositor_failed|flash_exited/.test(r.line));
      if (critical.length) fs.appendFileSync(this.journal, critical.map(r => JSON.stringify(r)).join('\n') + '\n');
    }
    return { records, newLines: records.map(r => r.line) };
  }
  checkpoint() { this.poll(); return this.lastScene; }
  close() { for (const file of this.files) { if (file.fd !== null) fs.closeSync(file.fd); file.fd = null; } }
  static discover(root) {
    return [path.join(root, 'logs/bootstrap.log'), path.join(root, 'logs/launcher.log'),
      path.join(process.env.APPDATA || '', 'Macromedia/Flash Player/Logs/flashlog.txt')];
  }
}
module.exports = { LogTracker };
