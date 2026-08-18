cask "sshtunnel" do
  version "1.6.0"
  sha256 "4821c117982b7955cdebb17d3508333dbb181dfa7b215c733d0b1c71de6fe190"

  url "https://github.com/TypoStudio/ssh-tunnel-for-macos/releases/download/v#{version}/SSHTunnel-#{version}.dmg"
  name "SSHTunnel"
  desc "Manager for SSH tunnels and connection configs"
  homepage "https://github.com/TypoStudio/ssh-tunnel-for-macos"

  auto_updates false

  app "SSHTunnel.app"

  zap trash: "~/Library/Preferences/kr.typostudio.sshtunnel.plist"
end
