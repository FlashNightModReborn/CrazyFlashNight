'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const read = relative => fs.readFileSync(path.join(root, relative), 'utf8');

const itemUtil = read('scripts/类定义/org/flashNight/arki/item/ItemUtil.as');
const enemyDrop = read('scripts/逻辑/单位函数/单位函数_lsy_敌人模板迁移.as');
const pickup = read('scripts/类定义/org/flashNight/arki/unit/Action/PickUp/PickUpManager.as');
const taskRewards = read('scripts/通信/通信_鸡蛋_任务系统.as');
const achievement = read('scripts/类定义/org/flashNight/arki/achievement/AchievementService.as');
const grantEffect = read('scripts/类定义/org/flashNight/arki/item/drug/effects/GrantItemEffect.as');
const informationXml = read('data/items/收集品_情报.xml');

assert(itemUtil.includes('planInformationAcquire'));
assert(itemUtil.includes('planRewardAcquire'));
assert(itemUtil.includes('acquireReward'));
assert(enemyDrop.includes('ItemUtil.planInformationAcquire'));
assert(enemyDrop.includes('{精确货币数量:true}'));
assert(!enemyDrop.includes('item.最大数量 = maxvalue - value'));
assert(pickup.includes('ItemUtil.acquireReward'));
assert(pickup.includes('var exactCurrency:Boolean = parameterObject.精确货币数量 === true'));
assert(pickup.includes('if (_root.存档系统 != undefined) _root.存档系统.dirtyMark = true;'));
assert(taskRewards.includes('ItemUtil.acquireReward(itemArray)'));
assert(achievement.includes('ItemUtil.acquireReward'));
assert(grantEffect.includes('ItemUtil.acquireReward'));

const itemBlocks = informationXml.match(/<item>[\s\S]*?<\/item>/g) || [];
assert(itemBlocks.length > 0, 'information catalog must not be empty');
for (const block of itemBlocks) {
    if (!/<use>\s*情报\s*<\/use>/.test(block)) continue;
    const name = (block.match(/<name>([\s\S]*?)<\/name>/) || [])[1] || '(unnamed)';
    const maximum = Number((block.match(/<maxvalue>([\s\S]*?)<\/maxvalue>/) || [])[1]);
    const price = Number((block.match(/<price>([\s\S]*?)<\/price>/) || [])[1]);
    assert(Number.isInteger(maximum) && maximum > 0, `${name} requires a positive integer maxvalue`);
    assert(Number.isFinite(price) && price >= 0, `${name} requires a non-negative overflow price`);
}

process.stdout.write(`information overflow policy: ${itemBlocks.length} catalog entries checked\n`);
