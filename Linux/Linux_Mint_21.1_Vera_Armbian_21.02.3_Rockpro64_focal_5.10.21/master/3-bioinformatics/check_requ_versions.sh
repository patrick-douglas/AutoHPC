#!/usr/bin/env bash
set -u
USAGE="USAGE: $0 -u <username>"
if [ "$#" -lt "1" ] 
then 
    echo -e $USAGE;
exit 1    
else 
    var1=$2;
fi

while getopts u: option
do
case "${option}"
in
u) user_name=$OPTARG;;
esac
done

if [ "$user_name" = "" ]; then
"${g}Error, missing arguments:${y} -u | User name | <string>
${w}$USAGE"
exit 1
fi
# ===== Colors =====
w=$(tput sgr0 2>/dev/null || true)
g=$(tput setaf 2 2>/dev/null || true)
r=$(tput setaf 1 2>/dev/null || true)
y=$(tput setaf 3 2>/dev/null || true)

# ===== Helpers =====
have_cmd() { command -v "$1" >/dev/null 2>&1; }

safe_run() { "$@" 2>&1 || true; }

clean_ver() {
  echo "$1" | tr -d '\r' | head -n 1 | sed -E 's/[[:space:]]+$//'
}

show_ver() {
  local v="$1"
  if [ -z "${v:-}" ]; then
    echo "${r}not installed${g}"
  else
    echo "$v"
  fi
}

# ==== Short function ====
shorten_mid () {
  local s="$1"
  local max="${2:-16}"
  if [ ${#s} -le $max ]; then
    printf "%s" "$s"
    return
  fi
  local head_len=$(( (max - 3) / 2 ))
  local tail_len=$(( max - 3 - head_len ))
  printf "%s...%s" "${s:0:head_len}" "${s: -tail_len}"
}

# ===== Version getters =====
get_bbmap_ver() {
  if have_cmd bbmap.sh; then
    out=$(bbmap.sh --version 2>&1)
    ver=$(echo "$out" | grep -Eo 'BBTools version[[:space:]]+[0-9.]+' | awk '{print $3}')
    [ -n "${ver:-}" ] && { echo "$ver"; return; }
    ver=$(echo "$out" | grep -Eo '([0-9]+\.){1,3}[0-9]+' | head -n 1)
    [ -n "${ver:-}" ] && { echo "$ver"; return; }
    echo ""
  else
    echo ""
  fi
}

get_miniprot_ver() {
  have_cmd miniprot || { echo ""; return; }
  out=$(safe_run miniprot --version)
  ver=$(echo "$out" | grep -Eo '([0-9]+\.){1,3}[0-9]+([-_.a-zA-Z0-9]+)?' | head -n 1)
  [ -n "${ver:-}" ] && echo "$ver" || clean_ver "$out"
}

get_tblastn_ver() {
  have_cmd tblastn || { echo ""; return; }
  out=$(safe_run tblastn -version)
  ver=$(echo "$out" | grep -Eo '([0-9]+\.){1,3}[0-9]+\+?' | head -n 1)
  [ -n "${ver:-}" ] && echo "$ver" || clean_ver "$out"
}

get_makeblastdb_ver() {
  have_cmd makeblastdb || { echo ""; return; }
  out=$(safe_run makeblastdb -version)
  ver=$(echo "$out" | grep -Eo '([0-9]+\.){1,3}[0-9]+\+?' | head -n 1)
  [ -n "${ver:-}" ] && echo "$ver" || clean_ver "$out"
}

get_augustus_ver() {
  have_cmd augustus || { echo ""; return; }
  out=$(safe_run augustus --version)
  ver=$(echo "$out" | grep -Eo '([0-9]+\.){1,3}[0-9]+' | head -n 1)
  [ -n "${ver:-}" ] && echo "$ver" || clean_ver "$out"
}

get_metaeuk_ver() {
  have_cmd metaeuk || { echo ""; return; }
  out=$(safe_run metaeuk version)
  # MetaEuk sometimes prints commit hash; keep first token-like thing
  ver=$(echo "$out" | grep -Eo '([0-9]+\.){1,3}[0-9]+|[0-9a-f]{8,}' | head -n 1)
  [ -n "${ver:-}" ] && echo "$ver" || clean_ver "$out"
}

get_hmmer_ver() {
  if have_cmd hmmsearch; then
    out=$(safe_run hmmsearch -h)
  elif have_cmd hmmscan; then
    out=$(safe_run hmmscan -h)
  else
    echo ""; return
  fi
  ver=$(echo "$out" | grep -Eo 'HMMER[[:space:]]+([0-9]+\.){1,3}[0-9]+' | head -n 1 | awk '{print $2}')
  [ -n "${ver:-}" ] && echo "$ver" || clean_ver "$(echo "$out" | head -n 1)"
}

get_prodigal_ver() {
  have_cmd prodigal || { echo ""; return; }
  out=$(safe_run prodigal -v)
  ver=$(echo "$out" | grep -Eo 'V([0-9]+\.){1,3}[0-9]+' | head -n 1 | sed 's/^V//')
  [ -n "${ver:-}" ] && echo "$ver" || clean_ver "$out"
}

get_sepp_ver() {
  if have_cmd run_sepp.py; then
    out=$(safe_run run_sepp.py -v)
  elif have_cmd sepp; then
    out=$(safe_run sepp -h)
  else
    echo ""; return
  fi
  ver=$(echo "$out" | grep -Eo '([0-9]+\.){1,3}[0-9]+' | head -n 1)
  [ -n "${ver:-}" ] && echo "$ver" || clean_ver "$(echo "$out" | head -n 1)"
}

# ===== Collect versions =====
bbmap_ver=$(get_bbmap_ver)
miniprot_ver=$(get_miniprot_ver)
tBLASTn_ver=$(get_tblastn_ver)
makeblastdb_ver=$(get_makeblastdb_ver)
augustus_ver=$(get_augustus_ver)
metaeuk_ver=$(get_metaeuk_ver)
hmmer_ver=$(get_hmmer_ver)
prodigal_ver=$(get_prodigal_ver)
sepp_ver=$(get_sepp_ver)

# =========================
# PATH / FILE verification
# =========================

# ---------- helpers ----------
color_status () {
  case "$1" in
    OK)            printf "%s" "$g" ;;
    "WRONG PATH")  printf "%s" "$y" ;;
    *)             printf "%s" "$r" ;;
  esac
}

# For commands expected in PATH
check_cmd_path() {
  local label="$1"
  local expected_dir="$2"
  local cmd="$3"
  local version="$4"

  local found status

  if have_cmd "$cmd"; then
    found="$(command -v "$cmd")"
    if [[ "$found" == "$expected_dir"* ]]; then
      status="OK"
    else
      status="WRONG PATH"
    fi
  else
    found="-"
    status="NOT FOUND"
  fi

  printf "║ %-20s ║ %-48s ║ %-16s ║ %s%-6s%s ║\n" \
    "$label" \
    "$found" \
    "$(shorten_mid "$version" 16)" \
    "$(color_status "$status")" \
    "$status" \
    "$w"
}

# For files/scripts NOT expected in PATH
check_file_exists() {
  local label="$1"
  local fullpath="$2"
  local version="$3"

  local found status

  if [ -e "$fullpath" ]; then
    found="$fullpath"
    status="OK"
  else
    found="-"
    status="NOT FOUND"
  fi

  printf "║ %-20s ║ %-48s ║ %-16s ║ %s%-6s%s ║\n" \
    "$label" \
    "$found" \
    "$(shorten_mid "$version" 12)" \
    "$(color_status "$status")" \
    "$status" \
    "$w"
}

# =========================
# Table print
# =========================

echo "╔══════════════════════╦══════════════════════════════════════════════════╦══════════════════╦════════╗"
echo "║ Tool                 ║ Path                                             ║ Version          ║ Status ║"
echo "╠══════════════════════╬══════════════════════════════════════════════════╬══════════════════╬════════╣"

# Commands in PATH
check_cmd_path "tblastn"     "/usr/bin/"           "tblastn"     "$tBLASTn_ver"
check_cmd_path "makeblastdb" "/usr/bin/"           "makeblastdb" "$makeblastdb_ver"
check_cmd_path "metaeuk"     "/usr/local/bin/"     "metaeuk"     "$metaeuk_ver"
check_cmd_path "augustus"    "/usr/local/bin/"     "augustus"    "$augustus_ver"
check_cmd_path "etraining"   "/usr/local/bin/"     "etraining"   "$augustus_ver"
check_cmd_path "miniprot"    "/usr/local/bin/"     "miniprot"    "$miniprot_ver"
check_cmd_path "hmmsearch"   "/usr/local/bin/"     "hmmsearch"   "$hmmer_ver"
check_cmd_path "sepp"        "/usr/local/bin/"     "run_sepp.py" "$sepp_ver"
check_cmd_path "prodigal"    "/usr/local/bin/"     "prodigal"    "$prodigal_ver"

# BBTools: check for stats.sh inside bbmap directory
check_file_exists "bbtools (stats.sh)" "/usr/local/bin/bbmap/stats.sh" "$bbmap_ver"

# Augustus scripts (file existence only)
check_file_exists "gff2gbSmallDNA.pl"    "/usr/share/augustus/scripts/gff2gbSmallDNA.pl"    "$augustus_ver"
check_file_exists "new_species.pl"       "/usr/share/augustus/scripts/new_species.pl"       "$augustus_ver"
check_file_exists "optimize_augustus.pl" "/usr/share/augustus/scripts/optimize_augustus.pl" "$augustus_ver"

echo "${w}╚══════════════════════╩══════════════════════════════════════════════════╩══════════════════╩════════╝"

# =========================
# Auto-fix ~/.bashrc for AUGUSTUS (run as target user)
# Script runs as root; user_name must be defined
# =========================

echo
echo "${g}═══════════════════════════════════════════════════════════════${w}"
echo "${g}AUGUSTUS: updating ~/.bashrc for user '${user_name}' (run-as-user)${w}"
echo "${g}═══════════════════════════════════════════════════════════════${w}"

if ! have_cmd augustus; then
  echo "${r}AUGUSTUS not found in PATH; skipping ~/.bashrc configuration.${w}"
  echo "${g}═══════════════════════════════════════════════════════════════${w}"
else
  # Detect real installation paths (as root)
  AUG_BIN="$(command -v augustus)"
  AUG_BIN_DIR="$(dirname "$AUG_BIN")"
  AUG_SCRIPTS_DIR="/usr/share/augustus/scripts"
  AUG_CONFIG_DIR="/usr/share/augustus/config"

  # Run modifications as the target user (NOT root).
  # Pass paths via env vars; use a *quoted* heredoc to prevent any expansion.
  su - "$user_name" -c \
    "AUG_BIN_DIR='$AUG_BIN_DIR' AUG_SCRIPTS_DIR='$AUG_SCRIPTS_DIR' AUG_CONFIG_DIR='$AUG_CONFIG_DIR' bash -s" <<'EOF'
set -euo pipefail

BASHRC="$HOME/.bashrc"
ts=$(date +"%Y%m%d_%H%M%S")

BEGIN_MARKER='# >>> AUGUSTUS AUTO-CONFIG (managed by script) >>>'
END_MARKER='# <<< AUGUSTUS AUTO-CONFIG (managed by script) <<<'

# Ensure ~/.bashrc exists
[ -e "$BASHRC" ] || touch "$BASHRC"

# Backup
cp "$BASHRC" "$BASHRC.bak_$ts" 2>/dev/null || true
echo "Backup created: $BASHRC.bak_$ts"

# Remove any previously managed block (defensive / idempotent)
sed -i "/^# >>> AUGUSTUS AUTO-CONFIG (managed by script) >>>/,/^# <<< AUGUSTUS AUTO-CONFIG (managed by script) <<</d" "$BASHRC"

# Append fresh managed block (WRITE $PATH LITERALLY)
{
  echo
  echo "$BEGIN_MARKER"
  echo "export PATH=\"$AUG_BIN_DIR:\$PATH\""
  if [ -d "$AUG_SCRIPTS_DIR" ]; then
    echo "export PATH=\"$AUG_SCRIPTS_DIR:\$PATH\""
  fi
  if [ -d "$AUG_CONFIG_DIR" ]; then
    echo "export AUGUSTUS_CONFIG_PATH=\"$AUG_CONFIG_DIR/\""
  fi
  echo "$END_MARKER"
} >> "$BASHRC"

echo
echo "Updated $BASHRC with:"
echo "  export PATH=\"$AUG_BIN_DIR:\$PATH\""
[ -d "$AUG_SCRIPTS_DIR" ] && echo "  export PATH=\"$AUG_SCRIPTS_DIR:\$PATH\""
[ -d "$AUG_CONFIG_DIR" ]  && echo "  export AUGUSTUS_CONFIG_PATH=\"$AUG_CONFIG_DIR/\""
EOF

  # IMPORTANT: check exit status without escaping
  if [ $? -eq 0 ]; then
    echo
    echo "${g}SUCCESS${w}: ~/.bashrc updated for user '${user_name}'."
    echo "To apply immediately (as that user):"
    echo "  su - ${user_name}"
    echo "  source ~/.bashrc"
  else
    echo "${r}FAILED${w}: could not update ~/.bashrc for ${user_name}."
  fi

  echo "${g}═══════════════════════════════════════════════════════════════${w}"
fi
