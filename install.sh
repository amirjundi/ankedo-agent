#!/usr/bin/env bash
#
# AnkEdo — install on Linux or macOS.
#
#   curl -fsSL https://raw.githubusercontent.com/amirjundi/ankedo-agent/master/install.sh | bash
#
# Installs OpenClaw from npm, builds this plugin, registers it, and puts an `ankedo`
# command on PATH.
#
# On the `ankedo` command: it is a wrapper that execs `openclaw`, not a rename. The
# real binary has to keep its name — OpenClaw spawns `openclaw` as a subprocess in
# several places (the ACP client, the native hook relay, tool descriptors), and
# renaming it would break those at the moment they are used rather than at install.
# You get the name you type; the code keeps the name it expects.

set -euo pipefail

BOLD=$'\033[1m'; DIM=$'\033[2m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; NC=$'\033[0m'
step() { printf '\n%s► %s%s\n' "$BOLD" "$1" "$NC"; }
ok()   { printf '  %s✓%s %s\n' "$GREEN" "$NC" "$1"; }
warn() { printf '  %s⚠%s %s\n' "$YELLOW" "$NC" "$1"; }
die()  { printf '  %s✗%s %s\n' "$RED" "$NC" "$1"; exit 1; }

REPO="https://github.com/amirjundi/ankedo-agent.git"
DIR="${ANKEDO_DIR:-$HOME/ankedo-agent}"

printf '\n%s  AnkEdo — hate-speech monitoring agent%s\n' "$BOLD" "$NC"

# ── Node ────────────────────────────────────────────────────────────────────
step "Checking Node"
command -v node >/dev/null 2>&1 || die "Node is not installed. OpenClaw needs >=22.22.3, >=24.15, or >=25.9."

NODE_VERSION="$(node --version | sed 's/^v//')"
# OpenClaw's engines field is a disjunction, not a floor: 23.x and 25.0-25.8 are
# excluded even though they are numerically higher than 22.22.3.
node -e '
const [maj, min, pat] = process.versions.node.split(".").map(Number);
const ge = (a, b, c) => maj > a || (maj === a && (min > b || (min === b && pat >= c)));
const ok = (maj === 22 && ge(22, 22, 3)) || (maj === 24 && ge(24, 15, 0)) || ge(25, 9, 0);
process.exit(ok ? 0 : 1);
' || die "Node $NODE_VERSION is not supported. Need >=22.22.3 <23, >=24.15 <25, or >=25.9.
      nvm:  nvm install 24 && nvm use 24
      apt:  curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash - && sudo apt install -y nodejs"
ok "Node $NODE_VERSION"

# ── OpenClaw ────────────────────────────────────────────────────────────────
step "Installing OpenClaw"
if command -v openclaw >/dev/null 2>&1; then
  ok "already installed ($(openclaw --version 2>/dev/null | head -1))"
else
  npm install -g openclaw || die "npm install -g openclaw failed. Try with sudo, or set a user prefix:
      npm config set prefix ~/.npm-global && export PATH=~/.npm-global/bin:\$PATH"
  ok "OpenClaw installed"
fi

# ── This plugin ─────────────────────────────────────────────────────────────
step "Fetching AnkEdo"
if [ -d "$DIR/.git" ]; then
  git -C "$DIR" pull --ff-only 2>&1 | tail -1
  ok "updated $DIR"
else
  git clone "$REPO" "$DIR" 2>&1 | tail -1
  ok "cloned to $DIR"
fi

step "Building"
cd "$DIR"
npm install --silent 2>&1 | tail -2 || die "npm install failed in $DIR"
npm run build --silent 2>&1 | tail -3 || die "build failed"
ok "built"

# ── Register ────────────────────────────────────────────────────────────────
step "Registering the plugin"
openclaw config set plugins.load.paths "[\"$DIR\"]" >/dev/null 2>&1 \
  || warn "could not set plugins.load.paths — run it by hand"
openclaw plugins enable ankedo >/dev/null 2>&1 || warn "could not enable — run: openclaw plugins enable ankedo"
ok "registered"

# ── The persona ─────────────────────────────────────────────────────────────
# This is what makes it a monitor rather than a general assistant, so it is part of
# installing rather than a later step someone forgets.
step "Installing the persona"
WORKSPACE="${OPENCLAW_WORKSPACE:-$HOME/.openclaw/workspace}"
mkdir -p "$WORKSPACE"
for f in SOUL.md AGENTS.md; do
  if [ -f "$WORKSPACE/$f" ] && ! cmp -s "workspace/$f" "$WORKSPACE/$f"; then
    cp "workspace/$f" "$WORKSPACE/$f.ankedo-new"
    warn "$f differs — yours kept, new one at $f.ankedo-new"
  else
    cp "workspace/$f" "$WORKSPACE/$f"
  fi
done
ok "persona in $WORKSPACE"

# ── The ankedo command ──────────────────────────────────────────────────────
step "Linking the ankedo command"
WRAPPER='#!/usr/bin/env bash
# AnkEdo. A wrapper, not a rename: OpenClaw spawns `openclaw` as a subprocess in
# several places, so the real binary keeps its name.
exec openclaw "$@"'

# sudo -n, never plain sudo: run as `curl ... | bash` the script *is* stdin, so a
# password prompt has no terminal to read from. It would hang, or fail at the very
# last step of an otherwise finished install. If sudo would need a password we use
# ~/.local/bin instead, which needs no privileges at all.
if [ -w /usr/local/bin ] 2>/dev/null; then
  printf '%s\n' "$WRAPPER" > /usr/local/bin/ankedo && chmod +x /usr/local/bin/ankedo
  ok "/usr/local/bin/ankedo"
elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null &&
     printf '%s\n' "$WRAPPER" | sudo -n tee /usr/local/bin/ankedo >/dev/null &&
     sudo -n chmod +x /usr/local/bin/ankedo; then
  ok "/usr/local/bin/ankedo"
else
  mkdir -p "$HOME/.local/bin"
  printf '%s\n' "$WRAPPER" > "$HOME/.local/bin/ankedo" && chmod +x "$HOME/.local/bin/ankedo"
  ok "$HOME/.local/bin/ankedo"
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) warn "add to your shell profile:  export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
  esac
fi

# ── Browser, optional ───────────────────────────────────────────────────────
step "Checking the browser"
if node -e "require.resolve('camoufox')" >/dev/null 2>&1; then
  ok "Camoufox present"
else
  warn "Camoufox not installed — classification works, collection does not."
  printf '  %sTo enable collection:%s\n' "$DIM" "$NC"
  printf '  %s  cd %s && npm install camoufox && npx camoufox fetch%s\n' "$DIM" "$DIR" "$NC"
  printf '  %s  ankedo config set plugins.entries.browser.enabled false%s\n' "$DIM" "$NC"
  printf '  %s(OpenClaw'"'"'s own browser drives Chromium over CDP with no anti-detection,%s\n' "$DIM" "$NC"
  printf '  %s which is what gets worker accounts banned. Camoufox replaces it.)%s\n' "$DIM" "$NC"
fi

# ── Done ────────────────────────────────────────────────────────────────────
cat <<EOF

$BOLD  Installed.$NC

  Point it at the platform:

    ${DIM}ankedo config set plugins.entries.ankedo.config.platformUrl https://ettok.net/api/hermes/
    ankedo config set plugins.entries.ankedo.config.agentKey <key with the hate_speech_scan scope>
    ankedo config set plugins.entries.ankedo.config.agentId ankedo-\$(hostname)
    ankedo config set plugins.entries.ankedo.config.databasePath \$HOME/.ankedo/evidence.db$NC

  ${DIM}agentId is not optional in practice: the platform scopes idempotency on
  (agent_id, key), so two machines omitting it share a namespace and one
  silently replays the other's response.$NC

  Then:

    ${DIM}ankedo onboard          configure a model provider
    ankedo gateway run      start the agent and its dashboard
    ankedo plugins list     confirm AnkEdo is enabled$NC

EOF
