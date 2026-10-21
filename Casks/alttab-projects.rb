cask "alttab-projects" do
  version "1.0.7"
  sha256 "772b7548f9b1024827934f26d30887c4d4e343532b26a59bd927b0dc509e6da7"

  url "https://github.com/horner/alt-tab-macos/releases/download/projects-v1.0.7/AltTabProjects.zip"
  name "AltTabProjects"
  desc "Window and Desktop switcher with saved Projects"
  homepage "https://github.com/horner/alt-tab-macos"

  auto_updates true
  depends_on macos: :monterey

  app "AltTabProjects.app"
end
