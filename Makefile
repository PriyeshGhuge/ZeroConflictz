# ==============================================================================
# ZeroConflict CLI - Cross-Platform Build & Release Makefile
# ==============================================================================

BIN_NAME       ?= zeroconflict
MODULE         ?= github.com/ZeroConflictz/cli
VERSION        ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo "v0.1.0-dev")
GIT_COMMIT     ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo "none")
BUILD_DATE     ?= $(shell date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "unknown")

# Go build flags
LDFLAGS        := -s -w \
                  -X 'main.version=$(VERSION)' \
                  -X 'main.commit=$(GIT_COMMIT)' \
                  -X 'main.date=$(BUILD_DATE)'

DIST_DIR       := dist
BUILD_DIR      := build

# Target architectures:
# Linux:   x86_64 (amd64), arm64
# macOS:   x86_64 (amd64), arm64 (Apple Silicon)
# Windows: x86_64 (amd64), arm64
TARGETS := \
	linux/amd64/tar.gz \
	linux/arm64/tar.gz \
	darwin/amd64/tar.gz \
	darwin/arm64/tar.gz \
	windows/amd64/zip \
	windows/arm64/zip

.PHONY: all build build-all clean checksums test help

all: build

help: ## Show Makefile targets
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  build        Build binary for current host platform"
	@echo "  build-all    Cross-compile binaries and create archives for all supported platforms"
	@echo "  checksums    Generate SHA-256 checksums (dist/checksums.txt)"
	@echo "  clean        Remove build artifacts and temporary files"
	@echo "  test         Run unit tests"

## -----------------------------------------------------------------------------
## Local Build
## -----------------------------------------------------------------------------
build: ## Build binary for current platform
	@echo "==> Building $(BIN_NAME) ($(VERSION))..."
	@mkdir -p $(BUILD_DIR)
	CGO_ENABLED=0 go build -trimpath -ldflags "$(LDFLAGS)" -o $(BUILD_DIR)/$(BIN_NAME) .
	@echo "==> Built: $(BUILD_DIR)/$(BIN_NAME)"

## -----------------------------------------------------------------------------
## Cross-Compilation Matrix
## -----------------------------------------------------------------------------
build-all: clean ## Cross-compile for all 6 target platforms and package
	@echo "==> Cross-compiling $(BIN_NAME) $(VERSION) across all platforms..."
	@mkdir -p $(DIST_DIR)
	@$(MAKE) $(TARGETS)
	@$(MAKE) checksums
	@echo "==> All artifacts generated in $(DIST_DIR)/"

# Pattern rule for packaging tar.gz (Linux, macOS)
%/tar.gz:
	@target="$*"; \
	os=$$(echo "$$target" | cut -d'/' -f1); \
	arch=$$(echo "$$target" | cut -d'/' -f2); \
	archive_name="$(BIN_NAME)_$$(echo $(VERSION) | sed 's/^v//')_$${os}_$${arch}.tar.gz"; \
	work_dir="$$(mktemp -d)"; \
	echo "  -> Building $${os}/$${arch} ($$archive_name)..."; \
	GOOS=$$os GOARCH=$$arch CGO_ENABLED=0 go build -trimpath -ldflags "$(LDFLAGS)" -o "$$work_dir/$(BIN_NAME)" . || exit 1; \
	[ -f LICENSE ] && cp LICENSE "$$work_dir/" || true; \
	[ -f README.md ] && cp README.md "$$work_dir/" || true; \
	tar -czf "$(DIST_DIR)/$$archive_name" -C "$$work_dir" .; \
	rm -rf "$$work_dir"; \
	echo "  [ok] Created $(DIST_DIR)/$$archive_name"

# Pattern rule for packaging zip (Windows)
%/zip:
	@target="$*"; \
	os=$$(echo "$$target" | cut -d'/' -f1); \
	arch=$$(echo "$$target" | cut -d'/' -f2); \
	archive_name="$(BIN_NAME)_$$(echo $(VERSION) | sed 's/^v//')_$${os}_$${arch}.zip"; \
	work_dir="$$(mktemp -d)"; \
	echo "  -> Building $${os}/$${arch} ($$archive_name)..."; \
	GOOS=$$os GOARCH=$$arch CGO_ENABLED=0 go build -trimpath -ldflags "$(LDFLAGS)" -o "$$work_dir/$(BIN_NAME).exe" . || exit 1; \
	[ -f LICENSE ] && cp LICENSE "$$work_dir/" || true; \
	[ -f README.md ] && cp README.md "$$work_dir/" || true; \
	(cd "$$work_dir" && zip -q -r - .) > "$(DIST_DIR)/$$archive_name" 2>/dev/null || \
	(cd "$$work_dir" && tar -a -cf "$(CURDIR)/$(DIST_DIR)/$$archive_name" *) 2>/dev/null || \
	(powershell -Command "Compress-Archive -Path '$$work_dir\*' -DestinationPath '$(DIST_DIR)/$$archive_name' -Force") 2>/dev/null; \
	rm -rf "$$work_dir"; \
	echo "  [ok] Created $(DIST_DIR)/$$archive_name"

## -----------------------------------------------------------------------------
## Checksums
## -----------------------------------------------------------------------------
checksums: ## Generate SHA-256 checksums for all distribution archives
	@echo "==> Generating SHA-256 checksums..."
	@cd $(DIST_DIR) && ( \
		if command -v sha256sum >/dev/null 2>&1; then \
			sha256sum *.tar.gz *.zip > checksums.txt 2>/dev/null || true; \
		elif command -v shasum >/dev/null 2>&1; then \
			shasum -a 256 *.tar.gz *.zip > checksums.txt 2>/dev/null || true; \
		fi \
	)
	@echo "==> Checksums written to $(DIST_DIR)/checksums.txt"
	@cat $(DIST_DIR)/checksums.txt 2>/dev/null || true

## -----------------------------------------------------------------------------
## Testing & Cleanup
## -----------------------------------------------------------------------------
test: ## Run unit tests
	go test -v -race ./...

clean: ## Clean build and dist directories
	@rm -rf $(BUILD_DIR) $(DIST_DIR)
	@echo "==> Cleaned build and dist directories."
