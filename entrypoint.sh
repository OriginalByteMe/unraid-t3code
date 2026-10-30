#!/bin/bash
# Starts as root, so Unraid's "Use Tailscale" hook can run before it, then
# drops to the t3code account for everything else.
set -euo pipefail

export USER=t3code LOGNAME=t3code
log() { echo "[unraid-t3code] $*"; }
# Numeric ids: setpriv resolves --regid names as group names, and t3code's
# group is "users" or whatever PGID points at.
drop=(setpriv --reuid="$PUID" --regid="$PGID" --init-groups)
as_t3() { "${drop[@]}" "$@"; }
# The image's own build, not a `t3 update` copy in the Data folder, so the
# container's version is the image's.
t3=/opt/t3code/t3

# Files in appdata get the owner Unraid expects (99:100 unless PUID/PGID say otherwise).
if [ "$(id -u t3code):$(id -g t3code)" != "$PUID:$PGID" ]; then
  getent group "$PGID" >/dev/null || groupadd -g "$PGID" t3code
  usermod -o -u "$PUID" -g "$PGID" t3code
fi
chown t3code "$HOME"
# Docker creates a missing Projects folder as root; an existing share that the
# agents can already write keeps its owner.
as_t3 test -w /projects || chown t3code /projects

# Mapped Docker or libvirt sockets: join whatever group owns them.
for sock in /var/run/docker.sock /var/run/libvirt/libvirt-sock; do
  [ -S "$sock" ] || continue
  gid=$(stat -c %g "$sock")
  getent group "$gid" >/dev/null || groupadd -g "$gid" "sock$gid"
  usermod -aG "$gid" t3code
  if as_t3 test -w "$sock"; then
    log "agents can use $sock (root-equivalent on this server)"
  else
    log "WARNING: $sock is mapped but not writable for its group; agents cannot use it"
  fi
done

# SHELL: bash, zsh or fish, for T3's terminals and the console.
shell=$(command -v "${SHELL:-bash}" || true)
if ! grep -qxF -- "$shell" /etc/shells; then
  log "WARNING: SHELL=${SHELL:-} is not an installed shell; using bash"
  shell=/bin/bash
fi
usermod -s "$shell" t3code >/dev/null # prints "no changes" on every restart
export SHELL=$shell

# OH_MY_ZSH=true: Oh My Zsh in the Data folder, installed once the way its own
# installer does it, keeping any existing ~/.zshrc as ~/.zshrc.pre-oh-my-zsh.
if [ "${OH_MY_ZSH:-false}" = true ] && [ ! -d "$HOME/.oh-my-zsh" ]; then
  if as_t3 git clone --quiet --depth 1 https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh"; then
    [ ! -s "$HOME/.zshrc" ] || as_t3 mv "$HOME/.zshrc" "$HOME/.zshrc.pre-oh-my-zsh"
    as_t3 cp "$HOME/.oh-my-zsh/templates/zshrc.zsh-template" "$HOME/.zshrc"
    log "installed Oh My Zsh"
  else
    log "WARNING: could not install Oh My Zsh"
  fi
fi
# Without a ~/.zshrc, zsh opens its first-run questionnaire in every terminal.
case $shell in */zsh) [ -e "$HOME/.zshrc" ] || as_t3 touch "$HOME/.zshrc" ;; esac

if [ -n "${GH_TOKEN:-}" ]; then
  as_t3 gh auth setup-git || log "WARNING: gh auth setup-git failed; git will not use GH_TOKEN"
fi
[ -z "${GIT_USER_NAME:-}" ] || as_t3 git config --global user.name "$GIT_USER_NAME"
[ -z "${GIT_USER_EMAIL:-}" ] || as_t3 git config --global user.email "$GIT_USER_EMAIL"

# GIT_REPOS: owner/name (GitHub) or full clone URLs, cloned once into /projects.
repo_dirs=()
for repo in ${GIT_REPOS:-}; do
  case "$repo" in
    *://* | git@*) url=$repo ;;
    *) url="https://github.com/$repo.git" ;;
  esac
  dir="/projects/$(basename "$repo" .git)"
  if [ -d "$dir/.git" ] || as_t3 git clone --quiet "$url" "$dir"; then
    repo_dirs+=("$dir")
  else
    log "WARNING: could not clone $repo"
  fi
done

# AGENTS: agent CLIs, installed once into ~/.local so they persist and update
# themselves. The names map T3 Code's providers that publish an official npm
# package, plus Gemini (an ACP agent) and omp; any other word is taken as an
# npm package name.
declare -A npm_name=(
  [claude]=@anthropic-ai/claude-code [codex]=@openai/codex [gemini]=@google/gemini-cli
  [omp]=@oh-my-pi/pi-coding-agent [opencode]=opencode-ai [pi]=@earendil-works/pi-coding-agent
)
agents=${AGENTS:-}
for name in ${agents//,/ }; do
  name=${name,,}
  pkg=${npm_name[$name]:-$name}
  [ -d "$HOME/.local/lib/node_modules/$pkg" ] || as_t3 npm install --global --silent "$pkg" \
    || log "WARNING: could not install $name ($pkg)"
done

# `docker run <image> <command>` runs that command as t3code instead of the server.
[ $# -eq 0 ] || exec "${drop[@]}" "$@"

# Add the cloned repos to T3's project list. This works before the server
# starts; a repo that is already a project fails with ProjectAlreadyExistsError.
for dir in "${repo_dirs[@]}"; do
  if out=$(as_t3 "$t3" project add "$dir" 2>&1); then
    log "added $dir to T3 Code"
  elif ! grep -q ProjectAlreadyExistsError <<<"$out"; then
    log "WARNING: could not add $dir to T3 Code: $(grep -m 1 ERROR <<<"$out" || tail -n 1 <<<"$out")"
  fi
done

log "starting t3 serve on port 3773; pair with the Token below (see the README)"
exec "${drop[@]}" "$t3" serve --host 0.0.0.0 --port 3773 /projects
