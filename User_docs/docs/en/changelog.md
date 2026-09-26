---
outline: deep
---

# Changelog

## v1.8.2 (In Development)

### Important Changes

- **Container data now uses mount migration**: directories under `~/Library/Containers/` and `~/Library/Group Containers/` no longer use symbolic links. AppPorts creates dedicated volumes on an APFS external drive and mounts them at the original directories, without changing app signatures. An APFS drive is required; allow Removable Volumes access on first launch. See [Mount Migration](/en/datamigrae/mount-migration).
- **Sandboxed apps are no longer re-signed**: the right-click menu, "Re-sign after migration" switch, and login re-signing script skip sandboxed apps. Re-signing by older versions may prevent them from opening on macOS 27; see [Upgrading to macOS 27](/en/macos-27).
- **Fixed "Restore Original Signature"**: a complete original app is backed up before re-signing, and a verified working copy safely replaces the current app. Original signatures and entitlements can be restored without the developer's private key. Legacy records can use an official original copy of the same version. Updated apps and damaged backups are not forcibly overwritten.
- **Automatic detection and repair guidance for replaced signatures**: the app list shows a red "Signature replaced" badge and reminds you once at startup. "Show repair steps" opens a panel guiding you through restoring data, moving the app back, reinstalling, and optionally using mount migration, without deleting data. The badge disappears after reinstallation restores the signature. Scans preserve recovery materials; successful restoration through AppPorts cleans up the backup.
- **Classic data migration mode**: a new switch in Settings is off by default and requires risk confirmation. It restores the 1.8.1 symbolic-link and re-signing workflow for users already relying on it. If your drive is not APFS, keeping things as they are is recommended instead of enabling this mode.
- "Auto Re-sign at Login" is off for new installations. Existing users with an installed login agent keep their setting.
- "Normalize", "Relink", and "Link Details" are disabled for container directories outside classic mode, preventing symbolic links from being recreated.

### Improvements

- **"Mount migration" starts with a check that makes no changes, then gives relevant guidance**: unencrypted APFS storage shows the space you can free, the first-launch permission prompt, and the need to keep the drive connected. For exFAT / NTFS / HFS+, encryption, insufficient space, or a disconnected drive, AppPorts explains the reason and offers actions such as "Keep As Is", "Choose Another Location", and "View Preparation Guide" without changing anything. Readiness checks in the welcome screen and Settings use the same guidance and no longer steer non-APFS users toward classic mode.
- **Data volumes are hidden in Finder**: newly created volumes do not automatically mount under `/Volumes`, and mounting uses `nobrowse`. Volumes mounted by earlier versions are hidden in place at the next launch or drive connection, without unmounting.
- **Encrypted APFS drives are not yet supported for mount migration**: new volumes do not inherit the original volume's password. AppPorts stops and explains instead of silently creating an unencrypted volume.
- **Free-space checks before migration and restoration**: insufficient external or local space stops the operation before volume creation or copying.
- **Safer restoration**: only the empty mount point is deleted after unmounting, without recursive deletion. Staging directories now use hidden names. If the final step cannot complete, the external volume and record remain intact and AppPorts reports the local copy's location.
- **Only operate on AppPorts volumes**: mount, unmount, and restore verify the volume identity at the mount point. Operations do not start without the lock shared with the login agent. An unreadable migration record file is never treated as an empty record and overwritten.
- **Automatic login-agent path updates**: each launch checks the agent's executable path and updates it after AppPorts is moved or upgraded. Running directly from a DMG or Downloads through a temporary App Translocation path blocks new mount migrations and asks you to move AppPorts to Applications first.
- Mount migration retries with the system administrator password prompt on systems requiring elevated privileges, such as macOS 12.
- Container volumes remount after login and when a drive connects while AppPorts is running. The login agent also watches `/Volumes` to mount before login apps start. A cross-process lock prevents the agent and AppPorts from competing for mount points during migration or restoration.
- **The login agent is no longer deferred behind login items**: it uses `KeepAlive` to declare that it needs to run, restarting only after failure, and removes `ProcessType: Background`. The user domain stays in on-demand-only mode for a period after login; the old definition could be delayed about 20 seconds while login apps started in 3 seconds.
- **Volumes mounted automatically by macOS are remounted correctly**: when a volume is already mounted under `/Volumes`, `diskutil mount -mountPoint` can ignore the requested path, print `mounted`, and return 0. This occurred on 2026-09-21 and 09-23: the command succeeded while the intended mount point remained empty, so WeChat read an empty directory. AppPorts now verifies the actual destination after every mount and, if necessary, unmounts from `/Volumes` and retries, up to 3 rounds.
- **Removed the most expensive boot-time `diskutil` query**: macOS first mounts volumes under `/Volumes/<卷名>`. The agent now identifies them using `statfs` and a volume-root marker in microseconds, avoiding a `diskutil info` query measured at 9 seconds. On a real Mac, a round from locating the volume to completing its mount now needs only `unmount` and `mount`, taking about 1 second.
- **The login agent keeps waiting for slow drives**: it watches `/Volumes` within the process and retries after real changes. Tests measured about 1 second from volume appearance to completed mounting. With no events, it checks every 20 seconds as a fallback, over a total 180-second window. It does not hold the shared lock while waiting.
- **Idle login-agent runs no longer flood logs**: launchd matches `WatchPaths` using FSEvents path prefixes, so any write on an external drive can wake the agent even when no action is needed. An idle run now writes only 3 lines; detailed per-record logs appear only for actual mounting, offline volumes, or failures.
- **Halved `diskutil` calls in the mounting path**: queries per volume drop from 4 to 2 by checking availability and the current mount location in one `diskutil info` call. Each query can take around a second during a busy boot, saving several seconds.
- **Spotlight no longer indexes data volumes**: volume creation writes `.metadata_never_index` at the root and removes any `.Spotlight-V100` already created, which totaled 110 MB across two tested WeChat volumes. Older migrated volumes receive the marker on their next mount. It stays with the volume and is not copied back to the local directory during restoration.
- Fixed incorrect container matches when a Bundle ID ends with generic words such as `mac` or `desktop`, for example Termius listing QQ Music containers.
- Fixed missing subdirectory scans when container paths appear in `/private/var` form.

## v1.8.0

### New Features

- Added custom local scan directories: the "Mac Local Apps" header now has a "+" button to add extra local app scan directories. Useful for tools like JetBrains Toolbox and Steam that install apps outside `/Applications`. Added directories are persisted and automatically monitored for changes (#48).
- Added Stub Portal version sync: when an external app is updated via the App Store, the local Stub Portal's version info is now automatically synced and the macOS Launch Services cache is refreshed. The "Open With" menu no longer shows stale version numbers (#50).
- Added tool directory detection for Gradle (`~/.gradle`), Android development data (`~/.android`), and Flutter/Dart Pub cache (`~/.pub-cache`) (#49).
- Added Directory Migration: add arbitrary user folders in the "Directory Migration" tab, migrate large projects, models, asset libraries, or tool caches to external storage, and relink or restore them later (#54).
- Added protected-app migration warning: before migrating App Store apps or root-owned apps, AppPorts warns that automatic deletion or replacement may fail due to permissions and suggests manually moving the app in Finder before creating a link (#55).

### Improvements

- Faster app scanning: Info.plist reads per app reduced from 7 to 1 (via in-memory cache), significantly improving scan speed.
- Scan timeout protection: the `codesign` subprocess now has a 10-second timeout, preventing large app signature checks from blocking the entire scan indefinitely.
- Directory size calculation safety cap: a 500,000 file count limit has been added to recursive size calculations, preventing runaway enumeration on Electron and other large app bundles.
- Scan trace logging: per-app TRACE logging added to the scan loop, making it easier to identify which app is slow or stuck during scanning.
- More precise data directory matching: fixed bundle ID suffix extraction to filter generic TLD words like `app`, `com`, `org`. Previously, bundle IDs like `cn.trae.app` would trigger scanning of 720+ unrelated system containers.
- More complete tool-directory relink detection: when a local tool directory is missing but a managed directory still exists at the canonical external-storage location, AppPorts shows it as "Needs Relinking"; switching external storage refreshes tool-directory state automatically.
- Improved localization and accessibility: app, data-directory, and custom-directory statuses, sort/filter labels, settings toggles, and status badges now follow the selected language more consistently and expose clearer accessibility labels.
- App sizes now use a session-level cache, reducing cases where sizes return to "Calculating" or disappear after a refresh (#55).
- Safer data-directory rollback: before creating the link, AppPorts renames the local source to a hidden safety backup. If link creation or backup cleanup fails, it keeps the local backup and external copy where possible to avoid losing both sides (#54).

### Fixes

- Fixed Trae and similar apps scanning extremely slowly — the generic suffix `app` from the bundle ID caused `~/Library/Containers/` to scan hundreds of unrelated directories.
- Fixed local Stub Portal version info not updating after external apps are updated via the App Store, causing the "Open With" menu to show stale versions.
- Fixed the refresh button not triggering Stub Portal version sync.
- Fixed data-directory relinking or normalization potentially treating an external regular file as a directory; regular files are now rejected and left untouched.
- Fixed multi-line dialog bodies falling back to Chinese in some languages, completed Russian UI translations, and localized the Stub Portal "external storage not connected" system dialog based on the system language (#55).

## v1.7.0

### New Features

- Added "Pending Move Out" status: when the real local app is newer than the app with the same name on external storage, AppPorts marks it as pending move out, indicating that the local newer version can be safely migrated out to replace the external older copy.
- Added re-sign confirmation for data migration: before migrating data inside an app container, AppPorts can ask whether to automatically apply Ad-hoc re-signing to the related app after migration, reducing the risk of unrecognized data, warnings, or launch failures after container data migration (#44).

### UI Improvements

- Rearranged the top toolbar: app/data-directory tab buttons now use a more compact icon + text style.
- Optimized the data-directory action bar: the Tool Directories / App Data switch, post-migration re-sign toggle, restore original signature button, and refresh button now live in the top toolbar.
- Added a "Pending Move Out" app status badge for apps whose local version is newer than the external old copy.
- Localized the data migration re-sign confirmation dialog, including title, body text, and buttons.

### Improvements

- Strengthened app migration safety: when the external destination already exists, AppPorts only auto-cleans it if it is identified as an AppPorts-managed old portal, a stale migration remnant, or the app is in "Pending Move Out" state.
- Strengthened data-directory recovery checks: automatic recovery no longer relies on similar directory size and now requires full AppPorts metadata matching.
- Made app data scanning more stable: results from older scan tasks no longer overwrite the data-directory list for the currently selected app.
- Improved escaping for admin commands and AppleScript: paths containing quotes, backslashes, spaces, or Chinese characters are handled more safely.
- Improved localization: fixed help content, prompts, and data migration confirmation text that could remain in Chinese or be incomplete after switching languages, and completed translations for all supported languages (#43).

### Fixes

- Fixed data directory migration incorrectly treating a real external directory as a recoverable target.
- Fixed app migration potentially deleting a real external app with the same name by mistake.
- Fixed unstable detection and cleanup of old external AppPorts portals or stale migration remnants.
- Fixed malformed AppleScript or admin commands when paths contain special characters.
- Fixed background migration or post-migration re-signing reading the app after the selected app had changed.
- Fixed the "Pending Move Out" status badge not appearing in the app list.

## v1.6.2

- New: Auto re-sign at login. Automatically re-signs migrated apps with expired signatures each time the user logs in, no manual action needed. Enabled by default, can be turned off in Settings
- Improvement: Stub Portal now uses a native Mach-O binary launcher instead of the legacy bash script, fixing the issue where double-clicking associated documents in Finder could not open the external app (#42)
- Improvement: About page layout optimized with scrollable content area, fixing content being cut off when the window is too small
- Fix: Native Stub Portal being incorrectly identified as a regular local app
- Fix: Unable to properly clean up native Stub Portal when moving apps back to local storage
- Fix: App shell being treated as a complete app during link-back-to-local operations
- Fix: AutoResignInstaller silently succeeding when installation fails

## v1.6.1

- Fixed: Auto-re-signing after data directory migration now correctly signs the real external app instead of the local stub shell
- Fixed: Re-signing and signature restore operations now correctly resolve the real path for linked apps
- Fixed: "Re-signed" status detection for linked apps now correctly identifies the signing status of the real external app
- Improved: Log output includes structured error codes and related path information

## v1.6.0

- Migrated apps no longer show arrow badges
- Auto-updating apps are no longer broken by updates after migration
- Added app signature management feature to fix "Damaged" prompts after migration
- External storage disconnection now shows red "Orphaned Link" warnings
- macOS 15.1+ users can install App Store apps directly to external drives
- Data directory migration is safer: prevents accidental system directory migration, auto-recovers from interruption
- Scanning and size calculation are faster; list no longer jumps
- File copying to external storage is more stable; no more errors on interruption
- App status badges redesigned with richer information and clickable details
- App list no longer loses selection after refresh; data directories support tree view
- UI refinements: search, sort, group cards, icon loading, etc.
- Added Martian language option
- Automated test updates

## v1.5.5

- Added macOS 15.1+ App Store app external installation support
- Added auto re-signing feature (auto-executed after data directory migration)
- Added `LocalizationAuditTests` localization audit tests
- Improved Stub Portal Info.plist generation logic
- Fixed Launchpad icon loss issue for some apps after migration

## v1.4.0

- Added data directory tree view
- Added tool directory detection (30+ development tools)
- Added diagnostic package export feature
- Improved self-update detection (Chrome, Edge, and other custom updaters)
- Fixed auto-recovery mechanism after migration interruption

## v1.3.0

- Added data directory migration feature
- Added code signature management (backup/restore original signatures)
- Added Sparkle and Electron app auto-detection
- Improved locked migration protection (`chflags uchg`)
- Fixed badge display issues in Finder

## v1.2.0

- Added Stub Portal migration strategy (replacing Deep Contents Wrapper)
- Added iOS app migration support (Mac version iOS apps)
- Improved batch migration performance
- Fixed issue where some apps could not launch after restore

## v1.1.0

- Added multi-language support (20+ languages)
- Added app suite directory migration (e.g., Microsoft Office)
- Improved external storage offline detection
- Fixed symbolic link penetration issue with Deep Contents Wrapper strategy

## v1.0.0

- First official release
- Supported app migration to external storage (Deep Contents Wrapper / Whole App Symlink)
- Supported app restore and link management
- Supported FolderMonitor real-time file system monitoring
