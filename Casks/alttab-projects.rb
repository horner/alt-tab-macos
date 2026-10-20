cask "alttab-projects" do
  version "1.0.5"
  sha256 "12bb3f79678296726491ac7b74d4bac90adb4b3fb8e4b177053f158a6c496b90"

  url "https://github.com/horner/alt-tab-macos/releases/download/projects-v1.0.5/AltTabProjects.zip"
  name "AltTabProjects"
  desc "Window and Desktop switcher with saved Projects"
  homepage "https://github.com/horner/alt-tab-macos"

  depends_on macos: :monterey

  app "AltTabProjects.app"
end
