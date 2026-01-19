cask "sanehosts" do
  version "1.0.0"
  sha256 "TODO:ADD_SHA256"

  url "https://github.com/stephanjoseph/SaneHosts/releases/download/v#{version}/SaneHosts-#{version}.dmg"
  name "SaneHosts"
  desc "Modern hosts file manager for macOS"
  homepage "https://sanehosts.com"

  depends_on macos: ">= :sonoma"

  app "SaneHosts.app"

  zap trash: [
    "~/Library/Application Support/SaneHosts",
    "~/Library/Preferences/com.sanehosts.app.plist",
    "~/Library/Caches/com.sanehosts.app",
  ]
end
