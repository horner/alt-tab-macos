cask "alttab-projects" do
  version "1.0.6"
  sha256 "da7b812a9024c8fb1016b1058ea0a162dcec6d017ed93c52a58d7b612c89f35a"

  url "https://github.com/horner/alt-tab-macos/releases/download/projects-v1.0.6/AltTabProjects.zip"
  name "AltTabProjects"
  desc "Window and Desktop switcher with saved Projects"
  homepage "https://github.com/horner/alt-tab-macos"

  auto_updates true
  depends_on macos: :monterey

  app "AltTabProjects.app"
end
