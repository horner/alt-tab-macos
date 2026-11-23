cask "alttab-projects" do
  version "1.0.9"
  sha256 "d0a073df7a59fe60c517d1dd75906b7ae4be0cd5e44e11574ac2b3ba52043282"

  url "https://github.com/horner/alt-tab-macos/releases/download/projects-v1.0.9/AltTabProjects.zip"
  name "AltTabProjects"
  desc "Window and Desktop switcher with saved Projects"
  homepage "https://github.com/horner/alt-tab-macos"

  auto_updates true
  depends_on macos: :monterey

  app "AltTabProjects.app"
end
