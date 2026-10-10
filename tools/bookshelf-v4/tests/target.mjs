import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
export const ROOT=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../../..');
export function target(relative){
 relative=relative.replace(/^web\//,'launcher/web/');
 relative=relative.replace('modules/preview-shelf-scene.js','modules/bookshelf-shelf-scene.js');
 relative=relative.replace(/modules\/(layout-core\.mjs|layout-three\.js|interaction-core\.mjs)$/,'modules/bookshelf/shelf/$1');
 return path.join(ROOT,relative);
}
export const targetUrl=relative=>pathToFileURL(target(relative)).href;
export function resultFile(name){
 const directory=path.join(ROOT,'tmp/bookshelf-v4-qa');fs.mkdirSync(directory,{recursive:true});
 return path.join(directory,name);
}
