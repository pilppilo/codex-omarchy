# Maintainer: weakandslowdev <weakandslowdev@outlook.com>
pkgname=chatgpt
pkgver=26.831.20005
pkgrel=1
pkgdesc="ChatGPT Desktop application by OpenAI"
arch=('x86_64')
url="https://developers.openai.com/codex/app"
license=('custom:Proprietary')
depends=(
  'alsa-lib'
  'at-spi2-core'
  'cairo'
  'dbus'
  'expat'
  'gcc-libs'
  'gdk-pixbuf2'
  'glib2'
  'glibc'
  'gtk3'
  'libcups'
  'libdrm'
  'libnotify'
  'libsecret'
  'libusb'
  'libx11'
  'libxcb'
  'libxcomposite'
  'libxdamage'
  'libxext'
  'libxfixes'
  'libxkbcommon'
  'libxrandr'
  'libxss'
  'libxtst'
  'mesa'
  'nspr'
  'nss'
  'pango'
  'systemd-libs'
  'xdg-utils'
)
optdepends=(
  'apparmor: AppArmor profile support'
  'trash-cli: desktop trash integration'
)
options=('!strip')

source=("${pkgname}_${pkgver}_amd64.deb::https://persistent.oaistatic.com/codex-app-prod/linux/deb/latest/chatgpt_amd64.deb")
sha256sums=('1cef3e8405f695b7f03fd1b072460d1185b7d53e24b727e3be25613e68a751aa')

package() {
  # Extract data archive from deb directly to $pkgdir
  bsdtar -xf "${pkgname}_${pkgver}_amd64.deb" data.tar.xz
  bsdtar -xf data.tar.xz -C "${pkgdir}"

  # Fix chrome-sandbox permissions if present
  if [ -f "${pkgdir}/usr/lib/chatgpt/chrome-sandbox" ]; then
    chmod 4755 "${pkgdir}/usr/lib/chatgpt/chrome-sandbox"
  fi

  # Install mandatory license per Arch non-free packaging guidelines
  install -dm755 "${pkgdir}/usr/share/licenses/${pkgname}"
  if [ -f "${pkgdir}/usr/share/doc/chatgpt/copyright" ]; then
    cp "${pkgdir}/usr/share/doc/chatgpt/copyright" "${pkgdir}/usr/share/licenses/${pkgname}/LICENSE"
  else
    echo "Proprietary license - OpenAI" > "${pkgdir}/usr/share/licenses/${pkgname}/LICENSE"
  fi
}
