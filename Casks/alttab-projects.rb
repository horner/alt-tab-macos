cask "alttab-projects" do
  version "0.1.4"
  sha256 "68678817d2e571bee2816abccd48b5907fb510bbb13ac4eab18cff153f538923"

  url "https://github.com/horner/alt-tab-macos/releases/download/projects-v0.1.4/AltTabProjects.zip"
  name "AltTabProjects"
  desc "Window and Desktop switcher with saved Projects"
  homepage "https://github.com/horner/alt-tab-macos"

  depends_on macos: ">= :monterey"

  app "AltTabProjects.app"
end
