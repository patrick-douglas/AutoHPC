#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# DEFAULT VARIABLES
# Can be changed by command-line parameters.
# ============================================================

SRC_URL="https://github.com/trinityrnaseq/trinityrnaseq/releases/download/Trinity-v2.15.2/trinityrnaseq-v2.15.2.FULL.tar.gz"

PKG_NAME="trinityrnaseq"
TRINITY_VERSION="auto"
PKG_ITERATION="1"

THREADS="$(nproc)"

BUILD_ROOT="/node_temp/trinity_build"
OUTDIR="/node_temp"

# Default layout compatible with older Trinity expectations:
#   /usr/local/bin/trinityrnaseq-latest/Trinity
#   /usr/local/bin/trinityrnaseq-latest/util/
#   /usr/local/bin/trinityrnaseq-latest/trinity-plugins/
#   /usr/local/bin/Trinity  -> wrapper that executes the real Trinity
INSTALL_PREFIX="/usr/local/bin"
INSTALL_DIR_BASENAME="trinityrnaseq-latest"

INSTALL_DEB="yes"
RUN_APT_INSTALL="yes"
RUN_MAKE_INSTALL_TEST="yes"
COPY_DEB_TO_CWD="yes"

MAINTAINER="Patrick Pereira"
DESCRIPTION="Trinity RNA-Seq assembler locally built for ARM64/aarch64"

START_DIR="$(pwd -P)"

# ============================================================
# COLORS
# ============================================================

if [ -t 1 ]; then
    RED="\033[1;31m"
    GREEN="\033[1;32m"
    YELLOW="\033[1;33m"
    BLUE="\033[1;34m"
    MAGENTA="\033[1;35m"
    CYAN="\033[1;36m"
    WHITE="\033[1;37m"
    RESET="\033[0m"
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    MAGENTA=""
    CYAN=""
    WHITE=""
    RESET=""
fi

# ============================================================
# HELP
# ============================================================

usage() {
cat <<USAGE
Usage:
  $0 --src_url URL_OR_LOCAL_TAR_GZ [options]

Required/important:
  --src_url URL_OR_PATH          URL or local path to Trinity source tar.gz / FULL tar.gz / zip

Options:
  --version VERSION             Package version. Default: auto
  --pkg_name NAME               Debian package name. Default: trinityrnaseq
  --iteration N                 Debian package iteration. Default: 1
  --threads N                   Build threads. Default: nproc
  --build_root DIR              Build working directory. Default: /node_temp/trinity_build
  --outdir DIR                  Output directory for .deb. Default: /node_temp

  --install_prefix DIR          Install prefix inside package.
                                Default: /usr/local/bin

  --install_dir_name NAME       Directory name under install prefix.
                                Default: trinityrnaseq-latest

  --install_deb yes|no          Install created .deb with dpkg. Default: yes
  --apt_install yes|no          Install build dependencies with apt. Default: yes
  --make_install_test yes|no    Test make install into temporary DESTDIR. Default: yes
  --copy_deb_to_cwd yes|no      Copy final .deb to launch directory. Default: yes
  --maintainer NAME             Package maintainer. Default: Patrick Pereira
  --description TEXT            Package description
  -h, --help                    Show this help

Examples:

  $0 --src_url https://github.com/trinityrnaseq/trinityrnaseq/releases/download/Trinity-v2.15.2/trinityrnaseq-v2.15.2.FULL.tar.gz --version 2.15.2 --threads 6

  $0 --src_url /node_temp/trinityrnaseq-v2.15.2.FULL.tar.gz --version 2.15.2 --threads 6

  $0 --src_url /node_temp/trinityrnaseq-v2.15.2.FULL.tar.gz --version 2.15.2 --install_deb no

Default final layout:

  /usr/local/bin/trinityrnaseq-latest/Trinity
  /usr/local/bin/trinityrnaseq-latest/util/
  /usr/local/bin/trinityrnaseq-latest/trinity-plugins/
  /usr/local/bin/Trinity

The /usr/local/bin/Trinity file is a wrapper, not a symlink.

Build commands used:

  make -jTHREADS
  make -jTHREADS plugins

If this Trinity version has no top-level 'plugins' target, the script falls back to:

  make -C trinity-plugins -jTHREADS
USAGE
}

# ============================================================
# ARGUMENT PARSER
# ============================================================

need_value() {
    local opt="$1"
    local val="${2:-}"
    if [ -z "$val" ]; then
        echo -e "${RED}ERROR:${RESET} option $opt requires a value"
        exit 1
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --src_url|--source_url)
            need_value "$1" "${2:-}"
            SRC_URL="$2"
            shift 2
            ;;
        --version)
            need_value "$1" "${2:-}"
            TRINITY_VERSION="$2"
            shift 2
            ;;
        --pkg_name)
            need_value "$1" "${2:-}"
            PKG_NAME="$2"
            shift 2
            ;;
        --iteration)
            need_value "$1" "${2:-}"
            PKG_ITERATION="$2"
            shift 2
            ;;
        --threads)
            need_value "$1" "${2:-}"
            THREADS="$2"
            shift 2
            ;;
        --build_root)
            need_value "$1" "${2:-}"
            BUILD_ROOT="$2"
            shift 2
            ;;
        --outdir)
            need_value "$1" "${2:-}"
            OUTDIR="$2"
            shift 2
            ;;
        --install_prefix)
            need_value "$1" "${2:-}"
            INSTALL_PREFIX="$2"
            shift 2
            ;;
        --install_dir_name)
            need_value "$1" "${2:-}"
            INSTALL_DIR_BASENAME="$2"
            shift 2
            ;;
        --install_deb)
            need_value "$1" "${2:-}"
            INSTALL_DEB="$2"
            shift 2
            ;;
        --apt_install)
            need_value "$1" "${2:-}"
            RUN_APT_INSTALL="$2"
            shift 2
            ;;
        --make_install_test)
            need_value "$1" "${2:-}"
            RUN_MAKE_INSTALL_TEST="$2"
            shift 2
            ;;
        --copy_deb_to_cwd)
            need_value "$1" "${2:-}"
            COPY_DEB_TO_CWD="$2"
            shift 2
            ;;
        --maintainer)
            need_value "$1" "${2:-}"
            MAINTAINER="$2"
            shift 2
            ;;
        --description)
            need_value "$1" "${2:-}"
            DESCRIPTION="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option:${RESET} $1"
            usage
            exit 1
            ;;
    esac
done

# ============================================================
# INTERNAL VARIABLES
# ============================================================

export DEBIAN_FRONTEND=noninteractive

ARCH="$(dpkg --print-architecture)"
DATE_TAG="$(date +%Y%m%d_%H%M%S)"

mkdir -p "$BUILD_ROOT" "$OUTDIR"

LOG_DIR="$BUILD_ROOT/logs"
mkdir -p "$LOG_DIR"

ARCHIVE="$BUILD_ROOT/source_$(basename "$SRC_URL" | sed 's/[^A-Za-z0-9._-]/_/g')"
EXTRACT_DIR="$BUILD_ROOT/source_extract"
STAGE="$BUILD_ROOT/deb_stage"
MAKE_INSTALL_STAGE="$BUILD_ROOT/make_install_stage"

SRC_DIR=""
INSTALL_DIR=""
DEB_FILE=""
DEB_COPY=""

# ============================================================
# FUNCTIONS
# ============================================================

msg() {
    echo
    echo -e "${CYAN}============================================================${RESET}"
    echo -e "${YELLOW}$1${RESET}"
    echo -e "${CYAN}============================================================${RESET}"
}

submsg() {
    echo -e "${BLUE}>>>${RESET} $1"
}

ok() {
    echo -e "${GREEN}OK:${RESET} $1"
}

warn() {
    echo -e "${MAGENTA}WARNING:${RESET} $1"
}

die() {
    echo
    echo -e "${RED}ERROR:${RESET} $1"
    exit 1
}

infer_version() {
    local text="$1"
    local v=""

    v="$(echo "$text" | grep -oE '[vV]?[0-9]+(\.[0-9]+){1,3}' | head -n 1 | sed -E 's/^[vV]//')" || true

    if [ -z "$v" ]; then
        v="0.0.0.${DATE_TAG}"
    fi

    echo "$v"
}

validate_yes_no() {
    local name="$1"
    local value="$2"

    case "$value" in
        yes|no)
            ;;
        *)
            die "$name must be yes or no. Got: $value"
            ;;
    esac
}

validate_args() {
    msg "[PRE] Validating parameters"

    validate_yes_no "--install_deb" "$INSTALL_DEB"
    validate_yes_no "--apt_install" "$RUN_APT_INSTALL"
    validate_yes_no "--make_install_test" "$RUN_MAKE_INSTALL_TEST"
    validate_yes_no "--copy_deb_to_cwd" "$COPY_DEB_TO_CWD"

    if ! [[ "$THREADS" =~ ^[0-9]+$ ]]; then
        die "--threads must be an integer. Got: $THREADS"
    fi

    if [ "$THREADS" -lt 1 ]; then
        die "--threads must be >= 1"
    fi

    if [[ "$INSTALL_PREFIX" != /* ]]; then
        die "--install_prefix must be an absolute path. Got: $INSTALL_PREFIX"
    fi

    if [[ "$INSTALL_DIR_BASENAME" = /* ]]; then
        die "--install_dir_name must be a directory name, not an absolute path. Got: $INSTALL_DIR_BASENAME"
    fi

    ok "parameters look valid"
}

install_build_deps() {
    if [ "$RUN_APT_INSTALL" != "yes" ]; then
        warn "Skipping apt dependency installation because --apt_install=$RUN_APT_INSTALL"
        return
    fi

    msg "[0] Installing build dependencies"

    apt-get update || true

    apt-get install -y \
        build-essential \
        gcc \
        g++ \
        make \
        cmake \
        autoconf \
        automake \
        libtool \
        pkg-config \
        git \
        wget \
        curl \
        perl \
        python3 \
        default-jre \
        zlib1g-dev \
        libbz2-dev \
        liblzma-dev \
        libcurl4-openssl-dev \
        libssl-dev \
        libncurses-dev \
        rsync \
        unzip \
        ruby \
        ruby-dev \
        rubygems

    if ! command -v fpm >/dev/null 2>&1; then
        msg "[0b] Installing fpm"
        gem install --no-document fpm
    fi

    command -v fpm >/dev/null 2>&1 || die "fpm is not available."
    ok "build dependencies checked"
}

download_or_copy_source() {
    msg "[1] Getting Trinity source"

    rm -f "$ARCHIVE"

    echo -e "${BLUE}SRC_URL:${RESET}  $SRC_URL"
    echo -e "${BLUE}ARCHIVE:${RESET} $ARCHIVE"

    if [[ "$SRC_URL" =~ ^https?://|^ftp:// ]]; then
        if command -v curl >/dev/null 2>&1; then
            curl -L --retry 5 --retry-delay 5 -o "$ARCHIVE" "$SRC_URL"
        else
            wget -O "$ARCHIVE" "$SRC_URL"
        fi
    else
        if [ ! -f "$SRC_URL" ]; then
            die "Local source file not found: $SRC_URL"
        fi
        cp -f "$SRC_URL" "$ARCHIVE"
    fi

    test -s "$ARCHIVE" || die "Source archive is empty or missing."

    ok "source archive ready"
}

extract_source() {
    msg "[2] Extracting source"

    rm -rf "$EXTRACT_DIR"
    mkdir -p "$EXTRACT_DIR"

    case "$ARCHIVE" in
        *.tar.gz|*.tgz)
            tar -xzf "$ARCHIVE" -C "$EXTRACT_DIR"
            ;;
        *.tar.bz2|*.tbz2)
            tar -xjf "$ARCHIVE" -C "$EXTRACT_DIR"
            ;;
        *.tar.xz|*.txz)
            tar -xJf "$ARCHIVE" -C "$EXTRACT_DIR"
            ;;
        *.zip)
            unzip -q "$ARCHIVE" -d "$EXTRACT_DIR"
            ;;
        *)
            tar -xf "$ARCHIVE" -C "$EXTRACT_DIR"
            ;;
    esac

    SRC_DIR="$(find "$EXTRACT_DIR" -mindepth 1 -maxdepth 4 -type f -name Trinity -print -quit | xargs -r dirname)"

    test -n "${SRC_DIR:-}" || die "Could not detect Trinity source directory. Missing Trinity script."
    test -f "$SRC_DIR/Trinity" || die "Extracted source does not look like Trinity."

    echo -e "${BLUE}SRC_DIR:${RESET} $SRC_DIR"
    ok "source extracted"
}

set_version_and_install_dir() {
    msg "[2b] Setting version and install paths"

    if [ "$TRINITY_VERSION" = "auto" ]; then
        TRINITY_VERSION="$(infer_version "$SRC_URL")"
    fi

    INSTALL_DIR="${INSTALL_PREFIX}/${INSTALL_DIR_BASENAME}"
    DEB_FILE="${OUTDIR}/${PKG_NAME}_${TRINITY_VERSION}-${PKG_ITERATION}_${ARCH}.deb"
    DEB_COPY="${START_DIR}/$(basename "$DEB_FILE")"

    echo -e "${BLUE}TRINITY_VERSION:${RESET} $TRINITY_VERSION"
    echo -e "${BLUE}INSTALL_PREFIX:${RESET}  $INSTALL_PREFIX"
    echo -e "${BLUE}INSTALL_DIR_NAME:${RESET} $INSTALL_DIR_BASENAME"
    echo -e "${BLUE}INSTALL_DIR:${RESET}     $INSTALL_DIR"
    echo -e "${BLUE}DEB_FILE:${RESET}        $DEB_FILE"
    echo -e "${BLUE}DEB_COPY:${RESET}        $DEB_COPY"
}

patch_arm64_m64_flags() {
    msg "[3] Applying ARM64 patch: removing x86_64 -m64 flags"

    local targets=()

    [ -d "$SRC_DIR/Inchworm" ] && targets+=("$SRC_DIR/Inchworm")
    [ -d "$SRC_DIR/Chrysalis" ] && targets+=("$SRC_DIR/Chrysalis")
    [ -d "$SRC_DIR/trinity-plugins/ParaFly" ] && targets+=("$SRC_DIR/trinity-plugins/ParaFly")

    if [ "${#targets[@]}" -eq 0 ]; then
        warn "No Inchworm/Chrysalis/ParaFly directories found. Skipping -m64 patch."
        return
    fi

    grep -RIl -- "-m64" "${targets[@]}" 2>/dev/null | while read -r f; do
        case "$f" in
            *.bak|*.pre_arm64_patch.bak|*/config.log*)
                continue
                ;;
        esac

        echo -e "${BLUE}patch -m64:${RESET} $f"
        cp -n "$f" "$f.pre_arm64_patch.bak" || true
        perl -pi -e 's/-m64\b//g' "$f"
    done

    echo
    submsg "Checking remaining active -m64 entries"

    if grep -RIn \
        --exclude="*.bak" \
        --exclude="*.pre_arm64_patch.bak" \
        --exclude="config.log*" \
        -- "-m64" "${targets[@]}" 2>/dev/null; then
        die "Active -m64 flags are still present."
    else
        ok "no active -m64 flags found"
    fi
}

patch_htscodecs_version() {
    msg "[4] Applying htscodecs version.h patch"

    local htscodecs_dir="$SRC_DIR/trinity-plugins/bamsifter/htslib/htscodecs/htscodecs"

    if [ ! -d "$htscodecs_dir" ]; then
        warn "Directory not found: $htscodecs_dir"
        warn "Skipping htscodecs patch."
        return
    fi

    mkdir -p "$htscodecs_dir"

    cat > "$htscodecs_dir/version.h" <<'EOH'
#ifndef HTSCODECS_VERSION_TEXT
#define HTSCODECS_VERSION_TEXT "vendored"
#endif
EOH

    echo -e "${BLUE}Created/updated:${RESET} $htscodecs_dir/version.h"
    ok "htscodecs version patch applied"
}

clean_previous_builds() {
    msg "[5] Cleaning previous build directories"

    rm -rf "$SRC_DIR/Inchworm/build" || true
    rm -rf "$SRC_DIR/Chrysalis/build" || true

    if [ -d "$SRC_DIR/trinity-plugins/ParaFly" ]; then
        cd "$SRC_DIR/trinity-plugins/ParaFly"
        make distclean >/dev/null 2>&1 || true
        rm -f Makefile src/Makefile config.status config.log
        cd "$SRC_DIR"
    fi

    if [ -d "$SRC_DIR/trinity-plugins/bamsifter" ]; then
        cd "$SRC_DIR/trinity-plugins/bamsifter"
        make clean >/dev/null 2>&1 || true
        cd "$SRC_DIR"
    fi

    ok "old build directories cleaned"
}

target_exists() {
    local target="$1"
    make -qp 2>/dev/null | awk -F: '/^[A-Za-z0-9_.\/-]+:/ {print $1}' | grep -qx "$target"
}

build_trinity() {
    msg "[6] Building Trinity: make"

    cd "$SRC_DIR"

    echo -e "${BLUE}Using THREADS:${RESET} $THREADS"
    echo -e "${BLUE}Build log:${RESET} $LOG_DIR/build_make_${DATE_TAG}.log"

    make -j"$THREADS" 2>&1 | tee "$LOG_DIR/build_make_${DATE_TAG}.log"

    msg "[6b] Building Trinity plugins: make plugins"

    echo -e "${BLUE}Plugin build log:${RESET} $LOG_DIR/build_make_plugins_${DATE_TAG}.log"

    if target_exists "plugins"; then
        echo -e "${GREEN}Detected Makefile target:${RESET} plugins"
        make -j"$THREADS" plugins 2>&1 | tee "$LOG_DIR/build_make_plugins_${DATE_TAG}.log"
    else
        warn "No top-level Makefile target named 'plugins' detected."
        warn "Fallback: make -C trinity-plugins"

        if [ -d "$SRC_DIR/trinity-plugins" ]; then
            make -C "$SRC_DIR/trinity-plugins" -j"$THREADS" 2>&1 | tee "$LOG_DIR/build_make_plugins_${DATE_TAG}.log"
        else
            warn "trinity-plugins directory not found. Skipping plugin fallback."
        fi
    fi

    ok "Trinity build steps completed"
}

run_make_install_test() {
    if [ "$RUN_MAKE_INSTALL_TEST" != "yes" ]; then
        warn "Skipping make install test because --make_install_test=$RUN_MAKE_INSTALL_TEST"
        return
    fi

    msg "[7] Running make install test into temporary DESTDIR when available"

    cd "$SRC_DIR"

    rm -rf "$MAKE_INSTALL_STAGE"
    mkdir -p "$MAKE_INSTALL_STAGE"

    if target_exists "install"; then
        make install DESTDIR="$MAKE_INSTALL_STAGE" 2>&1 | tee "$LOG_DIR/make_install_${DATE_TAG}.log" || true
        echo -e "${BLUE}make install test stage:${RESET} $MAKE_INSTALL_STAGE"
    else
        warn "No usable make install target detected. This is OK for Trinity."
        warn "The DEB will package the Trinity tree into $INSTALL_DIR and expose /usr/local/bin/Trinity."
    fi
}

test_local_build() {
    msg "[8] Testing local build"

    cd "$SRC_DIR"

    chmod +x ./Trinity || true

    echo -e "${BLUE}Trinity version test:${RESET}"
    ./Trinity --version || true

    echo
    echo -e "${BLUE}ParaFly test:${RESET}"
    if [ -x "$SRC_DIR/trinity-plugins/BIN/ParaFly" ]; then
        "$SRC_DIR/trinity-plugins/BIN/ParaFly" -h | head -n 5 || true
    elif [ -x "$SRC_DIR/trinity-plugins/ParaFly/bin/ParaFly" ]; then
        "$SRC_DIR/trinity-plugins/ParaFly/bin/ParaFly" -h | head -n 5 || true
    else
        warn "ParaFly executable not found in expected locations."
    fi

    echo
    echo -e "${BLUE}Inchworm test:${RESET}"
    if [ -x "$SRC_DIR/Inchworm/bin/inchworm" ]; then
        "$SRC_DIR/Inchworm/bin/inchworm" 2>&1 | head -n 5 || true
    else
        warn "Inchworm executable not found in Inchworm/bin/inchworm"
    fi
}

create_deb_stage() {
    msg "[9] Creating DEB staging tree"

    rm -rf "$STAGE"

    mkdir -p "$STAGE${INSTALL_PREFIX}"
    mkdir -p "$STAGE/usr/local/bin"
    mkdir -p "$STAGE/usr/share/doc/${PKG_NAME}"

    echo -e "${BLUE}Copying source/build tree to:${RESET} $STAGE${INSTALL_DIR}"

    rsync -a \
        --exclude ".git" \
        --exclude "*.o" \
        --exclude "CMakeFiles" \
        --exclude "CMakeCache.txt" \
        --exclude "cmake_install.cmake" \
        --exclude "*.pre_arm64_patch.bak" \
        --exclude "backup_before_arm64_patch_*" \
        "$SRC_DIR/" \
        "$STAGE${INSTALL_DIR}/"

    # Important:
    # Do NOT create /usr/local/bin/Trinity as a symlink.
    # A symlink can confuse Trinity's internal relative paths.
    # Use a wrapper instead, so the real script path is preserved.
    cat > "$STAGE/usr/local/bin/Trinity" <<EOF
#!/usr/bin/env bash
exec ${INSTALL_DIR}/Trinity "\$@"
EOF

    chmod +x "$STAGE/usr/local/bin/Trinity"

    cat > "$STAGE/usr/share/doc/${PKG_NAME}/README.local-arm64.txt" <<DOC
Trinity RNA-Seq ${TRINITY_VERSION}

Locally built package for ARM64/aarch64.

Installed path:
  ${INSTALL_DIR}

Main executable:
  /usr/local/bin/Trinity

Real executable:
  ${INSTALL_DIR}/Trinity

Test:
  Trinity --version

Original source:
  ${SRC_URL}

Build date:
  ${DATE_TAG}

Build commands used:
  make -j${THREADS}
  make -j${THREADS} plugins

Notes:
  This package was built from a locally patched Trinity tree for ARM64/aarch64.
  The ARM64 patch removes x86_64-only -m64 flags.
  The htscodecs patch creates a minimal version.h when the vendored source lacks git metadata.
  /usr/local/bin/Trinity is a wrapper, not a symlink, to avoid breaking Trinity's relative internal paths.
DOC

    chmod -R a+rX "$STAGE${INSTALL_DIR}"
    chmod +x "$STAGE${INSTALL_DIR}/Trinity"

    echo
    submsg "Checking staged layout"
    ls -ld "$STAGE${INSTALL_DIR}" || true
    ls -lh "$STAGE${INSTALL_DIR}/Trinity" || true
    ls -lh "$STAGE/usr/local/bin/Trinity" || true

    ok "DEB staging tree ready"
}

build_deb() {
    msg "[10] Building DEB package with fpm"

    rm -f "$DEB_FILE"

    FPM_ARGS=()
    FPM_ARGS+=("-s" "dir")
    FPM_ARGS+=("-t" "deb")
    FPM_ARGS+=("-n" "$PKG_NAME")
    FPM_ARGS+=("-v" "$TRINITY_VERSION")
    FPM_ARGS+=("--iteration" "$PKG_ITERATION")
    FPM_ARGS+=("--architecture" "$ARCH")
    FPM_ARGS+=("--description" "$DESCRIPTION")
    FPM_ARGS+=("--maintainer" "$MAINTAINER")
    FPM_ARGS+=("--deb-no-default-config-files")

    FPM_ARGS+=("--depends" "perl")
    FPM_ARGS+=("--depends" "python3")
    FPM_ARGS+=("--depends" "default-jre")
    FPM_ARGS+=("--depends" "libgomp1")
    FPM_ARGS+=("--depends" "zlib1g")
    FPM_ARGS+=("--depends" "libbz2-1.0")
    FPM_ARGS+=("--depends" "liblzma5")
    FPM_ARGS+=("--depends" "libcurl4")

    if dpkg-query -W -f='${Status}' libssl1.1 2>/dev/null | grep -q "install ok installed"; then
        FPM_ARGS+=("--depends" "libssl1.1")
    elif dpkg-query -W -f='${Status}' libssl3 2>/dev/null | grep -q "install ok installed"; then
        FPM_ARGS+=("--depends" "libssl3")
    fi

    FPM_ARGS+=("-C" "$STAGE")
    FPM_ARGS+=("-p" "$DEB_FILE")
    FPM_ARGS+=(".")

    fpm "${FPM_ARGS[@]}"

    test -s "$DEB_FILE" || die "DEB package was not created."

    echo
    echo -e "${GREEN}Created package:${RESET}"
    ls -lh "$DEB_FILE"

    echo
    dpkg-deb -I "$DEB_FILE"

    ok "DEB package created"
}

install_deb_package() {
    if [ "$INSTALL_DEB" != "yes" ]; then
        warn "Skipping dpkg install because --install_deb=$INSTALL_DEB"
        return
    fi

    msg "[11] Installing DEB with dpkg"

    dpkg -i "$DEB_FILE" || apt-get install -f -y

    echo
    echo -e "${BLUE}Installed package check:${RESET}"
    dpkg -l "$PKG_NAME" || true

    echo
    echo -e "${BLUE}Binary check:${RESET}"
    which Trinity || true
    ls -lh "$(command -v Trinity)" || true
    Trinity --version || true

    echo
    echo -e "${BLUE}Real Trinity path check:${RESET}"
    ls -lh "${INSTALL_DIR}/Trinity" || true
    ls -ld "${INSTALL_DIR}/util" || true
    ls -ld "${INSTALL_DIR}/trinity-plugins" || true

    ok "DEB installation step completed"
}

copy_deb_to_cwd() {
    if [ "$COPY_DEB_TO_CWD" != "yes" ]; then
        warn "Skipping copy to launch directory because --copy_deb_to_cwd=$COPY_DEB_TO_CWD"
        return
    fi

    msg "[12] Copying DEB to the directory where the script was launched"

    mkdir -p "$START_DIR"

    if [ "$(realpath "$DEB_FILE")" = "$(realpath -m "$DEB_COPY")" ]; then
        echo -e "${BLUE}DEB is already in launch directory:${RESET}"
        echo "  $DEB_COPY"
    else
        cp -f "$DEB_FILE" "$DEB_COPY"
        echo -e "${GREEN}Copied:${RESET}"
        echo "  $DEB_FILE"
        echo -e "${GREEN}to:${RESET}"
        echo "  $DEB_COPY"
        ls -lh "$DEB_COPY"
    fi

    ok "DEB copied to launch directory"
}

final_report() {
    msg "DONE"

    echo -e "${BLUE}Source:${RESET}"
    echo "  $SRC_URL"

    echo
    echo -e "${BLUE}Build source directory:${RESET}"
    echo "  $SRC_DIR"

    echo
    echo -e "${BLUE}Installed directory:${RESET}"
    echo "  $INSTALL_DIR"

    echo
    echo -e "${BLUE}Wrapper:${RESET}"
    echo "  /usr/local/bin/Trinity"

    echo
    echo -e "${BLUE}DEB package:${RESET}"
    echo "  $DEB_FILE"

    echo
    echo -e "${BLUE}DEB copy in launch directory:${RESET}"
    echo "  $DEB_COPY"

    echo
    echo -e "${BLUE}Useful commands:${RESET}"
    echo "  dpkg -i $DEB_COPY"
    echo "  apt remove $PKG_NAME"
    echo "  Trinity --version"
    echo "  ls -lh ${INSTALL_DIR}/Trinity"
}

# ============================================================
# MAIN
# ============================================================

msg "Trinity ARM64 build + patch + make + make plugins + DEB pipeline"

echo -e "${BLUE}SRC_URL:${RESET}                $SRC_URL"
echo -e "${BLUE}PKG_NAME:${RESET}               $PKG_NAME"
echo -e "${BLUE}TRINITY_VERSION:${RESET}        $TRINITY_VERSION"
echo -e "${BLUE}THREADS:${RESET}                $THREADS"
echo -e "${BLUE}ARCH:${RESET}                   $ARCH"
echo -e "${BLUE}BUILD_ROOT:${RESET}             $BUILD_ROOT"
echo -e "${BLUE}OUTDIR:${RESET}                 $OUTDIR"
echo -e "${BLUE}INSTALL_PREFIX:${RESET}         $INSTALL_PREFIX"
echo -e "${BLUE}INSTALL_DIR_BASENAME:${RESET}   $INSTALL_DIR_BASENAME"
echo -e "${BLUE}INSTALL_DEB:${RESET}            $INSTALL_DEB"
echo -e "${BLUE}RUN_APT_INSTALL:${RESET}        $RUN_APT_INSTALL"
echo -e "${BLUE}RUN_MAKE_INSTALL_TEST:${RESET}  $RUN_MAKE_INSTALL_TEST"
echo -e "${BLUE}COPY_DEB_TO_CWD:${RESET}        $COPY_DEB_TO_CWD"
echo -e "${BLUE}START_DIR:${RESET}              $START_DIR"

validate_args
install_build_deps
download_or_copy_source
extract_source
set_version_and_install_dir
patch_arm64_m64_flags
patch_htscodecs_version
clean_previous_builds
build_trinity
run_make_install_test
test_local_build
create_deb_stage
build_deb
install_deb_package
copy_deb_to_cwd
final_report
