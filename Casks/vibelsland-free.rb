cask "vibelsland-free" do
  version "0.2.1"
  sha256 "cb19ce0cf320ff016d7426f6edcaef7f5438e237a37ddca7884f65650df29dbb"

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
    Vibelsland Free 0.2.1 is ad-hoc signed and not notarized, so macOS
    Gatekeeper asks for manual confirmation on first launch. Steps:
    https://shinteni.github.io/prompt-island/install.html
  EOS
end
