#!/usr/bin/env bash
# Install the claude-brain skills for this OS into ~/.claude/skills.
#
#   ./install.sh                     detect your OS, install
#   ./install.sh --brain-dir ~/kb    put the brain somewhere other than ~/claude-brain
#   ./install.sh --yes               no prompts (replaces existing skills, keeping a backup)
#   ./install.sh --dry-run           show what would happen, change nothing
#   ./install.sh --os linux          force a platform (macos | linux | windows); auto-detected otherwise
#
# Works in macOS and Linux shells and in Git Bash on Windows (PowerShell users: install.ps1).
#
# Placeholders filled in each SKILL.md:
#   {{BRAIN_ABS}}  absolute path of the brain directory
#   ~/claude-brain rewritten only when --brain-dir is given
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_ROOT="$REPO/skills"
SRC=""
OS=""
DEST="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
SKILLS=(claude-brain-builder brain-architect brain-recall brain-transcriber)
DEFAULT_BRAIN="$HOME/claude-brain"

BRAIN="$DEFAULT_BRAIN"
ASSUME_YES=0
DRY_RUN=0
WORK=""

die() { echo "install: $*" >&2; exit 1; }

usage() { awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; exit "${1:-0}"; }

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --brain-dir) [ $# -ge 2 ] || die "--brain-dir needs a value"; BRAIN="$2"; shift 2 ;;
      --yes|-y)    ASSUME_YES=1; shift ;;
      --dry-run)   DRY_RUN=1; shift ;;
      --os)        [ $# -ge 2 ] || die "--os needs a value"; OS="$2"; shift 2 ;;
      --help|-h)   usage 0 ;;
      *)           echo "install: unknown option $1" >&2; usage 1 ;;
    esac
  done
}

detect_os() {
  case "$(uname -s)" in
    Darwin)               echo macos ;;
    Linux)                echo linux ;;
    MINGW*|MSYS*|CYGWIN*) echo windows ;;
    *)                    die "unsupported platform $(uname -s); pass --os macos|linux|windows" ;;
  esac
}

# Path the brain's Python scripts and the hook will see (C:/Users/... on Windows).
native_path() {
  if [ "$OS" = "windows" ] && command -v cygpath >/dev/null 2>&1; then
    cygpath -m "$1"
  else
    echo "$1"
  fi
}

confirm() {
  [ "$ASSUME_YES" -eq 1 ] && return 0
  [ -t 0 ] || die "not interactive; rerun with --yes"
  local reply
  read -r -p "$1 [y/N] " reply
  case "$reply" in [yY]*) return 0 ;; *) return 1 ;; esac
}

resolve_inputs() {
  case "$BRAIN" in "~"|"~/"*) BRAIN="$HOME${BRAIN#\~}" ;; esac
  case "$BRAIN" in /*) ;; *) BRAIN="$PWD/$BRAIN" ;; esac
  BRAIN="${BRAIN%/}"
  case "$BRAIN" in *[\|\&\\]*) die "brain dir may not contain | & or \\" ;; esac
}

# Brain path as written in the skills: ~/… when under $HOME.
brain_display() {
  case "$BRAIN" in "$HOME"/*) echo "~${BRAIN#"$HOME"}" ;; *) echo "$BRAIN" ;; esac
}

render() {
  local src="$1" out="$2" shown
  shown="$(brain_display)"
  sed -e "s|{{BRAIN_ABS}}|$(native_path "$BRAIN")|g" \
      -e "s|~/claude-brain|$shown|g" "$src" > "$out"
  if grep -q '{{[A-Z_]*}}' "$out"; then
    die "unfilled placeholder left in $out"
  fi
}

install_skill() {
  local skill="$1" target="$DEST/$1"
  [ -f "$SRC/$skill/SKILL.md" ] || die "missing $SRC/$skill/SKILL.md"
  rm -rf "${WORK:?}/$skill"
  cp -R "$SRC/$skill" "$WORK/$skill"
  render "$SRC/$skill/SKILL.md" "$WORK/$skill/SKILL.md"

  if [ -e "$target" ] || [ -L "$target" ]; then
    if [ ! -L "$target" ] && diff -rq "$WORK/$skill" "$target" >/dev/null 2>&1; then
      echo "  unchanged  $skill"; return 0
    fi
    if [ "$DRY_RUN" -eq 1 ]; then echo "  would replace  $skill (backup kept)"; return 0; fi
    if ! confirm "  $target exists. Replace it (a backup is kept)?"; then
      echo "  skipped    $skill"; return 0
    fi
    mv "$target" "$target.bak-$(date +%Y%m%d-%H%M%S)"
    echo "  backed up  $skill"
  elif [ "$DRY_RUN" -eq 1 ]; then
    echo "  would install  $skill"; return 0
  fi
  mv "$WORK/$skill" "$target"
  echo "  installed  $skill"
}

main() {
  parse_args "$@"
  [ -n "$OS" ] || OS="$(detect_os)"
  case "$OS" in macos|linux|windows) ;; *) die "--os must be macos, linux or windows" ;; esac
  SRC="$SKILLS_ROOT/$OS"
  [ -d "$SRC" ] || die "missing $SRC (run this from the repo)"
  resolve_inputs
  echo "Platform:   $OS"
    echo "Brain dir:  $BRAIN"
  echo "Skills to:  $DEST"
  [ "$DRY_RUN" -eq 1 ] && echo "(dry run: nothing will be changed)"
  [ "$DRY_RUN" -eq 1 ] || mkdir -p "$DEST"
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  for s in "${SKILLS[@]}"; do install_skill "$s"; done
  echo
  echo "Done. Open Claude Code and say: \"Build my claude brain.\""
  echo "Re-run ./install.sh after git pull to pick up skill updates."
}

main "$@"
