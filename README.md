# ZeroConflict CLI - Release & Distribution Automation

This repository contains the complete cross-platform build, release, and installation infrastructure for the **ZeroConflict CLI**.

---

## 1. Quick Installation & Localhost Server

Your distribution and installer server is live on localhost:
- **Web UI & Dashboard**: [http://localhost:3000/](http://localhost:3000/)
- **Health Endpoint**: [http://localhost:3000/health](http://localhost:3000/health)

### Linux & macOS (POSIX Shell)
```sh
# Via Localhost
curl -fsSL http://localhost:3000/ | sh

# Via Production Edge Domain
curl -fsSL https://cli.example.com/ | sh
```

### Windows (PowerShell)
```powershell
# Via Localhost
irm http://localhost:3000/ | iex

# Via Production Edge Domain
irm https://cli.example.com/ | iex
```

### Starting the Localhost Server Manually
```sh
# Run with Node.js directly
node server.js

# Or via npm
npm start
```

---

## 2. Architecture & Components

```
.
├── .github/
│   └── workflows/
│       └── release.yml        # GitHub Actions matrix compilation & release pipeline
├── scripts/
│   ├── build.sh               # Local cross-compilation POSIX shell script
│   └── build.ps1              # Local cross-compilation PowerShell script
├── install.sh                 # Stream-safe POSIX installer (macOS/Linux)
├── install.ps1                # Stream-safe PowerShell installer (Windows)
├── worker.js                  # Cloudflare Worker installer router & edge cache
├── wrangler.toml              # Cloudflare Worker configuration
├── Makefile                   # Production build & cross-compilation targets
├── go.mod                     # Go module definition
└── main.go                    # CLI entrypoint with version & build metadata
```

---

## 3. GitHub Actions Release Workflow (`.github/workflows/release.yml`)

Triggered automatically upon pushing any tag matching `v*.*.*` (e.g., `git tag v1.0.0 && git push origin v1.0.0`):

1. **Multi-Platform Matrix Build**:
   - **Linux**: `amd64` (x86_64) & `arm64` packaged as `.tar.gz`
   - **macOS**: `amd64` (Intel x86_64) & `arm64` (Apple Silicon) packaged as `.tar.gz`
   - **Windows**: `amd64` (x86_64) & `arm64` packaged as `.zip`
2. **Metadata Injection**:
   - Injects `-s -w` and ldflags: `main.version`, `main.commit`, `main.date`.
3. **Artifact Aggregation & SHA-256 Checksums**:
   - Downloads all compiled packages to a single stage.
   - Computes `checksums.txt` containing SHA-256 hashes of all release packages.
4. **Publishing**:
   - Uses `softprops/action-gh-release@v2` to publish the 6 archives and `checksums.txt` to GitHub Releases with auto-generated release notes.

---

## 4. Local Cross-Compilation

To reproduce the multi-platform build matrix locally:

### Using `make`:
```sh
# Build for current host platform
make build

# Cross-compile for all 6 target architectures, package, and generate dist/checksums.txt
make build-all

# Clean dist and build directories
make clean
```

### Using helper scripts:
```sh
# On Linux / macOS / Git Bash:
./scripts/build.sh

# On Windows PowerShell:
.\scripts\build.ps1
```

All generated archives and `checksums.txt` are output to the `dist/` directory.

---

## 5. Client Installers

### POSIX Shell Installer (`install.sh`)
- **Stream-Safe**: Functions are parsed before execution; network drops during `curl | sh` abort cleanly without executing partial shell commands.
- **Auto-Detection**: Identifies `Linux`/`Darwin` and `x86_64`/`arm64`.
- **Integrity**: Fetches release metadata from GitHub API, downloads the archive, and validates the SHA-256 hash against `checksums.txt` using `sha256sum` or `shasum`.
- **Permission-Aware**: Checks `/usr/local/bin` write permissions; safely falls back to `~/.local/bin` without prompting for `sudo`.
- **PATH Guidance**: Verifies if the install directory is in `$PATH` and gives copy-paste instructions for `.bashrc` / `.zshrc`.

### PowerShell Installer (`install.ps1`)
- **Windows Architecture**: Detects `x64` and `ARM64`.
- **Integrity**: Computes SHA-256 using `Get-FileHash` and verifies against `checksums.txt`.
- **Installation Directory**: Installs to `$HOME\.local\bin`.
- **Environment Management**: Appends directory to User PATH permanently via `[Environment]::SetEnvironmentVariable` and updates the current session's `$env:PATH` for immediate availability.

---

## 6. Cloudflare Worker (`worker.js`)

Deploys to a custom domain (e.g. `cli.example.com`):
- **Dynamic Routing**:
  - `GET /` or `GET /cli`: Serves `install.sh` by default; auto-detects PowerShell user-agents and serves `install.ps1`.
  - `GET /cli.ps1` or `GET /win`: Directly serves `install.ps1`.
  - `GET /health`: JSON health status with endpoint mappings.
- **Edge Caching**: Proxies raw files from GitHub `main` branch with a 5-minute CDN edge cache (`Cache-Control: public, max-age=300`).
