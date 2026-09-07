#!/usr/bin/env node
'use strict';
// Preserved audit entrypoint; all condition/endpoint validation is owned by C#.
try {
    const result=require('./lib/map-domain.js').validateContent();
    const summary={success:true,pages:result.pages,locations:result.locations,tasks:result.tasks,unreadyWorldBindings:result.unreadyWorldBindings};
    console.log(process.argv.includes('--json')?JSON.stringify(summary,null,2):'PASS C# 地图内容、任务端点、素材闭包；未就绪绑定 '+summary.unreadyWorldBindings.length+'。');
} catch(error) { console.error(error.message); process.exitCode=1; }
