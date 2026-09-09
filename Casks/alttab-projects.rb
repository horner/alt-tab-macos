cask "alttab-projects" do
  version "0.1.0"
  sha256 "ab370a264cf2c73cb662f9accb611bdca9b9a066dd1fe341afe85a0bb524a578"

  url "https://github.com/horner/alt-tab-macos/releases/download/projects-v0.1.0/AltTabProjects.zip"
  name "AltTabProjects"
  desc "Window and Desktop switcher with saved Projects"
  homepage "https://github.com/horner/alt-tab-macos"

  depends_on :macos

  app "AltTabProjects.app"
end
