'use strict';

const {fixture} = require('./runtime-source-probe');
const MORPH = 'scripts/逻辑/装备函数/烬灭裁决.as';
const RHINO = 'scripts/逻辑/单位函数/单位函数_雾人_aka_fs_主动战技.as';

function item(source, relativePath, name) {
    const read = source.read(relativePath);
    source.evidence.push({path:relativePath,sha256:read.hash,kind:'real-item-xml'});
    const block = read.text.match(/<item>[\s\S]*?<\/item>/g).find(text => text.includes('<name>' + name + '</name>'));
    const data = block.match(/<data>([\s\S]*?)<\/data>/)[1];
    const result = {};
    for (const match of data.matchAll(/<([\w]+)>([^<]*)<\/\1>/g)) {
        const numeric = Number(match[2]);
        result[match[1]] = match[2].trim() !== '' && Number.isFinite(numeric) ? numeric : match[2];
    }
    return result;
}

module.exports = function run(source, report) {
    if(source.read(MORPH).text.includes('requestPersistentRefresh')) return require('./fixed-source-probes').morph(source,report,item);
    const long = item(source,'data/items/武器_刀_长柄.xml','烬灭裁决');
    const dual = item(source,'data/items/武器_刀_双刀.xml','烬灭裁决双刀');
    const root = {getItemData:name => ({data:{...(name === '烬灭裁决' ? long : dual)}}),
        装备引用配置:{刷新所有装扮(){}}};
    const apply = source.fn(MORPH,'_root.装备生命周期函数.烬灭裁决_应用形态 =',{_root:root});
    const unit = {刀:{name:'烬灭裁决',value:{长柄形态:true}},刀属性:{...long},
        hp基本满血值:1000,mp基本满血值:500,基本防御力:100,
        hp满血值装备加层:long.hp,mp满血值装备加层:long.mp,装备防御力:long.defence || 0,
        hp满血值:1550,mp满血值:900,hp:600,mp:200,吸血:long.vampirism,击溃:long.rout,
        装载主动战技(){}};
    const ref = {自机:unit,装备类型:'刀',是否为主角:false};
    const powers = [unit.刀属性.power];
    apply(ref,false);powers.push(unit.刀属性.power);apply(ref,false);powers.push(unit.刀属性.power);
    report('morph-same-mode',powers,[565,565,565],[565,601,639]);
    report('morph-build-contribution',unit.hp满血值,1550,1200);

    const f = fixture(source), t = f.target;
    t._name = 'rhino';t.基本空手攻击力 = 500;t.空手攻击力 = 500;
    t.刀属性 = t.刀数据.data = {power:80};
    Object.assign(t,{头部装备:'黑犀头甲',上装装备:'黑犀胸甲',手部装备:'黑犀手甲',下装装备:'黑犀腿甲',脚部装备:'黑犀鞋'});
    f.root.控制目标 = 'other';f.root.发布消息 = () => {};f.root.战技路由 = {战技标签跳转_旧(){}};
    const globals = {_root:f.root,EffectSystem:{Effect(){}}};
    const begin = source.fn(RHINO,['_root.主动战技函数.兵器.狂瀑扎 =','释放: function'],globals,true);
    const end = source.fn(RHINO,['_root.主动战技函数.空手.狂瀑顶 =','释放: function'],globals,true);
    begin(t);f.api.updateProperties(t);end(t);
    report('rhino-paired-transfer',[t.空手攻击力,t.刀属性.power],[500,80],[900,80]);
};
