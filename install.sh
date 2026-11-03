#!/bin/bash
# Installs or updates the omni CLI: builds it from source and links it onto
# PATH. Safe to run again; that's how you update.
#
#   From a checkout:   ./install.sh
#   From nowhere:      curl -fsSL https://raw.githubusercontent.com/heapwolf/omni/master/install.sh | bash
#
# From a checkout, it builds that checkout: apps that depend on omni by path
# (../omni) then get a CLI that matches the library they compile against.
# Otherwise it clones to ~/.omni/src/omni (or $OMNI_DIR).
#
# Afterwards, `omni doctor -p <platform> --fix` sets up the rest.
set -euo pipefail

REPO_URL="${OMNI_REPO:-https://github.com/heapwolf/omni.git}"
BIN_DIR="$HOME/.omni/bin"

say()  { printf '\033[90m●\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '\033[31m🅧\033[0m %s\n' "$*" >&2; exit 1; }

# Prompts read the terminal even when the script itself arrives on stdin
# through `curl | bash`.
ask() {
  local answer=""
  if [ -r /dev/tty ]; then
    printf '  %s [Y/n]: ' "$1" > /dev/tty
    read -r answer < /dev/tty || answer="n"
  else
    answer="n"
  fi
  case "$answer" in ""|y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

# 1. Apple's Command Line Tools: git and swift come with them.
if [ "$(uname -s)" = "Darwin" ]; then
  if ! xcode-select -p >/dev/null 2>&1 || ! xcrun --find swift >/dev/null 2>&1; then
    say "Apple's Command Line Tools aren't installed; git and Swift come with them"
    ask "Install them now (a window opens; about 1GB)?" \
      || fail "omni needs them. Install with: xcode-select --install"
    xcode-select --install >/dev/null 2>&1 || true
    say "finish the installer window that just opened; this continues when it's done"
    until xcode-select -p >/dev/null 2>&1 && xcrun --find swift >/dev/null 2>&1; do sleep 5; done
    ok "Command Line Tools installed"
  fi
fi
command -v git   >/dev/null || fail "git isn't installed"
command -v swift >/dev/null || fail "Swift isn't installed; see https://www.swift.org/install/"

# 2. The source: this checkout, $OMNI_DIR, or a clone.
script_dir=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
if [ -n "${OMNI_DIR:-}" ]; then
  src="$OMNI_DIR"
elif [ -n "$script_dir" ] && [ -f "$script_dir/Package.swift" ] && [ -d "$script_dir/src/cli" ]; then
  src="$script_dir"
else
  src="$HOME/.omni/src/omni"
fi

if [ ! -d "$src/.git" ]; then
  say "downloading omni into $src"
  mkdir -p "$(dirname "$src")"
  git clone --quiet "$REPO_URL" "$src"
fi
cd "$src"

# 3. Update, unless that would touch someone's work. A checkout with local
#    changes, or on a branch with no upstream, builds as it is.
before="$(git rev-parse --short HEAD 2>/dev/null || echo none)"
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  say "local changes in $src; building them as they are, without pulling"
elif ! git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
  say "$(git rev-parse --abbrev-ref HEAD) has no upstream; building it as it is"
else
  say "checking for updates"
  if git pull --ff-only --quiet; then
    after="$(git rev-parse --short HEAD)"
    [ "$before" = "$after" ] && say "already up to date ($after)" || say "updated $before → $after"
  else
    say "couldn't fast-forward (offline, or the branch has diverged); building $before"
  fi
fi

# 4. Build.
if [ -d .build ]; then say "building omni"; else say "building omni (the first build takes a few minutes)"; fi
if ! build_log="$(swift build -c release --product omni 2>&1)"; then
  printf '%s\n' "$build_log" | tail -30 >&2
  fail "swift build failed (above). omni needs Swift 6.0 or newer: $(swift --version 2>&1 | head -1)"
fi
binary="$(swift build -c release --product omni --show-bin-path)/omni"
[ -x "$binary" ] || fail "built, but no binary at $binary"

# 5. Link. ~/.omni/bin goes first on PATH, so a copy someone put in
#    /usr/local/bin by hand (as the README once said to) can't win.
mkdir -p "$BIN_DIR"
ln -sfn "$binary" "$BIN_DIR/omni"

stale="$(command -v omni 2>/dev/null || true)"
if [ -n "$stale" ] && [ "$stale" != "$BIN_DIR/omni" ] && [ "$(readlink "$stale" 2>/dev/null || true)" != "$binary" ]; then
  say "an older omni is at $stale"
  if [ -w "$(dirname "$stale")" ]; then
    ln -sfn "$binary" "$stale" && say "pointed it at this build"
  elif ask "Point $stale at this build (asks for your Mac password)?"; then
    sudo ln -sfn "$binary" "$stale" && say "pointed it at this build"
  fi
fi

line='export PATH="$HOME/.omni/bin:$PATH"'
case "$(basename "${SHELL:-zsh}")" in
  bash) profile="$HOME/.bash_profile" ;;
  *)    profile="$HOME/.zprofile" ;;
esac
on_path=0
case ":$PATH:" in *":$BIN_DIR:"*) on_path=1 ;; esac
if ! grep -qs '.omni/bin' "$profile"; then
  printf '\n# omni\n%s\n' "$line" >> "$profile"
  say "added ~/.omni/bin to PATH in $profile"
fi

ok "omni $(git rev-parse --short HEAD) installed at $BIN_DIR/omni"
if [ "$on_path" = 0 ]; then
  echo "  Open a new terminal window, or run:  $line"
fi
echo "  Next: omni doctor -p android --fix   (or ios, ios-simulator, macos)"
echo "  Update later with: omni update"
