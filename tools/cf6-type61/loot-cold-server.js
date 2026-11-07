'use strict';
const fs=require('node:fs'),net=require('node:net'),path=require('node:path');
const root=path.resolve(process.argv[2]);
const valid=r=>['decide','admit','claim','read'].includes(r.phase)
  && /^[a-f0-9]{16}$/u.test(r.nonce) && r.slot==='cf7_env_cf6_loot_'+r.nonce
  && ['longgun','sidearm_pair','none','guarantee'].includes(r.kind);
const server=net.createServer(socket=>{
  fs.appendFileSync(path.join(root,'connections.log'),'connect '+new Date().toISOString()+'\n');
  let buffer='';socket.on('error',()=>{});
  socket.on('data',bytes=>{
    buffer+=bytes.toString('utf8');if(buffer.length>16384){socket.destroy();return;}
    while(buffer.includes('\0')){
      const at=buffer.indexOf('\0'),packet=buffer.slice(0,at);buffer=buffer.slice(at+1);
      fs.appendFileSync(path.join(root,'connections.log'),packet.slice(0,1024)+'\n');
      if(packet.includes('policy-file-request')){
        // A local network-mode SWF has no web origin. This disposable server
        // exposes only its loopback port and the exact current synthetic slot.
        socket.write('<cross-domain-policy><allow-access-from domain="*" to-ports="47184" /></cross-domain-policy>\0');
      }else if(packet==='hello'){
        const r=JSON.parse(fs.readFileSync(path.join(root,'request.json'),'utf8').replace(/^\uFEFF/u,''));
        if(r.phase==='ready')socket.write('ready\0');
        else if(valid(r))socket.write([r.phase,r.nonce,r.slot,r.kind].join('|')+'\0');
      }else{
        const [phase,nonce,slot,kind,outcome,rolls]=packet.split('|'),r={phase,nonce,slot,kind,outcome,rolls:Number(rolls)};
        const expected=JSON.parse(fs.readFileSync(path.join(root,'request.json'),'utf8').replace(/^\uFEFF/u,''));
        if(valid(r)&&['phase','nonce','slot','kind'].every(k=>r[k]===expected[k]))
          fs.writeFileSync(path.join(root,'result.json'),JSON.stringify(r));
      }
    }
  });
});
server.listen(47184,'127.0.0.1',()=>fs.writeFileSync(path.join(root,'server-ready'),String(process.pid)));
process.on('SIGTERM',()=>server.close(()=>process.exit(0)));
