'use strict';
const {atomicWriteJson}=require('../workbench-live-e2e/kshop/common');
// Windows readers can briefly deny replacement. Retry only transient filesystem
// errors; the existing writer still validates regular files and owns its temp.
function writeReport(filePath,value,options={}) {
    const write=options.write||atomicWriteJson;
    const wait=options.wait||((ms)=>Atomics.wait(new Int32Array(new SharedArrayBuffer(4)),0,0,ms));
    const attempts=options.attempts===undefined?101:options.attempts;
    if(!Number.isInteger(attempts)||attempts<1||attempts>101)throw Error('Invalid bounded report retry count');
    for(let attempt=1;attempt<=attempts;attempt++) {
        try{write(filePath,value);return {attempts:attempt};}
        catch(error){
            if(!['EBUSY','EPERM','EACCES'].includes(error.code)||attempt===attempts)throw error;
            wait(50);
        }
    }
}
module.exports={writeReport};
