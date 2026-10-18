#!/bin/sh
# ==============================================================================
# ZeroConflict CLI - POSIX-Compliant Stream-Safe Installer
# Usage: curl -fsSL https://<domain>/cli | sh
# ==============================================================================

set -eu

# Guard against partial downloads executing in pipe
main() {
    # -------------------------------------------------------------------------
    # UI & Color Setup
    # -------------------------------------------------------------------------
    if [ -t 1 ]; then
        COLOR_RESET="\033[0m"
        COLOR_RED="\033[1;31m"
        COLOR_GREEN="\033[1;32m"
        COLOR_YELLOW="\033[1;33m"
        COLOR_BLUE="\033[1;34m"
        COLOR_CYAN="\033[1;36m"
        COLOR_BOLD="\033[1m"
    else
        COLOR_RESET=""
        COLOR_RED=""
        COLOR_GREEN=""
        COLOR_YELLOW=""
        COLOR_BLUE=""
        COLOR_CYAN=""
        COLOR_BOLD=""
    fi

    log_info()    { printf "${COLOR_BLUE}==>${COLOR_RESET} %s\n" "$*"; }
    log_ok()      { printf "  ${COLOR_GREEN}[ok]${COLOR_RESET} %s\n" "$*"; }
    log_warn()    { printf "  ${COLOR_YELLOW}[! ]${COLOR_RESET} %s\n" "$*"; }
    log_error()   { printf "${COLOR_RED}Error:${COLOR_RESET} %s\n" "$*" >&2; }
    log_step()    { printf "  ${COLOR_CYAN}->${COLOR_RESET} %s\n" "$*"; }

    # -------------------------------------------------------------------------
    # Configuration
    # -------------------------------------------------------------------------
    BIN_NAME="${BIN_NAME:-zeroconflict}"
    GITHUB_REPO="${GITHUB_REPO:-ZeroConflictz/cli}"
    TARGET_VERSION="${VERSION:-}"

    log_info "Starting installer for ${COLOR_BOLD}${BIN_NAME}${COLOR_RESET}..."

    # -------------------------------------------------------------------------
    # Requirement Check: HTTP downloader
    # -------------------------------------------------------------------------
    HTTP_CLIENT=""
    if command -v curl >/dev/null 2>&1; then
        HTTP_CLIENT="curl"
    elif command -v wget >/dev/null 2>&1; then
        HTTP_CLIENT="wget"
    else
        log_error "Neither curl nor wget was found on your system. Please install one and re-run."
        exit 1
    fi

    download() {
        _url="$1"
        _dest="$2"
        if [ "$HTTP_CLIENT" = "curl" ]; then
            curl -fsSL "$_url" -o "$_dest"
        else
            wget -qO "$_dest" "$_url"
        fi
    }

    download_stdout() {
        _url="$1"
        if [ "$HTTP_CLIENT" = "curl" ]; then
            curl -fsSL "$_url"
        else
            wget -qO- "$_url"
        fi
    }

    # -------------------------------------------------------------------------
    # Step 1: Detect Operating System and Architecture
    # -------------------------------------------------------------------------
    log_step "Detecting platform and architecture..."

    OS_RAW="$(uname -s)"
    case "$OS_RAW" in
        Linux)  TARGET_OS="linux" ;;
        Darwin) TARGET_OS="darwin" ;;
        *)
            log_error "Unsupported operating system: ${OS_RAW}. (Supported: Linux, Darwin/macOS)"
            exit 1
            ;;
    esac

    ARCH_RAW="$(uname -m)"
    case "$ARCH_RAW" in
        x86_64|amd64) TARGET_ARCH="amd64" ;;
        arm64|aarch64) TARGET_ARCH="arm64" ;;
        *)
            log_error "Unsupported architecture: ${ARCH_RAW}. (Supported: x86_64/amd64, arm64/aarch64)"
            exit 1
            ;;
    esac

    log_ok "Detected platform: ${COLOR_BOLD}${TARGET_OS}/${TARGET_ARCH}${COLOR_RESET}"

    # -------------------------------------------------------------------------
    # Step 2: Resolve Release Version
    # -------------------------------------------------------------------------
    if [ -n "$TARGET_VERSION" ]; then
        RESOLVED_TAG="$TARGET_VERSION"
        log_ok "Using user-specified version: ${COLOR_BOLD}${RESOLVED_TAG}${COLOR_RESET}"
    else
        log_step "Resolving latest release from GitHub API..."
        API_URL="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
        
        # Try GitHub API first
        TAG_NAME=""
        API_RESPONSE="$(download_stdout "$API_URL" 2>/dev/null || true)"
        if [ -n "$API_RESPONSE" ]; then
            # Parse tag_name without jq for pure POSIX compatibility
            TAG_NAME="$(printf '%s\n' "$API_RESPONSE" | grep '"tag_name":' | head -n 1 | sed -E 's/.*"tag_name":[[:space:]]*"([^"]+)".*/\1/')"
        fi

        # Fallback to redirect resolution if API is rate-limited
        if [ -z "$TAG_NAME" ] && [ "$HTTP_CLIENT" = "curl" ]; then
            REDIRECT_URL="$(curl -fsSLI -o /dev/null -w "%{url_effective}" "https://github.com/${GITHUB_REPO}/releases/latest" 2>/dev/null || true)"
            TAG_NAME="$(basename "$REDIRECT_URL" 2>/dev/null || true)"
        fi

        if [ -z "$TAG_NAME" ] || [ "$TAG_NAME" = "latest" ]; then
            log_error "Failed to resolve latest version tag for ${GITHUB_REPO}."
            log_error "You can set VERSION=vX.Y.Z manually (e.g., VERSION=v1.0.0 curl ... | sh)."
            exit 1
        fi

        RESOLVED_TAG="$TAG_NAME"
        log_ok "Resolved latest version: ${COLOR_BOLD}${RESOLVED_TAG}${COLOR_RESET}"
    fi

    CLEAN_VERSION="${RESOLVED_TAG#v}"
    ARCHIVE_FILENAME="${BIN_NAME}_${CLEAN_VERSION}_${TARGET_OS}_${TARGET_ARCH}.tar.gz"
    ARCHIVE_URL="https://github.com/${GITHUB_REPO}/releases/download/${RESOLVED_TAG}/${ARCHIVE_FILENAME}"
    CHECKSUMS_URL="https://github.com/${GITHUB_REPO}/releases/download/${RESOLVED_TAG}/checksums.txt"

    # -------------------------------------------------------------------------
    # Step 3: Temporary workspace and cleanup trap
    # -------------------------------------------------------------------------
    TMP_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t 'zeroconflict-install.XXXXXX')"
    cleanup() {
        rm -rf "$TMP_DIR"
    }
    trap cleanup EXIT INT TERM

    # -------------------------------------------------------------------------
    # Step 4: Download Archive and Checksums
    # -------------------------------------------------------------------------
    log_step "Downloading ${ARCHIVE_FILENAME}..."
    ARCHIVE_PATH="${TMP_DIR}/${ARCHIVE_FILENAME}"
    if ! download "$ARCHIVE_URL" "$ARCHIVE_PATH"; then
        log_error "Failed to download archive from: ${ARCHIVE_URL}"
        exit 1
    fi
    log_ok "Downloaded release archive."

    log_step "Downloading checksums.txt..."
    CHECKSUMS_PATH="${TMP_DIR}/checksums.txt"
    if ! download "$CHECKSUMS_URL" "$CHECKSUMS_PATH"; then
        log_error "Failed to download checksums from: ${CHECKSUMS_URL}"
        exit 1
    fi
    log_ok "Downloaded checksums.txt."

    # -------------------------------------------------------------------------
    # Step 5: Verify SHA-256 Checksum
    # -------------------------------------------------------------------------
    log_step "Verifying SHA-256 checksum..."
    EXPECTED_HASH="$(grep "${ARCHIVE_FILENAME}" "$CHECKSUMS_PATH" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')"
    if [ -z "$EXPECTED_HASH" ]; then
        log_error "Archive ${ARCHIVE_FILENAME} not found in checksums.txt."
        exit 1
    fi

    ACTUAL_HASH=""
    if command -v sha256sum >/dev/null 2>&1; then
        ACTUAL_HASH="$(sha256sum "$ARCHIVE_PATH" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')"
    elif command -v shasum >/dev/null 2>&1; then
        ACTUAL_HASH="$(shasum -a 256 "$ARCHIVE_PATH" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')"
    else
        log_error "Neither sha256sum nor shasum was found to verify download integrity."
        exit 1
    fi

    if [ "$EXPECTED_HASH" != "$ACTUAL_HASH" ]; then
        log_error "Checksum verification failed!"
        log_error "  Expected: ${EXPECTED_HASH}"
        log_error "  Actual:   ${ACTUAL_HASH}"
        exit 1
    fi
    log_ok "SHA-256 checksum verified: ${COLOR_GREEN}${ACTUAL_HASH}${COLOR_RESET}"

    # -------------------------------------------------------------------------
    # Step 6: Extract & Determine Install Directory
    # -------------------------------------------------------------------------
    log_step "Extracting archive..."
    tar -xzf "$ARCHIVE_PATH" -C "$TMP_DIR"
    EXTRACTED_BIN="${TMP_DIR}/${BIN_NAME}"

    if [ ! -f "$EXTRACTED_BIN" ]; then
        log_error "Binary '${BIN_NAME}' was not found in the extracted archive."
        exit 1
    fi

    # Determine installation directory without invoking sudo:
    # 1. Prefer /usr/local/bin if writable
    # 2. Fallback to ~/.local/bin
    if [ -w "/usr/local/bin" ] || ( [ ! -d "/usr/local/bin" ] && [ -w "/usr/local" ] ); then
        INSTALL_DIR="/usr/local/bin"
    else
        INSTALL_DIR="${HOME}/.local/bin"
    fi

    mkdir -p "$INSTALL_DIR"
    cp -f "$EXTRACTED_BIN" "$INSTALL_DIR/$BIN_NAME"
    chmod 755 "$INSTALL_DIR/$BIN_NAME"
    log_ok "Installed binary to ${COLOR_BOLD}${INSTALL_DIR}/${BIN_NAME}${COLOR_RESET}"

    # -------------------------------------------------------------------------
    # Step 7: PATH Verification & Guidance
    # -------------------------------------------------------------------------
    IN_PATH=0
    case ":${PATH}:" in
        *":${INSTALL_DIR}:"*) IN_PATH=1 ;;
    esac

    echo ""
    log_info "${COLOR_GREEN}Installation successful!${COLOR_RESET}"
    echo ""

    if [ "$IN_PATH" -eq 1 ]; then
        log_ok "Your PATH already includes ${INSTALL_DIR}."
        printf "Run '${COLOR_BOLD}%s --version${COLOR_RESET}' to get started.\n" "$BIN_NAME"
    else
        log_warn "${INSTALL_DIR} is not currently in your PATH."
        echo ""
        printf "To make '${COLOR_BOLD}%s${COLOR_RESET}' available globally, add this directory to your shell configuration:\n\n" "$BIN_NAME"

        # Determine user's active shell
        CURRENT_SHELL="$(basename "${SHELL:-sh}")"
        case "$CURRENT_SHELL" in
            zsh)
                printf "  ${COLOR_CYAN}echo 'export PATH=\"%s:\$PATH\"' >> ~/.zshrc${COLOR_RESET}\n" "$INSTALL_DIR"
                printf "  ${COLOR_CYAN}source ~/.zshrc${COLOR_RESET}\n"
                ;;
            bash)
                printf "  ${COLOR_CYAN}echo 'export PATH=\"%s:\$PATH\"' >> ~/.bashrc${COLOR_RESET}\n" "$INSTALL_DIR"
                printf "  ${COLOR_CYAN}source ~/.bashrc${COLOR_RESET}\n"
                ;;
            *)
                printf "  ${COLOR_CYAN}echo 'export PATH=\"%s:\$PATH\"' >> ~/.profile${COLOR_RESET}\n" "$INSTALL_DIR"
                printf "  ${COLOR_CYAN}source ~/.profile${COLOR_RESET}\n"
                ;;
        esac
        echo ""
    fi
}

# Invoke main function with all arguments on the last line (stream-safe)
main "$@"
