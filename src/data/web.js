'use strict';
// Single-port front end for the browser Quake 3 server, no dependencies.
//   GET  /...                  static files (game page, client, assets)
//   WebSocket upgrade on any   raw TCP pass-through to the game server on
//   path                       127.0.0.1:GAME_PORT, with X-Forwarded-For set
//                              to the real peer so bans and logs see it.
// Players only need WEB_PORT reachable.
const http = require('http');
const net = require('net');
const fs = require('fs');
const path = require('path');

const PORT = parseInt(process.env.WEB_PORT || '8080', 10);
const GAME_PORT = parseInt(process.env.GAME_PORT || '27960', 10);
const ROOT = path.resolve(process.env.WEB_ROOT || path.join(__dirname, 'html'));

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
  '.xml': 'application/xml',
  '.txt': 'text/plain; charset=utf-8',
};

function log(msg) { console.log(new Date().toISOString() + ' ' + msg); }

function send(res, code) {
  res.writeHead(code, { 'Content-Type': 'text/plain', 'X-Content-Type-Options': 'nosniff' });
  res.end(code + '\n');
}

const server = http.createServer((req, res) => {
  if (req.method !== 'GET' && req.method !== 'HEAD') return send(res, 405);
  let rel;
  try {
    rel = decodeURIComponent(new URL(req.url, 'http://local').pathname);
  } catch (e) {
    return send(res, 400);
  }
  if (rel.endsWith('/')) rel += 'index.html';
  const file = path.join(ROOT, path.normalize(rel));
  if (!file.startsWith(ROOT + path.sep)) return send(res, 403);

  fs.stat(file, (err, st) => {
    if (err || !st.isFile()) return send(res, 404);
    const ext = path.extname(file).toLowerCase();
    // Pages, code and the manifest change between builds; paks are
    // content-addressed by their CRC prefix and never change.
    const immutable = /\/assets\/.+/.test(rel) && !rel.endsWith('manifest.json');
    res.writeHead(200, {
      'Content-Type': TYPES[ext] || 'application/octet-stream',
      'Content-Length': st.size,
      'Cache-Control': immutable ? 'public, max-age=604800' : 'no-cache',
      'X-Content-Type-Options': 'nosniff',
      'X-Frame-Options': 'SAMEORIGIN',
    });
    if (req.method === 'HEAD') return res.end();
    fs.createReadStream(file).on('error', () => res.destroy()).pipe(res);
  });
});

server.on('upgrade', (req, client, head) => {
  if (String(req.headers.upgrade || '').toLowerCase() !== 'websocket') {
    return client.destroy();
  }
  const peer = String(client.remoteAddress || '').replace(/^::ffff:/, '');
  const upstream = net.connect(GAME_PORT, '127.0.0.1', () => {
    let out = req.method + ' ' + req.url + ' HTTP/1.1\r\n';
    for (let i = 0; i < req.rawHeaders.length; i += 2) {
      // Drop any client-supplied X-Forwarded-For: the game server trusts
      // this header from loopback, so only we may set it.
      if (req.rawHeaders[i].toLowerCase() === 'x-forwarded-for') continue;
      out += req.rawHeaders[i] + ': ' + req.rawHeaders[i + 1] + '\r\n';
    }
    out += 'X-Forwarded-For: ' + peer + '\r\n\r\n';
    upstream.write(out);
    if (head && head.length) upstream.write(head);
    client.pipe(upstream).pipe(client);
  });
  upstream.setNoDelay(true);
  client.setNoDelay(true);
  const close = () => { client.destroy(); upstream.destroy(); };
  upstream.on('error', close).on('close', close);
  client.on('error', close).on('close', close);
});

server.listen(PORT, '0.0.0.0', () => log('web listening on :' + PORT + ', game on 127.0.0.1:' + GAME_PORT));
process.on('SIGTERM', () => server.close(() => process.exit(0)));
