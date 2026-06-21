cask "scratchmate" do
  version "0.1.0"

  # Digest of the published DMG. Until the first release ships, this stays
  # :no_check. To pin it: run Scripts/release.sh <version> (it prints the line
  # "==> Cask sha256 (v<version>): <digest>", the same value make-dmg.sh writes
  # to dist/ScratchMate-v<version>-macOS.dmg.sha256), then replace :no_check with
  # that digest. Always bump version and sha256 together, never one without the other.
  sha256 :no_check

  # The artifact name MUST match what Scripts/make-dmg.sh produces
  # (ScratchMate-v#{version}-macOS.dmg). Any mismatch breaks cask installation.
  url "https://github.com/leonardocandiani/scratchmate/releases/download/v#{version}/ScratchMate-v#{version}-macOS.dmg"

  name "ScratchMate"
  desc "Programmable, ephemeral scratchpad for developers"
  homepage "https://github.com/leonardocandiani/scratchmate"

  # Requires macOS 14 (Sonoma), aligned with the deployment target in Package.swift.
  depends_on macos: ">= :sonoma"

  app "ScratchMate.app"

  # ScratchMate is ad-hoc signed, not notarized, so macOS quarantines the download.
  # Strip the quarantine flag after install so the app launches without a
  # Gatekeeper block. Remove this once the DMG is notarized.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-rd", "com.apple.quarantine", "#{appdir}/ScratchMate.app"],
                   sudo: false
  end

  zap trash: [
    "~/Library/Preferences/com.leonardolima.scratchmate.plist",
    "~/Library/Application Support/ScratchMate",
  ]

  caveats <<~EOS
    ScratchMate is not signed with an Apple Developer ID certificate or notarized.
    If macOS blocks the app on first launch, run:
      xattr -rd com.apple.quarantine /Applications/ScratchMate.app
  EOS
end
