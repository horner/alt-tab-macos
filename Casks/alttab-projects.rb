cask "alttab-projects" do
  version "1.0.8"
  sha256 "08e727618b940839349fb6ec212c2db15f4d135bb20fc4da06ecca2508aeed2a"

  url "https://github.com/horner/alt-tab-macos/releases/download/projects-v1.0.8/AltTabProjects.zip"
  name "AltTabProjects"
  desc "Window and Desktop switcher with saved Projects"
  homepage "https://github.com/horner/alt-tab-macos"

  auto_updates true
  depends_on macos: :monterey

  app "AltTabProjects.app"
end
