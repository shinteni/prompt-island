cask "vibelsland-free" do
  version "0.3.0"
  sha256 "01387eee3133efb8c927205e7be8456114b6cdd87573bee36c714a8a0783d048"

  url "https://github.com/shinteni/prompt-island/releases/download/v#{version}/Vibelsland-Free-#{version}-macos.zip"
  name "Vibelsland Free"
  desc "Local-first floating island showing Claude Code and Codex session status"
  homepage "https://shinteni.github.io/prompt-island/"

  depends_on macos: :sonoma

  app ">_ - island.app"

  uninstall quit: "free.vibelsland.macos"

  zap trash: [
    "~/.vibelsland-free",
    "~/Library/Application Support/VibelslandFree",
    "~/Library/Logs/VibelslandFree",
  ]

  caveats <<~EOS
    Vibelsland Free 0.3.0 is ad-hoc signed and not notarized, so macOS
    Gatekeeper asks for manual confirmation on first launch. Steps:
    https://shinteni.github.io/prompt-island/install.html
  EOS
end
