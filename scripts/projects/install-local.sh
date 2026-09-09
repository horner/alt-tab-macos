#!/usr/bin/env bash
set -euo pipefail
package_dir="$(cd "$(dirname "$0")" && pwd)"
command -v brew >/dev/null || { echo "Install Homebrew first: https://brew.sh" >&2; exit 1; }
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_AUTOREMOVE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1
cd "$package_dir"
shasum -a 256 --check SHA256SUMS.txt
archive_name="$(awk 'NR == 1 { print $2 }' SHA256SUMS.txt)"
tap_name=horner/projects-local
tap_path="$(brew --repository)/Library/Taps/horner/homebrew-projects-local"
if [[ ! -d "$tap_path" ]]; then
  brew tap-new --no-git "$tap_name"
fi
mkdir -p "$tap_path/Casks"
/usr/bin/ruby -ruri -e '
  template, archive, output = ARGV
  url = "file://" + URI::DEFAULT_PARSER.escape(File.expand_path(archive), /[^A-Za-z0-9\-._~\/]/)
  File.write(output, File.read(template).sub("LOCAL_ARCHIVE_URL", url))
' "$package_dir/Casks/alttab-projects-local.rb" "$package_dir/$archive_name" "$tap_path/Casks/alttab-projects-local.rb"
if brew command trust >/dev/null 2>&1; then
  brew trust --cask "$tap_name/alttab-projects-local"
fi
brew install --cask --require-sha "$tap_name/alttab-projects-local" "$@"
