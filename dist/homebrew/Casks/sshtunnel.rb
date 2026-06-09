cask "sshtunnel" do
  version "1.5.3"
  sha256 "45c71648a170f867483601c64eea36b405e7193e5ae792c6a023ba3bb229991d"

  url "https://github.com/TypoStudio/ssh-tunnel-for-macos/releases/download/v#{version}/SSHTunnel-#{version}.dmg"
  name "SSHTunnel"
  desc "Manager for SSH tunnels and connection configs"
  homepage "https://github.com/TypoStudio/ssh-tunnel-for-macos"

  auto_updates false

  app "SSHTunnel.app"

  zap trash: "~/Library/Preferences/kr.typostudio.sshtunnel.plist"
end
