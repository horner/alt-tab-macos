cask "alttab-projects" do
  version "0.1.3"
  sha256 "aab30ca9fd9cd007c3cc0971828626a8564d3c9e9d2366a507cf4907502f8082"

  url "https://github.com/horner/alt-tab-macos/releases/download/projects-v0.1.3/AltTabProjects.zip"
  name "AltTabProjects"
  desc "Window and Desktop switcher with saved Projects"
  homepage "https://github.com/horner/alt-tab-macos"

  depends_on :macos

  app "AltTabProjects.app"
end
