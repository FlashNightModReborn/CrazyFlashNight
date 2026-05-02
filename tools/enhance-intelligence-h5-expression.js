#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const h5Dir = path.join(root, 'data', 'intelligence_h5');

function text(value) { return { type: 'text', text: String(value) }; }
function strong(value) { return { type: 'strong', content: [text(value)] }; }
function token(name, value) { return { type: 'colorToken', token: name, content: [text(value)] }; }
function decrypt(level, encryptedText, value) {
  return { type: 'decryptText', level, encryptedText, content: [text(value)] };
}
function p(content) { return { type: 'paragraph', content: flatInline(content) }; }
function note(content) { return { type: 'note', content: flatInline(content) }; }
function heading(level, content) { return { type: 'heading', level, content: flatInline(content) }; }
function stamp(tone, value) { return { type: 'stamp', tone, content: [text(value)] }; }
function surface(variant, x, y, w, h, rotate, opacity) {
  return { type: 'surfaceMark', variant, x, y, w, h, rotate, opacity };
}
function annotation(content, sideNote) {
  return { type: 'annotation', content: flatInline(content), note: flatInline(sideNote) };
}
function terminal(title, entries) { return { type: 'terminalLog', title, entries }; }
function row(kind, content) { return { kind, content: flatInline(content) }; }
function timeline(entries) { return { type: 'timeline', entries }; }
function table(columns, rows) { return { type: 'table', columns, rows }; }
function hardware(label, status, steps, reveal) {
  return { type: 'hardwareExtract', label, status, steps, reveal };
}
function decryptBlock(label, level, plain, encrypted) {
  return { type: 'decryptBlock', label, level, plain, encrypted };
}

function flatInline(items) {
  const out = [];
  (Array.isArray(items) ? items : [items]).forEach((item) => {
    if (item == null) return;
    if (Array.isArray(item)) out.push(...flatInline(item));
    else if (typeof item === 'string') out.push(text(item));
    else out.push(item);
  });
  return out;
}

function load(name) {
  return JSON.parse(fs.readFileSync(path.join(h5Dir, `${name}.json`), 'utf8'));
}

function save(name, doc) {
  fs.writeFileSync(path.join(h5Dir, `${name}.json`), JSON.stringify(doc, null, 2) + '\n', 'utf8');
}

function page(doc, key) {
  const found = doc.pages.find((item) => item.pageKey === key);
  if (!found) throw new Error(`${doc.itemName}: page ${key} not found`);
  return found;
}

function replacePage(doc, key, blocks) {
  page(doc, key).blocks = blocks;
}

function enhanceData() {
  const doc = load('资料');
  replacePage(doc, '40', [
    surface('fold', 8, 0, 8, 100, -2, 0.20),
    surface('dirt', 64, 13, 18, 14, -8, 0.16),
    heading(2, [strong('重组组织研判摘录')]),
    annotation(
      [
        '根据近期资料推算，“',
        decrypt(1, 'NOAH-██', '诺亚方舟计划组'),
        '”已重组为一个新组织，具体情况有待调查。'
      ],
      [
        '交叉比对：旧世研究组编号、地铁站异常样本、钻头技术回收记录均指向同一后继实体。'
      ]
    ),
    p([
      '该组织可能对废城进行了渗透，可能对于钻头技术进行了回收。但仍不能确认废城是否有该组织发送的钻头。'
    ]),
    p([
      '可确认地铁站近期骚动与该组织有关；资料显示地铁站出现大体型、身穿特殊服装的丧尸，其来源极可能就是“',
      decrypt(1, 'NOAH-██', '诺亚方舟计划组'),
      '”转型后的组织。'
    ])
  ]);
  save('资料', doc);
}

function enhanceEcho() {
  const doc = load('ECHO-034的加密日志');
  page(doc, '1_1').blocks.unshift(
    surface('dirt', 4, 72, 24, 18, 12, 0.20),
    annotation(
      ['恢复会话：废弃天网节点#7749 / 植入芯片紧急上传'],
      ['记录不是日记原件，而是从异常上传包中拼接出的可读层。缺块位置保留为局部密文。']
    )
  );
  page(doc, '1_9').blocks.push(
    decryptBlock(
      '备用权限解封记录',
      4,
      [
        terminal('ROOT://ECHO-034/FAILSAFE', [
          row('system', ['AUTH_FALLBACK accepted']),
          row('system', ['thermals: ', token('danger', 'critical'), ' / self-delete: 300s']),
          row('text', ['最后可读输入：', decrypt(4, '███', '我还是我'), '。至少现在还是。'])
        ])
      ],
      [
        terminal('ROOT://ECHO-034/FAILSAFE', [
          row('system', ['AUTH_FALLBACK ███████']),
          row('system', ['thermals: ███████ / self-delete: ███s'])
        ])
      ]
    )
  );
  page(doc, '1_10').blocks.unshift(
    annotation(
      ['自诊断日志连续输出 SUCCESS，但正文语气已经从“我”转向系统观察。'],
      ['该页保留原始终端文本，不额外改写叙述，只标记身份漂移。']
    )
  );
  page(doc, '1_12').blocks.push(
    decryptBlock('D+5 生理状态片段', 4, [
      p(['缓存中可恢复到多个短句，但语义重复指向“身体边界正在失效”。']),
      p(['解码关键词：', decrypt(4, '███', '骨刺'), ' / ', decrypt(4, '███', '灰皮肤症')])
    ], [
      p(['physiology fragment: ███ / ███ / boundary lost'])
    ])
  );
  page(doc, '1_13').blocks.unshift(surface('dirt', 72, 68, 20, 14, -18, 0.20));
  page(doc, '1_14').blocks.unshift(surface('blood-hand', 78, 16, 13, 16, -11, 0.28));
  page(doc, '1_14').blocks.push(
    hardware('植入芯片自毁栈', '逆向完成', ['定位上传栈', '跳过INACTIVE清理', '复制最后三段缓存'], [
      terminal('chip.dump.last_words', [
        row('system', ['checksum repaired: 91%']),
        row('text', ['肉体控制权持续下降；自杀动作被判定为“主动选择”，未触发外部接管。']),
        row('system', ['residual signal: ', decrypt(4, '██-███', 'ECHO-034')])
      ])
    ])
  );
  page(doc, '1_16').blocks.push(
    timeline([
      { label: 'D-14', content: [text('工牌仍正常，症状以震颤和记忆错位为主。')] },
      { label: 'D-4', content: [text('INACTIVE 标签出现，个体身份开始被系统重写。')] },
      { label: 'D日', content: [text('备用权限接管，上传伪装为错误报告。')] },
      { label: 'D+9', content: [text('节点周边出现“灰皮肤症”连锁报告。')] }
    ])
  );
  page(doc, '1_16').blocks.push(
    decryptBlock('INACTIVE 保护失败明细', 3, [
      table(['字段', '状态'], [
        ['出厂销毁标记', '未执行'],
        ['标签错误', '034-B 被错误写入错误报告队列'],
        ['自动删除触发', '3 次'],
        ['上传伪装', '系统错误报告']
      ])
    ], [
      p(['INACTIVE guard: █████ / upload: error_report'])
    ])
  );
  page(doc, '1_17').blocks.push(
    decryptBlock('E5 完整链路还原', 5, [
      table(['字段', '恢复值'], [
        ['样本', 'γ-ECHO / 034-B'],
        ['触发源', '医院地下三层-B区终端'],
        ['扩散迹象', '500米内72小时87起灰皮肤症'],
        ['处理记录', '焚烧处理，样本移交病理组']
      ]),
      note(['结论：这不是单一感染日志，而是一次失败产品在审判日混乱中的逃逸记录。'])
    ], [
      p(['██████ / ███-ECHO / █████████████████'])
    ])
  );
  save('ECHO-034的加密日志', doc);
}

function enhanceWaterPlant() {
  const doc = load('水厂外勤档案');
  page(doc, '1_1').blocks.splice(2, 0,
    annotation(
      ['关键阀门：', decrypt(3, 'V-██C', 'V-15C'), '。所有后续异常均围绕该联通阀回流。'],
      ['水渍遮挡处仍能辨认“下水道联通”字样，疑似有人反复翻看这一页。']
    )
  );
  page(doc, '1_3').blocks.unshift(
    stamp('danger', '驳回'),
    annotation(
      ['上级批示直接覆盖巡检风险，投放工单继续执行。'],
      ['“外部合作方已知悉”是该页最关键字段，说明水厂不是单独行动。']
    )
  );
  page(doc, '1_4').blocks.push(
    table(['投放区', '目标', '疑点'], [
      ['A区', '东城主管网', '居民区样本扩散'],
      ['B区', '备用供水线', '与仓库B区交接有关'],
      ['C区', '工业区', '后续指标异常最明显']
    ])
  );
  page(doc, '1_9').blocks.unshift(surface('water', 58, 2, 26, 16, 5, 0.28));
  page(doc, '1_9').blocks.push(
    timeline([
      { label: '12-18', content: [text('普通雇员健康监测开始出现连续异常。')] },
      { label: '复检', content: [text('血清黏稠度异常，记忆断片频率升高。')] },
      { label: '归档', content: [text('C级人员与B组替换体被要求分开归档。')] }
    ])
  );
  page(doc, '1_15').blocks.unshift(surface('tear', 76, 4, 14, 22, 9, 0.30));
  page(doc, '1_15').blocks.push(
    hardware('移交箱封条扫描', '封条残留可读', ['紫外照射', '封蜡边缘取样', '读取接收方压痕'], [
      table(['位置', '读取结果'], [
        ['封条左上', 'WP-东区自来水厂'],
        ['接收方压痕', '[内部通讯#1220-C]'],
        ['罐体标记', 'γ-ECHO / θ-HIVE / Σ-ITE'],
        ['异常', '频率调节器单独二次封装']
      ])
    ])
  );
  page(doc, '1_16').blocks.push(
    decryptBlock('接收方设施代号还原', 5, [
      p(['接收方并非普通仓储单位，而是地下设施接管链路。']),
      p(['可读片段：', decrypt(5, '█████', '地铁通风系统'), ' / 高浓度扩散。'])
    ], [
      p(['receiver facility: █████ / ventilation █████'])
    ])
  );
  page(doc, '1_18').blocks.unshift(surface('water', 18, 12, 34, 20, -4, 0.34));
  page(doc, '1_18').blocks.push(
    decryptBlock('末页水渍下的手写补录', 5, [
      p(['“SEC-006第二天就调走了。”']),
      p(['“调走不是调岗，是从名单里消失。”']),
      p(['“V-15C千万别打开。那些东西会顺着管道爬上来。”'])
    ], [
      p(['[水渍覆盖] SEC-006 █████████ V-15C █████████'])
    ])
  );
  save('水厂外勤档案', doc);
}

function enhanceBlackIron() {
  const doc = load('黑铁会的秘密情报书');
  page(doc, '1').blocks.unshift(surface('tear', 2, 2, 12, 26, -5, 0.28));
  page(doc, '1').blocks.push(
    annotation(
      ['“虚渊诡道”处墨色较新，疑似由传令人后补。'],
      ['烘烤纸背后可见另一层笔画，和“诺亚余孽”四字重叠。']
    )
  );
  page(doc, '2').blocks.unshift(
    stamp('danger', '急传'),
    table(['稽查项', '处置', '风险'], [
      ['降头师心网符线', '先断线后收押', '受染者可能伪装清醒'],
      ['白纸扇之器', '封缄编号，交翅虎堂', '墨匣风信可能自毁'],
      ['陌生符物', '先控人后取物', '暗线引路']
    ])
  );
  page(doc, '3').blocks.unshift(surface('blood-hand', 72, 20, 15, 17, 8, 0.24));
  page(doc, '3').blocks.push(
    decryptBlock('焦黑背面残字', 3, [
      p(['“若有坛主问教主伤势，只答：', token('danger', '神识澄明'), '。”']),
      p(['“问第二遍者，记名。”']),
      p(['“问第三遍者，不必回坛。”'])
    ], [
      p(['焦痕覆盖：问██遍者 █████'])
    ])
  );
  save('黑铁会的秘密情报书', doc);
}

enhanceData();
enhanceEcho();
enhanceWaterPlant();
enhanceBlackIron();
console.log('[intelligence-h5-expression] enhanced 4 intelligence files; 幻层残响 intentionally left at generated baseline');
