# Changelog

## 0.1.0 - 2026-09-02

First public build of the Godot 4 remake of Warblade 1.34: the complete
100-level campaign with endless continuation past level 100, the retail
big bosses at levels 25, 50, 75, and 100, cadence and mode-three shops, Time
Trial, simultaneous couch co-op, player-hosted online co-op through the lobby
server with nicknames, global chat, and talents, and the extracted retail
presentation (graphics, music, samples, voices).

### Downloads

- `WarbladeRemake-0.1.0-macos-universal.zip`: macOS, one universal app for
  Apple silicon and Intel, ad-hoc signed and not notarized
- `WarbladeRemake-0.1.0-windows-x86_64.zip`: Windows 10/11 x86_64, a single
  `Warblade.exe`, unsigned
- `WarbladeRemake-0.1.0-linux-x86_64.tar.gz`: Linux x86_64 (glibc 2.28 or
  newer, OpenGL 3.3), a single `Warblade.x86_64`, unsigned
- `SHA256SUMS.txt`: checksums of the three archives

### First run

- macOS blocks the first launch because the app is not notarized: open System
  Settings > Privacy & Security, find the message about Warblade near the
  bottom, click Open Anyway, and confirm. Terminal equivalent:
  `xattr -dr com.apple.quarantine /path/to/Warblade.app`.
- Windows SmartScreen shows "Windows protected your PC" for the unsigned
  executable: click More info, then Run anyway. Windows Firewall asks for
  permission the first time you host an online game.
- Linux: extract the archive, `chmod +x Warblade.x86_64` if your extractor
  dropped the executable bit, and run it.
- Saves, profiles, settings, the talent cache, and the device identity live in
  `~/Library/Application Support/Warblade Remake` (macOS),
  `%APPDATA%\Warblade Remake` (Windows), or `~/.local/share/Warblade Remake`
  (Linux).
- Online play needs outbound TCP 7400 and UDP 7401 to the lobby server.
  Hosting a game needs inbound UDP 42000 (the default HOST PORT) through UPnP
  or a manual port forward; solo, Time Trial, and couch co-op work offline.

### Known limitations

- The Windows and Linux builds were not run on real Windows or Linux hardware
  before this release. They are exported from the same source as the macOS
  build; the Linux binary passed its headless presentation and packaged-client
  smokes inside a linux/amd64 container, the Windows executable only its
  header and resource checks. Please report problems on GitHub.
- Windows and Linux builds are unsigned, so SmartScreen and some antivirus
  tools warn about an unknown publisher.
- There is no anti-cheat; the lobby server trusts self-reported match results
  and talent credits.
- The lobby link is plain `ws://`, so nicknames, chat, and the device key
  travel in cleartext.
- Built with Godot 4.7.2 stable; match content version 12, transport protocol
  version 8.

### Rights

Warblade and its original assets remain the property of the original game's
author. These builds embed the extracted retail material under the
authorization recorded in the app metadata; the source repository never
contains it.
