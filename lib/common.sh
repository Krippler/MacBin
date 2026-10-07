# shellcheck shell=bash
# Shared helpers for the MacBin scripts.

# shellcheck disable=SC2034 # used by the scripts sourcing this file
MACBIN_VERSION="0.1.0"

if [[ -t 2 ]]; then
  _c_info=$'\e[1;34m' _c_warn=$'\e[1;33m' _c_err=$'\e[1;31m' _c_ok=$'\e[1;32m' _c_off=$'\e[0m'
else
  _c_info='' _c_warn='' _c_err='' _c_ok='' _c_off=''
fi

log()  { printf '%s[macbin]%s %s\n' "$_c_info" "$_c_off" "$*" >&2; }
ok()   { printf '%s[macbin]%s %s\n' "$_c_ok" "$_c_off" "$*" >&2; }

if [[ ${GITHUB_ACTIONS:-} == true ]]; then
  # Surface problems as annotations on the workflow run.
  warn() { printf '::warning title=MacBin::%s\n' "$*" >&2; }
  die()  { printf '::error title=MacBin::%s\n' "$*" >&2; exit 1; }
  group()    { printf '::group::%s\n' "$*"; }
  endgroup() { printf '::endgroup::\n'; }
else
  warn() { printf '%s[macbin] warning:%s %s\n' "$_c_warn" "$_c_off" "$*" >&2; }
  die()  { printf '%s[macbin] error:%s %s\n' "$_c_err" "$_c_off" "$*" >&2; exit 1; }
  group()    { :; }
  endgroup() { :; }
fi

# split_words STRING ARRAY_NAME
# Splits STRING using shell quoting rules (without evaluating anything) into
# the named array, so values like CMAKE_ARGS='-DFOO="a b" -DBAR=1' work.
split_words() {
  local -n _out=$2
  _out=()
  [[ -n ${1//[[:space:]]/} ]] || return 0
  mapfile -d '' -t _out < <(python3 -c '
import shlex, sys
sys.stdout.write("".join(w + "\0" for w in shlex.split(sys.argv[1], comments=False)))
' "$1")
}

# Accepts "owner/repo" shorthand and returns a cloneable URL.
normalize_source() {
  local src=$1
  if [[ -d $src ]]; then
    printf '%s\n' "$src"
  elif [[ $src =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
    printf 'https://github.com/%s.git\n' "$src"
  else
    printf '%s\n' "$src"
  fi
}

# is_macho FILE - true for Mach-O executables, dylibs and bundles (thin or fat).
is_macho() {
  [[ -f $1 && ! -L $1 ]] || return 1
  local magic
  magic=$(od -An -tx1 -N4 "$1" 2>/dev/null | tr -d ' \n')
  case $magic in
    cffaedfe|cefaedfe|feedfacf|feedface|cafebabe) ;;
    *) return 1 ;;
  esac
  # cafebabe is also the magic of Java class files; those report no Mach-O header.
  [[ $magic != cafebabe ]] || llvm-otool -h "$1" >/dev/null 2>&1
}
