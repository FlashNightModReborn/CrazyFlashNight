// Phase 2a: 存档 schema 白名单 (v3.0)
// 每条定义一个可在"简易模式"编辑的字段路径。
// path 使用数组表示 JSON 层级（字符串 key + 数字 index 混合）。
// 未命中白名单的字段由树视图 fallback 覆盖。

(function() {
  'use strict';

  var ARCHIVE_SCHEMA_V3_0 = [
    { path: ['version'],     label: '存档版本', type: 'literal', value: '3.0', readonly: true },
    { path: ['lastSaved'],   label: '最后保存', type: 'string',  readonly: true },
    { path: ['0', 0],        label: '角色名',   type: 'string',  maxLength: 16 },
    { path: ['0', 1],        label: '性别',     type: 'enum',    options: ['男', '女'] },
    { path: ['0', 2],        label: '金钱',     type: 'number',  min: 0, max: 99999999 },
    { path: ['0', 3],        label: '等级',     type: 'number',  min: 1, max: 999 },
    { path: ['0', 4],        label: '经验',     type: 'number',  min: 0 },
    { path: ['0', 5],        label: '身高',     type: 'number',  min: 100, max: 300 },
    { path: ['0', 6],        label: '技能点',   type: 'number',  min: 0, max: 999999 },
    { path: ['0', 8],        label: '身价',     type: 'number',  min: 0 },
    { path: ['0', 9],        label: '虚拟币',   type: 'number',  min: 0 },
    { path: ['3'],           label: '主线进度', type: 'number',  min: 0 },
    { path: ['7', 0],        label: '健身 HP',  type: 'number',  min: 0 },
    { path: ['7', 1],        label: '健身 MP',  type: 'number',  min: 0 },
    { path: ['7', 2],        label: '健身空攻', type: 'number',  min: 0 },
    { path: ['7', 3],        label: '健身防御', type: 'number',  min: 0 },
    { path: ['7', 4],        label: '健身内力', type: 'number',  min: 0 }
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

  // 暴露
  window.ArchiveSchema = {
    SCHEMA_VERSION: SCHEMA_VERSION,
    fields: ARCHIVE_SCHEMA_V3_0,
    getByPath: getByPath,
    setByPath: setByPath,
    pathToString: pathToString,
    getWhitelistPathSet: getWhitelistPathSet
  };
})();
