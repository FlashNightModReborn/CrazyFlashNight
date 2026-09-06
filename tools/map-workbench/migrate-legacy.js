// 一次性机械提取器；只允许在旧手写 JS 尚存在时使用，不是第二份配置真源。
'use strict';
const fs = require('fs'), path = require('path'), vm = require('vm');
const root = path.resolve(__dirname, '../..');
const panel = path.join(root, 'launcher/web/modules/map-panel-data.js');
const avatar = path.join(root, 'launcher/web/modules/map-avatar-source-data.js');
const s = {console}; vm.createContext(s);
const original = fs.readFileSync(panel, 'utf8');
if (!original.includes('var _xflLayoutOverrides =')) throw new Error('已经迁移，拒绝重复提取');
vm.runInContext(fs.readFileSync(avatar, 'utf8'), s);
vm.runInContext(original.replace('getManifest: getManifest,', 'getManifest: getManifest, authoring: function(){return {version:1,pageOrder:_pageOrder,pageAliases:_pageAliases,sourceRefs:_sourceRefs,unlockGroups:_unlockGroups,pageUnlockGroups:_pageUnlockGroups,handTunedLayoutIds:_handTunedLayoutIds,xflSourceRects:_xflSourceRects,pages:_pages};},'), s);
const definition = JSON.parse(JSON.stringify(s.MapPanelData.authoring()));
definition.avatarSources = s.MapAvatarSourceData.getAll();
const dest = path.join(root,'data/map/map_definition.json');
if (fs.existsSync(dest)) throw new Error('目标已存在');
fs.writeFileSync(dest, JSON.stringify(definition,null,2)+'\n');
// 保存旧投影作为本轮机器等价检查输入，不进入正式数据目录。
fs.mkdirSync(path.join(root,'tmp/map-workbench'),{recursive:true});
fs.writeFileSync(path.join(root,'tmp/map-workbench/legacy-manifest.json'),JSON.stringify(s.MapPanelData.exportManifest()));
console.log('提取地图定义；旧布局与头像投影已保存为本轮对照。');
