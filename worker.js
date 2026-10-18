/**
 * ZeroConflict CLI Installer - Cloudflare Worker
 *
 * Serves install.sh and install.ps1 directly from the GitHub repository
 * with CDN edge caching and intelligent User-Agent dispatch.
 */

// Default configuration (can be overridden via Cloudflare Worker environment variables)
const DEFAULT_REPO = "ZeroConflictz/cli";
const DEFAULT_BRANCH = "main";
const CACHE_TTL_SECONDS = 300; // 5-minute CDN edge cache

export default {
  async fetch(request, env, ctx) {
    // Only allow GET and HEAD requests
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("Method Not Allowed", {
        status: 405,
        headers: {
          "Allow": "GET, HEAD",
          "Content-Type": "text/plain; charset=utf-8",
        },
      });
    }

    const url = new URL(request.url);
    const pathname = url.pathname.toLowerCase().replace(/\/+$/, "") || "/";
    const userAgent = request.headers.get("user-agent") || "";

    const repo = env.GITHUB_REPO || DEFAULT_REPO;
    const branch = env.GITHUB_BRANCH || DEFAULT_BRANCH;

    // -----------------------------------------------------------------------
    // Health Check Endpoint
    // -----------------------------------------------------------------------
    if (pathname === "/health") {
      return new Response(
        JSON.stringify(
          {
            status: "healthy",
            service: "zeroconflict-cli-installer",
            timestamp: new Date().toISOString(),
            upstream: {
              repo,
              branch,
            },
            routes: {
              shell_installer: ["/", "/cli"],
              powershell_installer: ["/cli.ps1", "/win"],
              health: "/health",
            },
          },
          null,
          2
        ),
        {
          status: 200,
          headers: {
            "Content-Type": "application/json; charset=utf-8",
            "Cache-Control": "no-cache, no-store, must-revalidate",
          },
        }
      );
    }

    // -----------------------------------------------------------------------
    // User-Agent Detection (PowerShell / Windows Client)
    // -----------------------------------------------------------------------
    const isPowerShellClient = isPowerShell(userAgent);

    let scriptToServe = null;

    if (pathname === "/" || pathname === "/cli") {
      // Dynamic content negotiation based on User-Agent:
      // If invoked via PowerShell (e.g., irm https://domain/cli | iex), serve install.ps1
      // If invoked via curl/wget/browser, serve install.sh
      scriptToServe = isPowerShellClient ? "install.ps1" : "install.sh";
    } else if (pathname === "/cli.ps1" || pathname === "/win") {
      scriptToServe = "install.ps1";
    } else if (pathname === "/install.sh" || pathname === "/sh") {
      scriptToServe = "install.sh";
    } else {
      return new Response("Not Found\n\nValid routes: / (or /cli), /cli.ps1, /win, /health\n", {
        status: 404,
        headers: { "Content-Type": "text/plain; charset=utf-8" },
      });
    }

    return await fetchAndCacheScript(scriptToServe, request, repo, branch, ctx);
  },
};

/**
 * Checks if the request User-Agent originates from PowerShell, Windows Terminal,
 * or standard Windows HTTP download clients.
 */
function isPowerShell(userAgent) {
  const ua = userAgent.toLowerCase();
  return (
    ua.includes("powershell") ||
    ua.includes("pwsh") ||
    ua.includes("invoke-webrequest") ||
    ua.includes("invoke-restmethod") ||
    ua.includes("winhttp")
  );
}

/**
 * Fetches the raw installer script from GitHub with Cloudflare Edge Caching.
 */
async function fetchAndCacheScript(filename, request, repo, branch, ctx) {
  const cacheKey = new URL(`https://cache.installer.local/${repo}/${branch}/${filename}`);
  const cache = caches.default;

  // Check Cloudflare Cache API first
  let cachedResponse = await cache.match(cacheKey);
  if (cachedResponse) {
    const resHeaders = new Headers(cachedResponse.headers);
    resHeaders.set("X-Cache-Status", "HIT");
    return new Response(cachedResponse.body, {
      status: cachedResponse.status,
      statusText: cachedResponse.statusText,
      headers: resHeaders,
    });
  }

  // Fetch directly from GitHub raw content
  const rawUrl = `https://raw.githubusercontent.com/${repo}/${branch}/${filename}`;
  const upstreamResponse = await fetch(rawUrl, {
    headers: {
      "User-Agent": "ZeroConflict-Cloudflare-Worker",
    },
    cf: {
      cacheTtl: CACHE_TTL_SECONDS,
      cacheEverything: true,
    },
  });

  if (!upstreamResponse.ok) {
    return new Response(
      `Failed to retrieve installer (${filename}) from upstream GitHub repository: ${upstreamResponse.statusText}\n`,
      {
        status: 502,
        headers: { "Content-Type": "text/plain; charset=utf-8" },
      }
    );
  }

  const scriptContent = await upstreamResponse.text();

  const responseHeaders = new Headers({
    "Content-Type": "text/plain; charset=utf-8",
    "Cache-Control": `public, max-age=${CACHE_TTL_SECONDS}, s-maxage=${CACHE_TTL_SECONDS}`,
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "X-Script-Target": filename,
    "X-Cache-Status": "MISS",
  });

  const responseToReturn = new Response(scriptContent, {
    status: 200,
    headers: responseHeaders,
  });

  // Store in edge cache asynchronously without blocking the response
  const responseToCache = responseToReturn.clone();
  ctx.waitUntil(cache.put(cacheKey, responseToCache));

  return responseToReturn;
}
