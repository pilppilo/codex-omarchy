#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="${HOME}/.cache/chatgpt-pkgbuild"
REPO_DIR="${SCRIPT_DIR}/repo"
DB_NAME="chatgpt-local"
UPSTREAM_DEB_URL="https://persistent.oaistatic.com/codex-app-prod/linux/deb/latest/chatgpt_amd64.deb"

mkdir -p "${CACHE_DIR}"

get_current_pkgver() {
  grep -E '^pkgver=' "${SCRIPT_DIR}/PKGBUILD" | cut -d '=' -f2 | tr -d " '"
}

get_upstream_pkgver() {
  # Fetch first 500KB of the upstream deb and extract Version from control.tar.xz in < 1 second
  local ver
  ver=$(curl -s -r 0-500000 "${UPSTREAM_DEB_URL}" | \
        bsdtar -xOf - control.tar.xz 2>/dev/null | \
        bsdtar -xOf - control 2>/dev/null | \
        grep -i '^version:' | awk '{print $2}' | tr -d '\r\n')
  if [ -z "${ver}" ]; then
    echo "ERROR: Failed to extract upstream version from ${UPSTREAM_DEB_URL}" >&2
    return 1
  fi
  echo "${ver}"
}

cmd_check() {
  local current upstream
  current="$(get_current_pkgver)"
  echo "PKGBUILD version : ${current}"
  echo "Checking upstream version at ${UPSTREAM_DEB_URL}..."
  upstream="$(get_upstream_pkgver)"
  echo "Upstream version : ${upstream}"
  if [ "${current}" = "${upstream}" ]; then
    echo "Status: Up-to-date."
    return 0
  else
    echo "Status: UPDATE AVAILABLE -> ${upstream}"
    return 2
  fi
}

cmd_update_pkgbuild() {
  local current upstream
  current="$(get_current_pkgver)"
  upstream="$(get_upstream_pkgver)"

  echo "Updating PKGBUILD from ${current} to ${upstream}..."
  sed -i -E "s/^pkgver=.*/pkgver=${upstream}/" "${SCRIPT_DIR}/PKGBUILD"
  sed -i -E "s/^pkgrel=.*/pkgrel=1/" "${SCRIPT_DIR}/PKGBUILD"

  echo "Computing sha256 checksum..."
  local deb_file="${CACHE_DIR}/chatgpt_${upstream}_amd64.deb"
  if [ ! -f "${deb_file}" ]; then
    echo "Downloading ${UPSTREAM_DEB_URL} to ${deb_file}..."
    curl -sL "${UPSTREAM_DEB_URL}" -o "${deb_file}"
  fi

  local sum
  sum=$(sha256sum "${deb_file}" | awk '{print $1}')
  sed -i -E "s/^sha256sums=\(.*?\)/sha256sums=('${sum}')/" "${SCRIPT_DIR}/PKGBUILD"
  echo "Updated sha256sum: ${sum}"

  # Reuse downloaded deb in workspace so makepkg does not download a duplicate copy
  local local_deb="${SCRIPT_DIR}/chatgpt_${upstream}_amd64.deb"
  if [ ! -f "${local_deb}" ]; then
    cp -l "${deb_file}" "${local_deb}" 2>/dev/null || cp "${deb_file}" "${local_deb}"
  fi
}

cmd_build() {
  local current upstream
  current="$(get_current_pkgver)"
  upstream="$(get_upstream_pkgver)"

  if [ "${current}" != "${upstream}" ] || [ "${FORCE:-0}" = "1" ]; then
    cmd_update_pkgbuild
  else
    echo "PKGBUILD is already at latest version (${upstream})."
  fi

  echo "Building package with makepkg..."
  (cd "${SCRIPT_DIR}" && makepkg -f --nodeps)

  if [ "${CLEAN_AFTER_BUILD:-0}" = "1" ]; then
    echo "Cleaning up past files..."
    cmd_clean --keep 1
  fi

  if [ "${UPDATE_REPO:-0}" = "1" ]; then
    cmd_repo
  fi
}

cmd_install() {
  local current upstream
  current="$(get_current_pkgver)"
  upstream="$(get_upstream_pkgver)"

  if [ "${current}" != "${upstream}" ] || [ "${FORCE:-0}" = "1" ]; then
    cmd_update_pkgbuild
  fi

  echo "Building and installing package with makepkg -si..."
  (cd "${SCRIPT_DIR}" && makepkg -si)

  if [ "${CLEAN_AFTER_BUILD:-0}" = "1" ]; then
    echo "Cleaning up past files..."
    cmd_clean --keep 1
  fi
}

cmd_repo() {
  mkdir -p "${REPO_DIR}"
  local pkg_file
  pkg_file=$(ls -t "${SCRIPT_DIR}"/chatgpt-*.pkg.tar.zst 2>/dev/null | head -n 1 || true)
  if [ -z "${pkg_file}" ]; then
    echo "No built package found. Building now..."
    cmd_build
    pkg_file=$(ls -t "${SCRIPT_DIR}"/chatgpt-*.pkg.tar.zst 2>/dev/null | head -n 1)
  fi

  local target_pkg="${REPO_DIR}/$(basename "${pkg_file}")"
  if [ "${pkg_file}" != "${target_pkg}" ]; then
    mv -f "${pkg_file}" "${REPO_DIR}/"
  fi

  echo "Adding $(basename "${target_pkg}") to local repo ${DB_NAME}..."
  repo-add -R "${REPO_DIR}/${DB_NAME}.db.tar.zst" "${target_pkg}"

  # Keep only latest 2 built packages in repo directory
  find "${REPO_DIR}" -maxdepth 1 -name 'chatgpt-*.pkg.tar.zst' | sort -V | head -n -2 | xargs -r rm -f

  echo "Local repository updated at ${REPO_DIR}"
  echo "Database: ${REPO_DIR}/${DB_NAME}.db.tar.zst"
}

cmd_auto() {
  local current upstream
  current="$(get_current_pkgver)"
  upstream="$(get_upstream_pkgver)"

  if [ "${current}" != "${upstream}" ]; then
    echo "New version detected: ${upstream} (current: ${current}). Building..."
    cmd_update_pkgbuild
    (cd "${SCRIPT_DIR}" && makepkg -f --nodeps)
    cmd_repo
    echo "Cleaning up past files and build artifacts..."
    cmd_clean --keep 1 --quiet
    if command -v notify-send >/dev/null 2>&1; then
      notify-send "ChatGPT Update Ready" "chatgpt ${upstream} built in local repo. Run 'sudo pacman -Syu' to install." -i chatgpt || true
    fi
  else
    echo "ChatGPT is up-to-date (${current})."
  fi
}

cmd_clean() {
  local dry_run=0
  local clean_all=0
  local keep_count=1
  local quiet=0

  while [ $# -gt 0 ]; do
    case "$1" in
      -n|--dry-run)
        dry_run=1
        shift
        ;;
      -a|--all)
        clean_all=1
        keep_count=0
        shift
        ;;
      -k|--keep)
        if [ -z "${2:-}" ] || ! [[ "$2" =~ ^[0-9]+$ ]]; then
          echo "Error: --keep requires a non-negative integer argument" >&2
          return 1
        fi
        keep_count="$2"
        if [ "${keep_count}" -eq 0 ]; then
          clean_all=1
        fi
        shift 2
        ;;
      -q|--quiet)
        quiet=1
        shift
        ;;
      *)
        echo "Unknown clean option: $1" >&2
        usage
        return 1
        ;;
    esac
  done

  local current_pkgver
  current_pkgver="$(get_current_pkgver)"

  local targets=()
  local -A seen_targets=()

  _add_target() {
    local item="$1"
    if [ -e "${item}" ] && [ -z "${seen_targets["${item}"]:-}" ]; then
      seen_targets["${item}"]=1
      targets+=("${item}")
    fi
  }

  # 1. Intermediate build directories
  _add_target "${SCRIPT_DIR}/src"
  _add_target "${SCRIPT_DIR}/pkg"

  _collect_old_files() {
    local dir="$1"
    local pattern="$2"
    local keep="$3"
    [ ! -d "${dir}" ] && return 0

    local matched_files=()
    while IFS= read -r f; do
      [ -n "${f}" ] && matched_files+=("${f}")
    done < <(find "${dir}" -maxdepth 1 -name "${pattern}" 2>/dev/null | sort -V)

    local total=${#matched_files[@]}
    [ "${total}" -eq 0 ] && return 0

    if [ "${clean_all}" -eq 1 ] || [ "${keep}" -le 0 ]; then
      for f in "${matched_files[@]}"; do
        _add_target "${f}"
      done
    elif [ "${total}" -gt "${keep}" ]; then
      local remove_count=$((total - keep))
      for ((i=0; i<remove_count; i++)); do
        local cand="${matched_files[i]}"
        if [[ "${cand}" != *"${current_pkgver}"* ]]; then
          _add_target "${cand}"
        fi
      done
    fi
  }

  _collect_old_packages() {
    local dir="$1"
    local keep="$2"
    [ ! -d "${dir}" ] && return 0

    local matched_files=()
    while IFS= read -r f; do
      [ -n "${f}" ] && matched_files+=("${f}")
    done < <(find "${dir}" -maxdepth 1 \( -name 'chatgpt-*.pkg.tar.zst' -o -name 'chatgpt-*.pkg.tar.xz' \) 2>/dev/null | sort -V)

    local total=${#matched_files[@]}
    [ "${total}" -eq 0 ] && return 0

    if [ "${clean_all}" -eq 1 ] || [ "${keep}" -le 0 ]; then
      for f in "${matched_files[@]}"; do
        _add_target "${f}"
      done
    elif [ "${total}" -gt "${keep}" ]; then
      local remove_count=$((total - keep))
      for ((i=0; i<remove_count; i++)); do
        local cand="${matched_files[i]}"
        if [[ "${cand}" != *"${current_pkgver}"* ]]; then
          _add_target "${cand}"
        fi
      done
    fi
  }

  # 2. Workspace downloaded .deb files
  _collect_old_files "${SCRIPT_DIR}" "chatgpt_*_amd64.deb" "${keep_count}"

  # 3. Cache directory .deb files
  _collect_old_files "${CACHE_DIR}" "chatgpt_*_amd64.deb" "${keep_count}"

  # 4. Workspace built packages (.pkg.tar.zst and .pkg.tar.xz)
  _collect_old_packages "${SCRIPT_DIR}" "${keep_count}"

  # 5. Local repo directory packages (if repo exists)
  if [ -d "${REPO_DIR}" ]; then
    _collect_old_packages "${REPO_DIR}" "${keep_count}"
  fi

  if [ ${#targets[@]} -eq 0 ]; then
    if [ "${quiet}" -eq 0 ]; then
      echo "No past files or build artifacts to clean up."
    fi
    return 0
  fi

  local total_size
  total_size=$(du -ch "${targets[@]}" 2>/dev/null | tail -n 1 | awk '{print $1}')

  if [ "${dry_run}" -eq 1 ]; then
    echo "Dry-run: The following items would be removed (keep: ${keep_count}, all: ${clean_all}):"
    for item in "${targets[@]}"; do
      local sz
      sz=$(du -sh "${item}" 2>/dev/null | awk '{print $1}')
      local display_name="${item#"${SCRIPT_DIR}/"}"
      echo "  - ${display_name} (${sz})"
    done
    echo "Estimated disk space to be reclaimed: ${total_size}"
    echo "No files were deleted."
    return 0
  fi

  if [ "${quiet}" -eq 0 ]; then
    echo "Cleaning up past files and build artifacts (keep: ${keep_count}, all: ${clean_all}):"
  fi

  for item in "${targets[@]}"; do
    if [ "${quiet}" -eq 0 ]; then
      local sz
      sz=$(du -sh "${item}" 2>/dev/null | awk '{print $1}')
      local display_name="${item#"${SCRIPT_DIR}/"}"
      echo "  Removing: ${display_name} (${sz})"
    fi
    rm -rf "${item}"
  done

  if [ "${quiet}" -eq 0 ]; then
    echo "Cleanup complete: Reclaimed ${total_size} of disk space."
  fi
}

usage() {
  cat <<EOF
Usage: $0 [command] [options]

Commands:
  check        Check upstream version vs PKGBUILD in <1 second (byte-range query)
  bump         Update PKGBUILD with latest upstream version and sha256 checksum
  build        Bump PKGBUILD if needed and build package with 'makepkg -f'
  install      Bump PKGBUILD if needed and build/install with 'makepkg -si'
  repo         Add latest built package to local pacman repo (${REPO_DIR})
  clean        Clean up past source files, build directories, and old packages
  auto         Check, build, update repo, and clean past files (used by systemd timer)
  help         Show this help message

Clean Options (used with 'clean'):
  -n, --dry-run   Preview files to be deleted and reclaimed space without deleting
  -a, --all       Clean all build artifacts and cached debs (including current version)
  -k, --keep <N>  Number of recent package versions to retain (default: 1)
  -q, --quiet     Suppress non-essential progress output

Default (no arguments) runs 'check'.
EOF
}

case "${1:-check}" in
  check)
    cmd_check
    ;;
  bump|update)
    cmd_update_pkgbuild
    ;;
  build)
    FORCE="${FORCE:-0}" cmd_build
    ;;
  install)
    FORCE="${FORCE:-0}" cmd_install
    ;;
  repo)
    cmd_repo
    ;;
  clean)
    shift
    cmd_clean "$@"
    ;;
  auto)
    cmd_auto
    ;;
  help|--help|-h)
    usage
    ;;
  *)
    echo "Unknown command: $1" >&2
    usage
    exit 1
    ;;
esac
