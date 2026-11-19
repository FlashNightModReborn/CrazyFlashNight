#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const compiler = path.resolve(__dirname, '../scripts/node_modules/typescript/bin/tsc');
if (!fs.existsSync(compiler)) throw new Error('Run npm ci --ignore-scripts --prefix launcher/scripts first (uses the existing locked TypeScript).');
const config = path.join(__dirname, 'tsconfig.json');
const destination = path.resolve(__dirname, '../scripts/dist/tooltip-bundle.js');
const check = process.argv.includes('--check');
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'cf7-tooltip-build-'));
const candidate = path.join(temp, 'tooltip-bundle.js');
function emit(file, bytes) {
    if (check) {
        if (!fs.existsSync(file) || !fs.readFileSync(file).equals(bytes))
            throw new Error(path.basename(file) + ' is stale; run node launcher/tooltip-engine/build.cjs');
    } else {
        fs.mkdirSync(path.dirname(file), {recursive:true});
        fs.writeFileSync(file, bytes);
    }
}
try {
    const built = spawnSync(process.execPath, [compiler, '-p', config, '--outFile', candidate], { stdio: 'inherit' });
    if (built.status !== 0) process.exitCode = built.status || 1;
    else {
        emit(destination, fs.readFileSync(candidate));
        const definitions = path.resolve(__dirname, '../../scripts/类定义/org/flashNight');
        const strings = fs.readFileSync(path.join(definitions,'gesh/string/StringUtils.as'),'utf8');
        const damage = fs.readFileSync(path.join(definitions,'arki/component/Damage/MagicDamageTypes.as'),'utf8');
        const entities = Object.fromEntries([...strings.matchAll(/htmlEntities\["&([^";]+);"\]\s*=\s*("(?:\\.|[^"\\])*")/g)]
            .map(match => [match[1],JSON.parse(match[2])]));
        const literal = /magicDamageTypesHash:Object\s*=\s*\{([^}]+)\}/.exec(damage);
        if (!literal || !Object.hasOwn(entities,'amp')) throw Error('Unable to extract Flash text contracts');
        const types = [...literal[1].matchAll(/([\w\u0080-\uffff]+)\s*:\s*true/g)].map(match => match[1]);
        if (!types.length) throw Error('Missing magic damage types');
        const modules = path.resolve(__dirname,'../scripts/node_modules');
        const result = require(path.join(modules,'esbuild')).buildSync({
            absWorkingDir:__dirname, entryPoints:['catalog/compiler.cjs'], nodePaths:[modules],
            bundle:true, format:'iife', globalName:'TooltipCatalog', platform:'neutral', target:'es2020',
            mainFields:['module','main'], write:false, legalComments:'inline',
            banner:{js:'/*!\n'+fs.readFileSync(path.join(__dirname,'catalog/THIRD-PARTY-NOTICES.txt'),'utf8').replace(/\r\n/g,'\n')+'*/'},
            define:{TOOLTIP_MAGIC_TYPES:JSON.stringify(types),TOOLTIP_HTML_ENTITIES:JSON.stringify(entities)}
        });
        emit(path.join(path.dirname(destination),'tooltip-catalog-compiler.js'),Buffer.from(result.outputFiles[0].contents));
        console.log('Tooltip engine and shared catalog compiler ' + (check ? 'current' : 'built'));
    }
} finally { fs.rmSync(temp, { recursive: true, force: true }); }
