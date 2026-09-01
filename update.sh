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
    if command -v notify-send >/dev/null 2>&1; then
      notify-send "ChatGPT Update Ready" "chatgpt ${upstream} built in local repo. Run 'sudo pacman -Syu' to install." -i chatgpt || true
    fi
  else
    echo "ChatGPT is up-to-date (${current})."
  fi
}

usage() {
  cat <<EOF
Usage: $0 [command]

Commands:
  check        Check upstream version vs PKGBUILD in <1 second (byte-range query)
  bump         Update PKGBUILD with latest upstream version and sha256 checksum
  build        Bump PKGBUILD if needed and build package with 'makepkg -f'
  install      Bump PKGBUILD if needed and build/install with 'makepkg -si'
  repo         Add latest built package to local pacman repo (${REPO_DIR})
  auto         Check, build and update repo if update exists (used by systemd timer)
  help         Show this help message

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
