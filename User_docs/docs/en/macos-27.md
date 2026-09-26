---
outline: deep
---

# Upgrading to macOS 27

::: tip The key point
If you migrated container data for an app such as WeChat with AppPorts and agreed to re-sign it, the app **may** quit immediately after upgrading to macOS 27. WeChat does; QQ Music still opened in our tests. **The data is not damaged**, and you do not need to migrate it again. Restore the data locally and reinstall the app from an official source. If you then want the data on an external drive, use the new [mount migration](/en/datamigrae/mount-migration).
:::

## Who Is Affected?

| Item | Description |
|------|-------------|
| Trigger | Upgrading to macOS 27 |
| Affected apps | Apps whose `~/Library/Containers/` or `~/Library/Group Containers/` data was migrated and which were re-signed Ad-hoc; or sandboxed apps manually re-signed from the right-click menu |
| Typical symptom | Opening from Finder / Dock does nothing, or the icon appears briefly and disappears without an error dialog. Not all re-signed apps behave this way: QQ Music runs normally on the same Mac with 27 |
| Data | Intact, including chat history and login sessions |
| Confirmed case | WeChat 4.1.15, macOS 27.0 (26A428) |

Re-signing removes the app's sandbox identity. When macOS 27 checks whether the app is entitled to access its container, existing permission records for its original signature may no longer match. WeChat's logs show `Failed to match existing code requirement`. Apps without an old record, such as QQ Music, are currently allowed through, but lost entitlements such as Keychain login access are not restored. See [Container Data, Sandboxing, and Signing Identity](/en/datamigrae/container-identity).

## Before Upgrading: Check First

This script lists apps whose signatures were replaced by AppPorts. Any listed app could have problems after upgrading.

```bash
BACKUP_DIR="$HOME/Library/Application Support/AppPorts/signature-backups"
for plist in "$BACKUP_DIR"/*.plist; do
  [ -f "$plist" ] || continue
  original=$(/usr/libexec/PlistBuddy -c "Print :signingIdentity" "$plist" 2>/dev/null)
  app=$(/usr/libexec/PlistBuddy -c "Print :originalPath" "$plist" 2>/dev/null)
  case "$original" in ""|ad-hoc) continue ;; esac   # 本来就是 ad-hoc 的跳过
  [ -d "$app" ] || continue
  if codesign -dv "$app" 2>&1 | grep -q "Signature=adhoc"; then
    printf "%s\n    原始签名: %s\n" "$app" "$original"
  fi
done
```

Ideally, follow the [repair steps](#repair) before upgrading. At least save the list so you know which apps may need attention afterward.

## After Upgrading: Confirm the Symptoms

```bash
# 1. 签名（出现 Signature=adhoc 且 TeamIdentifier=not set 即已被重签名）
codesign -dv --verbose=4 /Applications/WeChat.app 2>&1 | grep -E "Authority|TeamIdentifier|Signature"

# 2. 复现并看系统日志
open -a /Applications/WeChat.app; sleep 3
log show --last 1m --style compact 2>/dev/null | grep -i "rejected approval request"
```

If step 2 shows `kTCCServiceSystemPolicyAppData ... denied`, the problem is confirmed. See the fuller checklist in [Container Data, Sandboxing, and Signing Identity](/en/datamigrae/container-identity#check-it-yourself).

## Repair

AppPorts 1.8.2 identifies these apps automatically with a red "Signature replaced" badge and a one-time startup reminder. Right-click an app and choose "Show repair steps" to open a panel with each step's status and actions. It does not delete any data. Follow the same sequence if working manually. **Do not change the order.**

### Step 1: Restore Container Data to This Mac

Click "Restore all" in the repair panel. Alternatively, open "Data Directories" → "App Data", select the app, and click "Restore" on every "Linked" container directory. Since the app cannot open, a running-app check will not block you.

This must come first because the reinstalled app is sandboxed again and cannot read data through symbolic links. Otherwise it still appears empty, making the repair look unsuccessful.

After restoring, check:

```bash
find ~/Library/Containers/<Bundle ID> -maxdepth 6 -type l -exec readlink {} \; 2>/dev/null
# 没有输出，或输出里没有 /Volumes/... 就对了
```

### Step 2: Move the App Itself Back to This Mac

This is needed only if the app bundle was migrated to the external drive. The item in `/Applications` is then an AppPorts launcher; installing over it would replace the launcher and leave the external copy orphaned. Click "Move back" in the repair panel, or select the app in the external app library and move it back. If you want it on the external drive after reinstallation, migrate the app itself again.

### Step 3: Reinstall the App if It Cannot Open

If the app still opens normally on 27, you can skip this step and go to step 4 to switch the data to mount migration. If reinstallation is needed, quit completely and install over the app from an official source: use the App Store for App Store apps, with the panel's "Open App Store" button, or the developer's website for other apps. **Do not delete the container directory.** Reinstallation leaves it, its chat history, and login sessions in place.

After installation, click "Check again" in the panel, or use the first diagnostic command to confirm the signature is `Authority=Developer ID Application: ...` or `Apple Mac OS Application Signing`. The "Signature replaced" badge disappears when the signature is restored. Ordinary scans preserve backups; the corresponding backup is cleaned up only after restoration through AppPorts succeeds.

::: tip Full backups can restore directly; legacy backups need an original app
The new "Restore Original Signature" uses a complete original app backup and does not need the developer's private key. Legacy records containing only an identity name still cannot restore directly. Select an official original `.app` of the same version, or reinstall as described above. In either case, restore container data migrated in classic mode first. See [Signature Backups and Restoration](/en/datamigrae/resign#signature-backups-and-restoration).
:::

### Step 4 (Optional): Move the Data Back with Mount Migration

Open AppPorts after reinstalling. Container directories show "Mount migration" instead of "Migrate". Click it and follow the prompts. The first time you open the app, macOS requests access to Removable Volumes. **Click Allow.** The drive must use unencrypted APFS; AppPorts checks first and explains the next step. If your drive is not APFS, leaving the data on this Mac is also fine. See [Why External Drives Must Use APFS](/en/why-apfs#what-to-do).

## What Does Not Fix It

| Action | Why It Does Not Help |
|--------|----------------------|
| Restoring the data locally and assuming the repair is complete | Restoration fixes access to external data, not the signature. The re-signed app may still quit immediately |
| Clicking "Resign This App" again | Re-signing caused the problem and simply removes the entitlements again |
| Adding the app to Full Disk Access | May bypass the container check, but Keychain entitlements are still missing and login sessions may remain broken. This is only a temporary workaround |
| Treating a successful Terminal launch as a repair | Launching from Terminal borrows Terminal's permissions. Test by opening from Finder / Dock |

## What AppPorts 1.8.2 Changes

- Container directories use [mount migration](/en/datamigrae/mount-migration) rather than symbolic links, regardless of the main app's sandbox status.
- Sandboxed apps are refused at every re-signing entry point: right-click menu, "Re-sign after migration", and the login script.
- "Restore Original Signature" restores the complete original app, signature, and entitlements without the developer's private key. Legacy records can use an official original copy of the same version.
- Replaced signatures are detected automatically, with a red "Signature replaced" badge, a startup reminder, and a repair panel opened through "Show repair steps".
- Old container symbolic links are still recognized as "Linked" and can be restored. "Normalize" and "Relink" are disabled for containers to avoid recreating symbolic links.
- **Classic data migration mode** remains for users who already rely on the old method. It is off by default and requires risk confirmation; see [Settings](/en/settings#classic-data-migration-mode). If your drive is not APFS, leave container data on this Mac instead of enabling it for that reason.

Updating AppPorts does not automatically restore apps already re-signed. They still need the steps above.

## Common Questions

### Will I Lose Chat History?

No. Reinstallation does not affect container data, and the app continues reading it afterward. AppPorts does not delete data during this process either.

### I Restored the Data, but the App Still Will Not Open

The signature has not been repaired yet. Restoration and reinstallation are separate steps, and both are required. See [Repair](#repair).

### Does This Affect Only WeChat?

Not necessarily. Re-signed QQ Music opens normally on the same Mac with 27. Current evidence points to whether the system already holds permission records for the app's previous signature. This cannot be predicted in advance, so all apps with replaced signatures are listed for you to check. The [pre-upgrade script](#before-upgrading-check-first) produces the complete list.

### Did AppPorts Corrupt the Data?

No, the data is intact. However, the direct cause of the failure is the old AppPorts option to agree to re-signing. Version 1.8.2 removes that path.

## Related Documentation

- [Container Data, Sandboxing, and Signing Identity](/en/datamigrae/container-identity): the underlying mechanism
- [Mount Migration](/en/datamigrae/mount-migration): the new approach
- [Why External Drives Must Use APFS](/en/why-apfs)
- [Re-signing and Crash Prevention](/en/datamigrae/resign)
