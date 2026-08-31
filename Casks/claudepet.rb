cask "claudepet" do
  version "1.2.3"
  sha256 "35efc5630334be92f9bfa7538c40b4834883b27d6e0360380419f283bf7f2d34"

  url "https://github.com/MOHAMEDSAMEER78/claudepet/releases/download/v#{version}/ClaudePet-#{version}.zip"
  name "ClaudePet"
  desc "Menu-bar pet that shows live Claude Code session state"
  homepage "https://mohamedsameer78.github.io/claudepet/"

  depends_on macos: ">= :ventura"

  app "ClaudePet.app"

  zap trash: [
    "~/.claude/pet",
    "~/Library/Preferences/ai.armada.claudepet.plist",
  ]
end
