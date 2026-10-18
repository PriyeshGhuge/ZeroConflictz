/**
 * ZeroConflict CLI - Localhost Development & Distribution Server
 *
 * Runs locally on http://localhost:3000 with zero external dependencies.
 * - Browser requests (Accept: text/html): Serves an interactive landing page.
 * - Terminal requests (curl, wget): Serves install.sh.
 * - PowerShell requests (irm, powershell): Serves install.ps1.
 * - Explicit routes: /cli, /cli.ps1, /win, /health.
 */

const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = process.env.PORT || 3000;
const BASE_DIR = __dirname;

function isPowerShell(userAgent) {
  if (!userAgent) return false;
  const ua = userAgent.toLowerCase();
  return (
    ua.includes('powershell') ||
    ua.includes('pwsh') ||
    ua.includes('invoke-webrequest') ||
    ua.includes('invoke-restmethod') ||
    ua.includes('winhttp')
  );
}

function isBrowser(acceptHeader) {
  if (!acceptHeader) return false;
  return acceptHeader.includes('text/html');
}

function serveFile(res, filePath, contentType) {
  try {
    if (!fs.existsSync(filePath)) {
      res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end('404 Not Found\n');
      return;
    }
    const content = fs.readFileSync(filePath, 'utf8');
    res.writeHead(200, {
      'Content-Type': contentType,
      'Access-Control-Allow-Origin': '*',
      'Cache-Control': 'no-cache',
    });
    res.end(content);
  } catch (err) {
    res.writeHead(500, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end(`500 Server Error: ${err.message}\n`);
  }
}

function getLandingHtml() {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>ZeroConflict CLI - Localhost Distribution Server</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&family=JetBrains+Mono:wght@400;500;600&display=swap" rel="stylesheet">
  <style>
    :root {
      --bg: #090d16;
      --card-bg: rgba(18, 24, 38, 0.7);
      --card-border: rgba(255, 255, 255, 0.08);
      --text: #f0f4fc;
      --text-muted: #8b9bb4;
      --accent: #3b82f6;
      --accent-glow: rgba(59, 130, 246, 0.4);
      --accent-cyan: #06b6d4;
      --accent-green: #10b981;
      --code-bg: #0d121f;
    }

    * { box-sizing: border-box; margin: 0; padding: 0; }

    body {
      font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
      background: var(--bg);
      color: var(--text);
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      align-items: center;
      padding: 40px 20px;
      overflow-x: hidden;
      background-image: 
        radial-gradient(ellipse 80% 50% at 50% -20%, rgba(59, 130, 246, 0.25), transparent),
        radial-gradient(circle at 10% 30%, rgba(6, 182, 212, 0.1), transparent 40%),
        radial-gradient(circle at 90% 70%, rgba(139, 92, 246, 0.1), transparent 40%);
    }

    .container {
      max-width: 900px;
      width: 100%;
    }

    header {
      text-align: center;
      margin-bottom: 48px;
    }

    .badge {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      padding: 6px 14px;
      border-radius: 9999px;
      font-size: 13px;
      font-weight: 600;
      background: rgba(16, 185, 129, 0.15);
      border: 1px solid rgba(16, 185, 129, 0.3);
      color: var(--accent-green);
      margin-bottom: 20px;
      letter-spacing: 0.3px;
    }

    .badge-dot {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background: var(--accent-green);
      box-shadow: 0 0 10px var(--accent-green);
      animation: pulse 2s infinite;
    }

    @keyframes pulse {
      0%, 100% { opacity: 1; transform: scale(1); }
      50% { opacity: 0.4; transform: scale(0.85); }
    }

    h1 {
      font-size: 44px;
      font-weight: 800;
      letter-spacing: -0.03em;
      background: linear-gradient(135deg, #ffffff 40%, #93c5fd 100%);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
      margin-bottom: 14px;
    }

    p.subtitle {
      font-size: 18px;
      color: var(--text-muted);
      max-width: 620px;
      margin: 0 auto;
      line-height: 1.5;
    }

    .card {
      background: var(--card-bg);
      border: 1px solid var(--card-border);
      border-radius: 16px;
      padding: 28px;
      margin-bottom: 24px;
      backdrop-filter: blur(12px);
      box-shadow: 0 20px 40px rgba(0, 0, 0, 0.4);
    }

    .card-title {
      font-size: 20px;
      font-weight: 700;
      margin-bottom: 18px;
      display: flex;
      align-items: center;
      gap: 10px;
    }

    .tabs {
      display: flex;
      gap: 8px;
      margin-bottom: 16px;
      border-bottom: 1px solid var(--card-border);
      padding-bottom: 10px;
    }

    .tab-btn {
      background: transparent;
      border: none;
      color: var(--text-muted);
      font-size: 14px;
      font-weight: 600;
      padding: 8px 16px;
      border-radius: 8px;
      cursor: pointer;
      transition: all 0.2s ease;
    }

    .tab-btn.active {
      background: rgba(59, 130, 246, 0.2);
      color: #60a5fa;
      border: 1px solid rgba(59, 130, 246, 0.3);
    }

    .snippet-box {
      background: var(--code-bg);
      border: 1px solid var(--card-border);
      border-radius: 12px;
      padding: 16px 20px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 16px;
      font-family: 'JetBrains Mono', monospace;
      font-size: 14px;
      color: #e2e8f0;
      position: relative;
    }

    .snippet-text {
      overflow-x: auto;
      white-space: nowrap;
    }

    .copy-btn {
      background: rgba(255, 255, 255, 0.08);
      border: 1px solid rgba(255, 255, 255, 0.12);
      color: var(--text);
      padding: 8px 14px;
      border-radius: 8px;
      cursor: pointer;
      font-size: 13px;
      font-weight: 600;
      display: inline-flex;
      align-items: center;
      gap: 6px;
      transition: all 0.2s ease;
      flex-shrink: 0;
    }

    .copy-btn:hover {
      background: rgba(59, 130, 246, 0.3);
      border-color: rgba(59, 130, 246, 0.5);
      color: #fff;
    }

    .grid-2 {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
      gap: 16px;
      margin-top: 20px;
    }

    .grid-card {
      background: rgba(13, 18, 31, 0.6);
      border: 1px solid var(--card-border);
      border-radius: 12px;
      padding: 20px;
    }

    .grid-card h3 {
      font-size: 16px;
      margin-bottom: 8px;
      color: #93c5fd;
    }

    .grid-card p {
      font-size: 13px;
      color: var(--text-muted);
      line-height: 1.5;
    }

    .endpoint-item {
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding: 12px 16px;
      background: rgba(13, 18, 31, 0.5);
      border: 1px solid var(--card-border);
      border-radius: 8px;
      margin-bottom: 8px;
      font-family: 'JetBrains Mono', monospace;
      font-size: 13px;
    }

    .endpoint-path {
      color: #38bdf8;
      font-weight: 600;
    }

    .endpoint-desc {
      color: var(--text-muted);
      font-family: 'Inter', sans-serif;
      font-size: 12px;
    }

    .endpoint-link {
      color: #60a5fa;
      text-decoration: none;
      font-weight: 500;
      border: 1px solid rgba(96, 165, 250, 0.3);
      padding: 4px 10px;
      border-radius: 6px;
      transition: all 0.2s ease;
    }

    .endpoint-link:hover {
      background: rgba(96, 165, 250, 0.2);
    }

    footer {
      text-align: center;
      margin-top: 40px;
      font-size: 13px;
      color: var(--text-muted);
    }
  </style>
</head>
<body>

  <div class="container">
    <header>
      <div class="badge">
        <span class="badge-dot"></span>
        Localhost Server Active on Port ${PORT}
      </div>
      <h1>ZeroConflict CLI</h1>
      <p class="subtitle">Stream-safe, cross-platform installation and release distribution service running on your local machine.</p>
    </header>

    <div class="card">
      <div class="card-title">⚡ Install Commands</div>
      <div class="tabs">
        <button class="tab-btn active" onclick="switchTab('unix')">Linux & macOS (sh)</button>
        <button class="tab-btn" onclick="switchTab('win')">Windows (PowerShell)</button>
      </div>

      <div id="tab-unix" class="tab-content">
        <div class="snippet-box">
          <span class="snippet-text" id="cmd-unix">curl -fsSL http://localhost:${PORT}/ | sh</span>
          <button class="copy-btn" onclick="copySnippet('cmd-unix')">Copy</button>
        </div>
      </div>

      <div id="tab-win" class="tab-content" style="display: none;">
        <div class="snippet-box">
          <span class="snippet-text" id="cmd-win">irm http://localhost:${PORT}/ | iex</span>
          <button class="copy-btn" onclick="copySnippet('cmd-win')">Copy</button>
        </div>
      </div>
    </div>

    <div class="card">
      <div class="card-title">🌐 Live Localhost Endpoints</div>
      <div class="endpoint-item">
        <span class="endpoint-path">GET / or /cli</span>
        <span class="endpoint-desc">Dynamic dispatch (Browser: UI | sh: install.sh | pwsh: install.ps1)</span>
        <a href="/cli" class="endpoint-link" target="_blank">View /cli</a>
      </div>
      <div class="endpoint-item">
        <span class="endpoint-path">GET /cli.ps1 (or /win)</span>
        <span class="endpoint-desc">PowerShell Installer script (install.ps1)</span>
        <a href="/cli.ps1" class="endpoint-link" target="_blank">View /cli.ps1</a>
      </div>
      <div class="endpoint-item">
        <span class="endpoint-path">GET /health</span>
        <span class="endpoint-desc">JSON health status</span>
        <a href="/health" class="endpoint-link" target="_blank">Check /health</a>
      </div>
    </div>

    <div class="grid-2">
      <div class="grid-card">
        <h3>🛡️ Stream-Safe POSIX</h3>
        <p>POSIX sh installer wraps execution in closed blocks to prevent incomplete scripts from executing upon connection drops.</p>
      </div>
      <div class="grid-card">
        <h3>⚡ Windows Native</h3>
        <p>Detects AMD64/ARM64, verifies SHA-256 via Get-FileHash, and updates User PATH permanently.</p>
      </div>
      <div class="grid-card">
        <h3>☁️ Cloudflare Edge Ready</h3>
        <p>Configured with worker.js and wrangler.toml for instant multi-region edge deployment.</p>
      </div>
      <div class="grid-card">
        <h3>📦 6-Platform Matrix</h3>
        <p>Pre-configured GitHub Actions workflow and Makefile to build Linux, macOS, and Windows binaries.</p>
      </div>
    </div>

    <footer>
      ZeroConflict CLI &middot; Local Server running at http://localhost:${PORT}
    </footer>
  </div>

  <script>
    function switchTab(type) {
      document.querySelectorAll('.tab-btn').forEach(btn => btn.classList.remove('active'));
      document.querySelectorAll('.tab-content').forEach(content => content.style.display = 'none');
      if (type === 'unix') {
        document.querySelectorAll('.tab-btn')[0].classList.add('active');
        document.getElementById('tab-unix').style.display = 'block';
      } else {
        document.querySelectorAll('.tab-btn')[1].classList.add('active');
        document.getElementById('tab-win').style.display = 'block';
      }
    }

    function copySnippet(id) {
      const text = document.getElementById(id).innerText;
      navigator.clipboard.writeText(text).then(() => {
        alert('Copied to clipboard: ' + text);
      });
    }
  </script>
</body>
</html>`;
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const pathname = url.pathname.toLowerCase().replace(/\/+$/, '') || '/';
  const userAgent = req.headers['user-agent'] || '';
  const acceptHeader = req.headers['accept'] || '';

  console.log(`[${new Date().toLocaleTimeString()}] ${req.method} ${pathname} (UA: ${userAgent.slice(0, 40)})`);

  // Health endpoint
  if (pathname === '/health') {
    res.writeHead(200, {
      'Content-Type': 'application/json; charset=utf-8',
      'Access-Control-Allow-Origin': '*',
    });
    res.end(
      JSON.stringify(
        {
          status: 'healthy',
          server: 'zeroconflict-localhost-server',
          port: PORT,
          timestamp: new Date().toISOString(),
          endpoints: ['/', '/cli', '/cli.ps1', '/win', '/health'],
        },
        null,
        2
      )
    );
    return;
  }

  // Windows installer explicit routes
  if (pathname === '/cli.ps1' || pathname === '/win' || pathname === '/install.ps1') {
    return serveFile(res, path.join(BASE_DIR, 'install.ps1'), 'text/plain; charset=utf-8');
  }

  // Unix installer explicit routes
  if (pathname === '/cli' || pathname === '/sh' || pathname === '/install.sh') {
    return serveFile(res, path.join(BASE_DIR, 'install.sh'), 'text/plain; charset=utf-8');
  }

  // Root route: Dynamic dispatch based on client type
  if (pathname === '/') {
    // 1. Browser navigation -> Interactive UI
    if (isBrowser(acceptHeader)) {
      res.writeHead(200, {
        'Content-Type': 'text/html; charset=utf-8',
        'Cache-Control': 'no-cache',
      });
      return res.end(getLandingHtml());
    }

    // 2. PowerShell clients -> install.ps1
    if (isPowerShell(userAgent)) {
      return serveFile(res, path.join(BASE_DIR, 'install.ps1'), 'text/plain; charset=utf-8');
    }

    // 3. Default (curl, wget, terminal) -> install.sh
    return serveFile(res, path.join(BASE_DIR, 'install.sh'), 'text/plain; charset=utf-8');
  }

  res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
  res.end('404 Not Found\n');
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`====================================================`);
  console.log(` ZeroConflict Localhost Server is running!`);
  console.log(` Web UI:        http://localhost:${PORT}/`);
  console.log(` Shell (sh):    http://localhost:${PORT}/cli`);
  console.log(` Win (ps1):     http://localhost:${PORT}/cli.ps1`);
  console.log(` Health:        http://localhost:${PORT}/health`);
  console.log(`====================================================`);
});
