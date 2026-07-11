'use strict';

// Zero-dependency HTTP server. Configuration is injected via the Kubernetes
// ConfigMap (see harness/manifests/configmap.yaml) as environment variables.
const http = require('http');
const os = require('os');

const PORT = parseInt(process.env.PORT || '8080', 10);
const APP_MESSAGE = process.env.APP_MESSAGE || 'Hello from the Harness sample app';
const GREETING_COLOR = process.env.GREETING_COLOR || '#0263f4';
const LOG_LEVEL = (process.env.LOG_LEVEL || 'info').toLowerCase();
const RELEASE = process.env.RELEASE_NAME || 'local';

function log(level, msg) {
  const order = { debug: 10, info: 20, warn: 30, error: 40 };
  if ((order[level] || 20) >= (order[LOG_LEVEL] || 20)) {
    process.stdout.write(`[${new Date().toISOString()}] ${level.toUpperCase()} ${msg}\n`);
  }
}

const server = http.createServer((req, res) => {
  log('debug', `${req.method} ${req.url}`);

  if (req.url === '/healthz' || req.url === '/readyz') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    return res.end('ok');
  }

  if (req.url === '/api') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    return res.end(
      JSON.stringify({
        message: APP_MESSAGE,
        host: os.hostname(),
        release: RELEASE,
        uptimeSeconds: Math.round(process.uptime()),
      })
    );
  }

  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
  res.end(`<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>Harness Sample App</title>
<style>
  body { font-family: -apple-system, Segoe UI, Roboto, sans-serif; background:#0b1020; color:#e6e9f0; display:flex; min-height:100vh; align-items:center; justify-content:center; margin:0; }
  .card { background:#151b31; padding:48px 56px; border-radius:16px; box-shadow:0 20px 60px rgba(0,0,0,.4); text-align:center; }
  h1 { color:${GREETING_COLOR}; margin:0 0 12px; }
  code { background:#0b1020; padding:2px 8px; border-radius:6px; }
</style></head>
<body>
  <div class="card">
    <h1>${APP_MESSAGE}</h1>
    <p>Served by pod <code>${os.hostname()}</code></p>
    <p>Release: <code>${RELEASE}</code> &middot; Log level: <code>${LOG_LEVEL}</code></p>
  </div>
</body></html>`);
});

server.listen(PORT, () => log('info', `sample-web listening on :${PORT}`));
