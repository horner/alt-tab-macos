cask "alttab-projects" do
  version "0.1.1"
  sha256 "92851b49fdaef0d0d0c0670c0b431cc8d9ed130cd90d2ca03caa341f8ad21f59"

  url "https://github.com/horner/alt-tab-macos/releases/download/projects-v0.1.1/AltTabProjects.zip"
  name "AltTabProjects"
  desc "Window and Desktop switcher with saved Projects"
  homepage "https://github.com/horner/alt-tab-macos"

  depends_on :macos

  app "AltTabProjects.app"
end
