'use strict';
const fs = require('node:fs');
const net = require('node:net');
const path = require('node:path');
const root = path.resolve(process.argv[2]);
const server = net.createServer(socket => {
  let buffer = '';
  socket.on('error', () => {});
  socket.on('data', bytes => {
    buffer += bytes.toString('utf8');
    while (buffer.includes('\0')) {
      const index = buffer.indexOf('\0');
      const packet = buffer.slice(0, index);
      buffer = buffer.slice(index + 1);
      if (packet.includes('policy-file-request')) {
        socket.write('<cross-domain-policy><allow-access-from domain="127.0.0.1" to-ports="47183" /></cross-domain-policy>\0');
      } else if (packet === 'hello') {
        const request = JSON.parse(fs.readFileSync(path.join(root, 'request.json'), 'utf8'));
        if (request.phase === 'ready') socket.write('ready\0');
        else if (['write', 'read'].includes(request.phase)
          && /^[a-f0-9]{16}$/u.test(request.nonce)
          && request.slot === 'cf7_env_probe_' + request.nonce)
          socket.write([request.phase, request.nonce, request.slot].join('|') + '\0');
      } else {
        const [phase, nonce, slot, outcome] = packet.split('|');
        if (['write', 'read'].includes(phase) && /^[a-f0-9]{16}$/u.test(nonce)
          && slot === 'cf7_env_probe_' + nonce)
          fs.writeFileSync(path.join(root, 'result.json'), JSON.stringify({ phase, nonce, slot, outcome }));
      }
    }
  });
});
server.listen(47183, '127.0.0.1', () => fs.writeFileSync(path.join(root, 'server-ready'), String(process.pid)));
process.on('SIGTERM', () => server.close(() => process.exit(0)));
