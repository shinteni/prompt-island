cask "vibelsland-free" do
  version "0.2.2"
  sha256 "9a3971677e9c9dbf5dc78f32e1f603d46f83128958f07b2ec3155ab63b7dc654"

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
    Vibelsland Free 0.2.2 is ad-hoc signed and not notarized, so macOS
    Gatekeeper asks for manual confirmation on first launch. Steps:
    https://shinteni.github.io/prompt-island/install.html
  EOS
end
