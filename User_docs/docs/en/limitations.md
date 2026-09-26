---
outline: deep
---

# Compatibility and Limitations

## System Requirements

| Requirement | Details |
|-------------|---------|
| Minimum system | macOS 12.0 (Monterey) |
| Architecture | Intel x86_64 / Apple Silicon (arm64) |
| Permission | Full Disk Access |
| External storage | At least one external storage device |

## Feature Compatibility

### By macOS Version

| Feature | macOS 12.0 - 15.0 | macOS 15.1+ |
|---------|:----------------:|:-----------:|
| App migration (Stub Portal) | ✓ | ✓ |
| Data directory migration (symbolic links) | ✓ | ✓ |
| Container data mount migration | ✓ (administrator password required to mount) | ✓ (no password needed in tests on 27; versions 13 through 26 not individually verified) |
| Directory migration (custom folders) | ✓ | ✓ |
| Code signature management | ✓ | ✓ |
| App Store apps on external storage | ✗ | ✓ |
| In-place App Store updates on external storage | ✗ | ✓ |
| iOS app migration | ✓ | ✓ |

::: warning App Store apps before macOS 15.1
Systems before macOS 15.1 (Sequoia) do not support native App Store installation to external storage. If you need to migrate these apps, manually enable App Store app migration in AppPorts Settings. After an app update, migrate it again to replace the external copy.
:::

### By App Type

| App Type | Migrate | Restore | Automatic Updates | Details |
|----------|:-------:|:-------:|:-----------------:|---------|
| Native macOS apps | ✓ | ✓ | ✓ | Best compatibility |
| Sparkle apps | ✓ | ✓ | Lock required | Locking prevents in-app updates; move back locally before updating |
| Electron apps | ✓ | ✓ | Lock required | Same as Sparkle |
| Chrome / Edge (custom updaters) | ✓ | ✓ | ✓ | Updates install locally without damaging the external copy |
| App Store apps on macOS 15.1+ | ✓ | ✓ | ✓ | Native external installation; App Store updates directly |
| App Store apps on macOS <15.1 | ✓ | ✓ | Manual | Migrate again after updates |
| iOS apps for Mac | ✓ | ✓ | ✓ | Use iOS Stub Portal |
| System apps | ✗ | — | — | Protected by SIP; cannot be migrated |

::: warning Migrating protected apps
macOS permissions may prevent AppPorts from deleting or replacing local copies of App Store or root-owned apps automatically. When warned about a protected app, move it to external storage in Finder first, then create its local link in AppPorts.
:::

::: tip Finder shortcut arrows
Older AppPorts entries may use whole-app symbolic links, which show shortcut arrows in Finder. The current version uses Stub Portal for ordinary `.app` bundles, generally without arrows. If an arrow remains, move the app back locally and migrate it again.
:::

::: tip Pending Move Out
"Pending Move Out" requires comparable versions and a reliable match between the local and external apps. AppPorts matches by Bundle ID first, then normalized name when necessary. Missing or incomparable versions, or different Bundle IDs for same-name apps, prevent this status from appearing.
:::

### By Data Directory Type

| Data Directory | Migration Method | Risk |
|----------------|:----------------:|------|
| `~/Library/Application Support/` | Symbolic link | Medium — apps may use file locks or SQLite WAL logs |
| `~/Library/Preferences/` | Symbolic link | Low–medium — `cfprefsd` caching may return stale preferences |
| `~/Library/Containers/` | Mount | Medium — requires an unencrypted APFS drive, permission on first launch, and connecting the drive before opening the app |
| `~/Library/Group Containers/` | Mount | Medium — same requirements; shared data affects other apps in the same Team |
| `~/Library/Caches/` | Symbolic link | Low — caches can be rebuilt |
| `~/Library/Logs/` | Symbolic link | Low — log files only |
| `~/Library/WebKit/` | Symbolic link | Medium — WebKit local storage |
| `~/Library/HTTPStorages/` | Symbolic link | Low — network session storage |
| `~/Library/Application Scripts/` | Symbolic link | Low — extension scripts |
| `~/Library/Saved Application State/` | Symbolic link | Low — window state restoration |
| Dot-folders such as `~/.npm`, `~/.m2` | Symbolic link | Low — development tool caches |
| Custom folders under your home directory | Symbolic link | Depends on content — quit apps and tools writing there first |

::: warning Valuable data directories
WeChat chat history, virtual machine images, game libraries, databases, and model caches are often large, frequently written, and sensitive to paths and file locks. Make an independent backup first. If an app reports data problems after migration, restore locally before investigating further.
:::

::: warning Container data requires mount migration
Sandboxed apps cannot read data moved out of `~/Library/Containers/` or `~/Library/Group Containers/` through symbolic links. Older versions bypassed this by re-signing, which may prevent the apps from opening on macOS 27. Starting with 1.8.2, these directories use [mount migration](/en/datamigrae/mount-migration), and sandboxed apps are refused re-signing. See [Container Data, Sandboxing, and Signing Identity](/en/datamigrae/container-identity).
:::

::: warning Scope of custom directories
Directory Migration accepts real folders under your home directory. You cannot select files, symbolic links, paths inside an external destination, system directories, or paths that contain or are contained by an existing managed item.
:::

::: warning Destination conflicts
Similar directory sizes do not let AppPorts take over or resume a migration automatically. It resumes only when the external directory's AppPorts metadata fully matches the current operation. Otherwise it stops with a real-directory conflict.
:::

## Content That Cannot Be Migrated

### Protected by SIP

| Path | Reason |
|------|--------|
| macOS system apps such as Safari and Finder | System Integrity Protection |
| Top-level directories under `~/Library/Containers/` | macOS system protection |

### Contains Path References

| Path | Reason |
|------|--------|
| `~/.local` | Contains executable path references; migration may break command-line tools |
| `~/.config` | Contains absolute path settings; migration may break tool configurations |

## External Storage Requirements

| Requirement | Details |
|-------------|---------|
| File system | Apps and ordinary data directories: APFS, HFS+, or exFAT. **Container data: APFS only** |
| Minimum space | Depends on the size of the apps to migrate |
| Interface | USB, Thunderbolt, and NVMe supported |
| Connection | Keep external storage connected after migration; otherwise the relevant apps cannot start |

::: tip File system recommendations
- **APFS**: recommended; the only format supporting container mount migration, with the best performance.
- **HFS+**: compatible with older Macs, but cannot migrate container data.
- **exFAT**: cross-platform, but cannot migrate container data. Use a separate APFS partition if sharing the drive with Windows. Built-in tools cannot shrink an exFAT partition that fills the disk; back up and repartition first. If unallocated space already exists, create APFS there when the [partition requirements](/en/why-apfs#prepare-apfs) are met.

For why container data needs APFS and the alternatives we tested, see [Why External Drives Must Use APFS](/en/why-apfs).
:::

### Network Mounts

NAS, SMB, rclone, and SFTP mounts are not primary AppPorts validation targets. They may work, but you must verify mount stability, consistent paths, permissions, extended attributes, and symbolic-link behavior. They are not the preferred option for continuously written data directories.
