cask "vibelsland-free" do
  version "0.3.4"
  sha256 "45999d9117eaf0cd804b842201a6a9972d9f49fedcc4a4d2cde589695f3a878f"

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
    Vibelsland Free 0.3.4 is ad-hoc signed and not notarized, so macOS
    Gatekeeper asks for manual confirmation on first launch. Steps:
    https://shinteni.github.io/prompt-island/install.html
  EOS
end
