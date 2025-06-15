#!/bin/bash

# Fixes: destructive operations, pipeline errors, permission handling, download verification

set -euo pipefail

SUDOCMD=""
WGETCMD="wget -qO-"
CURLCMD="curl -sL"

# FIX: Added cleanup for temporary files to prevent disk space issues
cleanup() {
    [[ -n "${TEMP_DIR:-}" ]] && [[ -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"
    [[ -n "${TEMP_FILE:-}" ]] && [[ -f "$TEMP_FILE" ]] && rm -f "$TEMP_FILE"
}
trap cleanup EXIT

# FIX: Improved error handling for Go detection
set +e
GOBIN=$(which go 2>/dev/null)
set -e

if [[ -z "$GOBIN" ]]; then
    echo "❌ Go not installed, nothing to update"
    exit 1
fi

GOROOT=$($GOBIN env GOROOT 2>/dev/null) || true
GOPATH=$($GOBIN env GOPATH 2>/dev/null) || true

if [[ -z "$GOROOT" ]]; then
    echo "❌ Couldn't find \$GOROOT environment variable"
    exit 1
fi

GOVERSION=$($GOBIN env GOVERSION 2>/dev/null) || true
GOVERSIONPRETTY=${GOVERSION#"go"}

if [[ -z "$GOVERSION" ]]; then
    echo "❌ Couldn't find \$GOVERSION environment variable"
    exit 1
fi

echo "✅ Found Go $GOVERSIONPRETTY installed at $GOROOT"

if [[ -z "$(which wget 2>/dev/null)" ]] && [[ -z "$(which curl 2>/dev/null)" ]]; then
    echo "❌ Unable to update go to latest version, please install wget or curl"
    exit 1
fi

echo "🌐 Checking for latest Go version..."

# FIX: Clean version detection with proper parsing to remove the extra timestamp
GOLATESTURL="https://go.dev/VERSION?m=text"
set +e
GOLATEST=$($WGETCMD "$GOLATESTURL" 2>/dev/null | head -n1 || $CURLCMD "$GOLATESTURL" 2>/dev/null | head -n1)
set -e
GOLATESTPRETTY=${GOLATEST#"go"}

# Validate we got a version
if [[ -z "$GOLATEST" ]]; then
    echo "❌ Couldn't fetch latest golang version"
    echo "   Please check your internet connection"
    exit 1
fi

# Check if update is needed
if [[ "$GOVERSION" == "$GOLATEST" ]]; then
    echo "👍 You already have the latest go with version $GOVERSIONPRETTY, no update required"
    exit 0
fi

echo "📋 Update available: Go $GOVERSIONPRETTY → Go $GOLATESTPRETTY"

# Detect GOROOT ownership for permission handling
case $(uname) in
    Linux)  GOROOTOWNER=$(stat -c "%U" $GOROOT 2>/dev/null) || true ;;
    Darwin) GOROOTOWNER=$(stat -f "%Su" $GOROOT 2>/dev/null) || true ;;
esac

if [[ -z "$GOROOTOWNER" ]]; then
    echo "❌ Couldn't find owner of the \$GOROOT directory"
    exit 1
fi

# FIX: Improved sudo handling with proper validation
if [[ "$USER" != "$GOROOTOWNER" ]]; then
    echo "🔥 Requires $GOROOTOWNER user access rights ..."

    if [[ "$GOROOTOWNER" == "root" ]]; then
        SUDOCMD="sudo"
    else
        SUDOCMD="sudo -u $GOROOTOWNER"
    fi
    
    # Test sudo access properly
    if ! $SUDOCMD true; then
        echo "❌ Cannot execute commands as $GOROOTOWNER"
        exit 1
    fi
    
    # Test write permissions to GOROOT
    if ! $SUDOCMD touch "$GOROOT/.test_write"; then
        echo "❌ Cannot write to $GOROOT even with sudo"
        exit 1
    fi
    $SUDOCMD rm -f "$GOROOT/.test_write"
fi

GOARCH=$($GOBIN env GOARCH 2>/dev/null) || true

if [[ -z "$GOARCH" ]]; then
    echo "❌ Couldn't find \$GOARCH environment variable"
    exit 1
fi

GOOS=$($GOBIN env GOOS 2>/dev/null) || true

if [[ -z "$GOOS" ]]; then
    echo "❌ Couldn't find \$GOOS environment variable"
    exit 1
fi

GOTARBALL="https://go.dev/dl/$GOLATEST.$GOOS-$GOARCH.tar.gz"

echo "📥 Downloading Go $GOLATESTPRETTY..."

# FIX: Safe download to temp location with progress bars
TEMP_DIR=$(mktemp -d)
TEMP_FILE=$(mktemp)

download_success=false
if command -v wget >/dev/null 2>&1; then
    echo "Using wget to download..."
    if wget --progress=bar:force -O "$TEMP_FILE" "$GOTARBALL" 2>&1; then
        download_success=true
    fi
elif command -v curl >/dev/null 2>&1; then
    echo "Using curl to download..."
    if curl --progress-bar -L -o "$TEMP_FILE" "$GOTARBALL"; then
        download_success=true
    fi
fi

if [[ "$download_success" != "true" ]]; then
    echo "❌ Failed to download Go $GOLATESTPRETTY"
    exit 1
fi

echo "✅ Download completed successfully!"

echo "📦 Extracting and verifying Go $GOLATESTPRETTY..."

# FIX: Extract to temp and verify before installing
if ! tar -xzf "$TEMP_FILE" -C "$TEMP_DIR"; then
    echo "❌ Failed to extract Go tarball"
    exit 1
fi

# Verify the extracted Go installation works
if ! "$TEMP_DIR/go/bin/go" version >/dev/null 2>&1; then
    echo "❌ Downloaded Go installation is not working"
    exit 1
fi

echo "🔄 Installing Go $GOLATESTPRETTY..."

# FIX: Atomic replacement with rollback capability
if [[ -d "$GOROOT" ]]; then
    OLD_GOROOT="${GOROOT}.old.$$"
    $SUDOCMD mv "$GOROOT" "$OLD_GOROOT"
else
    OLD_GOROOT=""
fi

if $SUDOCMD mv "$TEMP_DIR/go" "$GOROOT"; then
    # Verify new installation works in its final location
    if "$GOROOT/bin/go" version >/dev/null 2>&1; then
        [[ -n "$OLD_GOROOT" ]] && $SUDOCMD rm -rf "$OLD_GOROOT"
        echo "✅ Go successfully upgraded from version $GOVERSIONPRETTY to version $GOLATESTPRETTY"
    else
        # Rollback on verification failure
        echo "❌ New Go installation failed verification, rolling back..."
        $SUDOCMD rm -rf "$GOROOT"
        [[ -n "$OLD_GOROOT" ]] && $SUDOCMD mv "$OLD_GOROOT" "$GOROOT"
        echo "❌ Rollback completed, Go $GOVERSIONPRETTY restored"
        exit 1
    fi
else
    # Restore old installation if move failed
    echo "❌ Failed to install new Go version, restoring previous installation..."
    [[ -n "$OLD_GOROOT" ]] && $SUDOCMD mv "$OLD_GOROOT" "$GOROOT"
    exit 1
fi
