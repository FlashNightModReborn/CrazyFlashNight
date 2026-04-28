// Phase 2a: 存档 schema 白名单 (v3.0)
// 每条定义一个可在"简易模式"编辑的字段路径。
// path 使用数组表示 JSON 层级（字符串 key + 数字 index 混合）。
// 未命中白名单的字段由树视图 fallback 覆盖。
//
// === Phase 5.8 扩展（2026-04-28）===
// 新增 category 分组（character / system / progress / training / danger）
// 新增 danger 标记（双击解锁，避免误改影响存档兼容性的字段）
// 新增 setGlobalVolume / setBGMVolume / setSfxVolume —— 迁移期音频设置 UI 的临时入口
// 新增 default 字段 —— 用于 diff 视图与"恢复默认"按钮（缺失则不可恢复）
// 新增 hint —— 字段下方说明，hintWarn=true 时高亮黄色

(function() {
  'use strict';

  // 类别枚举与排序权重；越小越靠前
  // 简易模式按此顺序渲染卡片
  var CATEGORIES = {
    character: { label: '角色', order: 1 },
    progress:  { label: '进度', order: 2 },
    training:  { label: '健身',  order: 3 },
    system:    { label: '系统',  order: 4 },
    danger:    { label: '危险',  order: 5 },
    other:     { label: '其它',  order: 99 }
  };

  var ARCHIVE_SCHEMA_V3_0 = [
    // ========== danger ==========
    { path: ['version'],     label: '存档版本', type: 'literal', value: '3.0',
      category: 'danger', danger: true,
      hint: '改动会让档无法被启动器识别，仅在调试时改。' },

    // ========== character ==========
    { path: ['lastSaved'],   label: '最后保存', type: 'string',  readonly: true,
      category: 'character' },
    { path: ['0', 0],        label: '角色名',   type: 'string',  maxLength: 16,
      category: 'character' },
    { path: ['0', 1],        label: '性别',     type: 'enum',    options: ['男', '女'],
      category: 'character' },
    { path: ['0', 2],        label: '金钱',     type: 'number',  min: 0, max: 99999999, default: 0,
      category: 'character' },
    { path: ['0', 3],        label: '等级',     type: 'number',  min: 1, max: 999, default: 1,
      category: 'character' },
    { path: ['0', 4],        label: '经验',     type: 'number',  min: 0, default: 0,
      category: 'character' },
    { path: ['0', 5],        label: '身高',     type: 'number',  min: 100, max: 300, default: 175,
      category: 'character' },
    { path: ['0', 6],        label: '技能点',   type: 'number',  min: 0, max: 999999, default: 0,
      category: 'character' },
    { path: ['0', 8],        label: '身价',     type: 'number',  min: 0, default: 0,
      category: 'character' },
    { path: ['0', 9],        label: '虚拟币',   type: 'number',  min: 0, default: 0,
      category: 'character' },

    // ========== progress ==========
    { path: ['3'],           label: '主线进度', type: 'number',  min: 0, default: 0,
      category: 'progress' },

    // ========== training ==========
    { path: ['7', 0],        label: '健身 HP',  type: 'number',  min: 0, default: 0,
      category: 'training' },
    { path: ['7', 1],        label: '健身 MP',  type: 'number',  min: 0, default: 0,
      category: 'training' },
    { path: ['7', 2],        label: '健身空攻', type: 'number',  min: 0, default: 0,
      category: 'training' },
    { path: ['7', 3],        label: '健身防御', type: 'number',  min: 0, default: 0,
      category: 'training' },
    { path: ['7', 4],        label: '健身内力', type: 'number',  min: 0, default: 0,
      category: 'training' },

    // ========== system（迁移期临时入口）==========
    // 实际存档路径：others.设置.setGlobalVolume / others.设置.setBGMVolume
    // 来源：SaveManager.packSettings / applySettings（scripts/类定义/.../SaveManager.as 1323-1348）
    // 写入 launcher 经 setGlobalVolume → socket master_vol → ma_bridge_set_master_volume；
    // setBGMVolume → socket bgm_vol → ma_bridge_bgm_set_volume。值域 0-100，launcher 端 /100 归一。
    // 默认值与 SoundEffectManager.as:49-50 一致：50 / 80。
    // 注：Flash 侧不存独立的 sfxVolume 字段（音效共享 globalVolume），所以这里也不暴露。
    { path: ['others', '设置', 'setGlobalVolume'], label: '主音量', type: 'number',
      min: 0, max: 100, default: 50, category: 'system',
      preview: 'audio.master',
      hint: '0 会让所有音效静默（包括 SFX 和 BGM）。',
      hintWarn: true },
    { path: ['others', '设置', 'setBGMVolume'],    label: 'BGM 音量', type: 'number',
      min: 0, max: 100, default: 80, category: 'system',
      preview: 'audio.bgm' }
  ];

  // 用于加载时对比版本
  var SCHEMA_VERSION = '3.0';

  // 按 path 取值
  function getByPath(obj, path) {
    var cur = obj;
    for (var i = 0; i < path.length; i++) {
      if (cur == null) return undefined;
      cur = cur[path[i]];
    }
    return cur;
  }

  // 按 path 设值
  function setByPath(obj, path, value) {
    var cur = obj;
    for (var i = 0; i < path.length - 1; i++) {
      if (cur[path[i]] == null) {
        cur[path[i]] = (typeof path[i + 1] === 'number') ? [] : {};
      }
      cur = cur[path[i]];
    }
    cur[path[path.length - 1]] = value;
  }

  // 路径转显示字符串
  function pathToString(path) {
    var s = '';
    for (var i = 0; i < path.length; i++) {
      if (typeof path[i] === 'number') s += '[' + path[i] + ']';
      else if (i === 0) s += path[i];
      else s += '.' + path[i];
    }
    return s;
  }

  // 收集白名单覆盖的 path 字符串集合（用于树视图排除）
  function getWhitelistPathSet() {
    var set = {};
    for (var i = 0; i < ARCHIVE_SCHEMA_V3_0.length; i++) {
      set[pathToString(ARCHIVE_SCHEMA_V3_0[i].path)] = true;
    }
    return set;
  }

  // 按 category 分组返回 {category: [field...]}，且每个 category 的 fields 按 schema 原始顺序
  // 没有 category 标记的字段归到 'other'
  function groupByCategory() {
    var groups = {};
    for (var i = 0; i < ARCHIVE_SCHEMA_V3_0.length; i++) {
      var f = ARCHIVE_SCHEMA_V3_0[i];
      var cat = f.category || 'other';
      if (!groups[cat]) groups[cat] = [];
      groups[cat].push(f);
    }
    return groups;
  }

  // 返回排好序的 category key 列表
  function orderedCategoryKeys() {
    var keys = Object.keys(CATEGORIES);
    keys.sort(function(a, b) {
      return (CATEGORIES[a].order || 99) - (CATEGORIES[b].order || 99);
    });
    return keys;
  }

  // 暴露
  window.ArchiveSchema = {
    SCHEMA_VERSION: SCHEMA_VERSION,
    fields: ARCHIVE_SCHEMA_V3_0,
    categories: CATEGORIES,
    getByPath: getByPath,
    setByPath: setByPath,
    pathToString: pathToString,
    getWhitelistPathSet: getWhitelistPathSet,
    groupByCategory: groupByCategory,
    orderedCategoryKeys: orderedCategoryKeys
  };
})();
