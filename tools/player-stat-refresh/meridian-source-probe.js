'use strict';

const FILE = 'scripts/类定义/org/flashNight/arki/ui/MeridianPanelService.as';
module.exports = function run(source, report) {
    const node = {id:'hp1',bonusType:'hp',bonusAmount:50,cost:1};
    const root = {存档系统:{},savePath:'A',_saveExt:{meridians:{v:1,nodes:{hp1:true}}},虚拟币:0};
    // Node 只替换角色 generation 端口；真实 SaveManager/同槽切换另由原生 suite 验证。
    let owner=root.存档系统,slot=root.savePath,token={};
    const coordinator={contextToken(){
        if(owner!==root.存档系统 || slot!==root.savePath){owner=root.存档系统;slot=root.savePath;token={};}
        return token;
    }};
    const globals = {_root:root,_config:[{nodes:[node]}],_nodeIndex:{hp1:{node,meridianId:'m',order:1}},
        BONUS_TYPES:['innerPower','hp','mp','defense'],_caps:{innerPower:50,hp:1000,mp:1000,defense:500},
        _cache:{innerPower:0,hp:0,mp:0,defense:0},_raw:{innerPower:0,hp:0,mp:0,defense:0},
        _dirty:true,_lightResults:{hp1:{success:true,applied:true,nodeId:'hp1',savePending:false}},_skillMods:{},
        _contextOwner:undefined,_contextSlot:undefined,_contextExt:undefined,_contextToken:undefined,_contextStatToken:undefined,
        org:{flashNight:{arki:{unit:{PlayerStatRefreshCoordinator:{production:()=>coordinator}}}}},
        findMissingInfo:() => [],findOrderBlocker:() => null,findMissingValues:() => [],trace(){}};
    const names = ['getLitNodes','isLit','isBonusType','recomputeBonuses','getBonus','getRawBonus',
        'getCap','buildBonusSnapshot','attachBonuses','copyPending','executeLight','failLight'];
    for (const name of ['resetContext','ensureContext','clearContextCache','retryPendingSave','projectionStatus']) {
        if (source.read(FILE).text.includes('function ' + name + '(')) names.push(name);
    }
    const api = source.methods(FILE,names,globals);
    api.getBonus('hp');
    root.存档系统 = {};root.savePath = 'B';root._saveExt = {meridians:{v:1,nodes:{}}};
    report('meridian-context-bonus',api.getBonus('hp'),0,50);
    const result = api.executeLight('hp1');
    report('meridian-context-receipt',result.applied === true ? 'applied' : result.error,'insufficient_funds','applied');
};
