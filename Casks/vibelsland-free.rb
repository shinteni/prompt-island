cask "vibelsland-free" do
  version "0.1.0"
  sha256 "b8ae6ea245d4720c1c9389c2ce95a582df9005866fda3522279058eb40b40af5"

  url "https://github.com/shinteni/prompt-island/releases/download/v#{version}/Vibelsland-Free-#{version}-macos.zip"
  name "Vibelsland Free"
  desc "Local-first floating island showing Claude Code and Codex session status"
  homepage "https://shinteni.github.io/prompt-island/"

  depends_on macos: :sonoma
  depends_on arch: :arm64

  app ">_ - island.app"

  uninstall quit: "free.vibelsland.macos"

  zap trash: [
    "~/.vibelsland-free",
    "~/Library/Application Support/VibelslandFree",
    "~/Library/Logs/VibelslandFree",
  ]

  caveats <<~EOS
    Vibelsland Free 0.1.0 is ad-hoc signed and not notarized, so macOS
    Gatekeeper asks for manual confirmation on first launch. Steps:
    https://shinteni.github.io/prompt-island/install.html
  EOS
end
