cask "alttab-projects" do
  version "0.1.2"
  sha256 "8d7977ab3bf95c9a0f58c3cb786990c401b6702231fa8296479f4b7609446bcf"

  url "https://github.com/horner/alt-tab-macos/releases/download/projects-v0.1.2/AltTabProjects.zip"
  name "AltTabProjects"
  desc "Window and Desktop switcher with saved Projects"
  homepage "https://github.com/horner/alt-tab-macos"

  depends_on :macos

  app "AltTabProjects.app"
end
