cask "sshtunnel" do
  version "1.5.2"
  sha256 "458692aa94c080840e90593988a608a24edf7fdba7cbe33593ef2415541d0fbc"

  url "https://github.com/TypoStudio/ssh-tunnel-for-macos/releases/download/v#{version}/SSHTunnel-#{version}.dmg"
  name "SSHTunnel"
  desc "Manager for SSH tunnels and connection configs"
  homepage "https://github.com/TypoStudio/ssh-tunnel-for-macos"

  auto_updates false

  app "SSHTunnel.app"

  zap trash: "~/Library/Preferences/kr.typostudio.sshtunnel.plist"
end
