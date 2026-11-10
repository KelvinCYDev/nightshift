#!/usr/bin/env bash
# nightshift installer — one command per machine. Idempotent; safe to re-run.
#
#   ./install.sh                 install the DISPATCH side on this machine
#                                (roster placeholders from .env.example — edit
#                                NIGHTSHIFT_TARGETS/_HOST to your real aliases)
#   ./install.sh --push <host> rsync the repo onto an always-on box AND
#                                install the SERVER side there: roster = one
#                                target 'self' → localhost, self-authorized
#                                SSH key (so the supervisor supervises its own
#                                gateway), PATH line, skill symlink.
#                                Run once per box:  ./install.sh --push home
#
# Root of everything: ~/.nightshift/ (config, bin symlink, run log,
# ControlMaster sockets, landed/, run-summaries/). Nothing installs
# anywhere else. An existing .env is never overwritten — your edits win.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HOME/.nightshift"
PATH_LINE='export PATH="$HOME/.nightshift/bin:$PATH"'

ensure_root() {
  mkdir -p "$ROOT/bin"
  ln -sfn "$HERE/bin/nightshift" "$ROOT/bin/nightshift"
}

ensure_env() { # $1=dispatch|server
  [ -f "$ROOT/.env" ] && return 0
  if [ "$1" = server ]; then
    # server roster: one target 'self' reaching its own gateway via loopback
    {
      echo '# nightshift config (created by install.sh — server side)'
      echo 'NIGHTSHIFT_TARGETS="self"'
      echo 'NIGHTSHIFT_DEFAULT_TARGET="self"'
      echo 'NIGHTSHIFT_SELF_HOST="localhost"'
    } > "$ROOT/.env"
  else
    cp "$HERE/.env.example" "$ROOT/.env"
  fi
  return 1
}

ensure_shell_path() {
  local rc
  for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    [ -f "$rc" ] || continue
    grep -qF '.nightshift/bin' "$rc" || printf '\n# nightshift\n%s\n' "$PATH_LINE" >> "$rc"
  done
}

ensure_skill() {
  mkdir -p "$HOME/.hermes/skills"
  ln -sfn "$HERE/skill" "$HOME/.hermes/skills/nightshift"
}

ensure_self_key() { # server: key-auth to localhost so ssh -L self-tunnels work
  local key="$HOME/.ssh/id_ed25519"
  mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
  [ -f "$key" ] || ssh-keygen -q -t ed25519 -N '' -f "$key"
  # derive the public key from the ACTUAL private key (a stale/mismatched
  # .pub on disk is a real failure mode — authorize what ssh will offer)
  local pub
  pub="$(ssh-keygen -y -f "$key" 2>/dev/null)" || pub="$(cat "$key.pub" 2>/dev/null)"
  [ -n "$pub" ] || { echo "could not derive self key" >&2; return 1; }
  touch "$HOME/.ssh/authorized_keys"
  grep -qxF "$pub" "$HOME/.ssh/authorized_keys" \
    || printf '%s\n' "$pub" >> "$HOME/.ssh/authorized_keys"
  chmod 600 "$HOME/.ssh/authorized_keys"
  # seed localhost host keys so BatchMode ssh doesn't die on first connect
  for h in localhost 127.0.0.1; do
    grep -q "^$h " "$HOME/.ssh/known_hosts" 2>/dev/null \
      || ssh-keyscan -T 5 "$h" >> "$HOME/.ssh/known_hosts" 2>/dev/null
  done
}

install_dispatch() {
  ensure_root
  local fresh=0; ensure_env dispatch || fresh=1
  ensure_shell_path
  ensure_skill
  echo "nightshift dispatch side installed under $ROOT/"
  if [ "$fresh" = 1 ]; then
    echo "  NOTE  edit $ROOT/.env: NIGHTSHIFT_TARGETS + _HOST aliases → then: nightshift --doctor"
  fi
}

install_server() {
  ensure_root
  ensure_env server || true
  ensure_self_key
  ensure_shell_path
  ensure_skill
  echo "nightshift server side installed: roster [self → localhost], ssh key self-authorized"
  echo "  verify:     nightshift --doctor"
  echo "  overnight:  nightshift supervise phase1.md phase2.md --stop 08:30"
}

case "${1:-}" in
  --push)
    host="${2:-}"
    [ -n "$host" ] || { echo "usage: ./install.sh --push <ssh-host>" >&2; exit 1; }
    echo "==> rsync repo -> $host:~/nightshift"
    rsync -a --delete --exclude '.git' --exclude '.DS_Store' "$HERE/" "$host:nightshift/"
    echo "==> install server side on $host"
    ssh "$host" 'bash ~/nightshift/install.sh --server'
    ;;
  --server)
    install_server
    ;;
  "")
    install_dispatch
    ;;
  *)
    echo "usage: ./install.sh [--push <ssh-host>]" >&2
    exit 1
    ;;
esac
