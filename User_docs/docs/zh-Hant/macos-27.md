---
outline: deep
---

# macOS 27 升級說明

::: tip 一句話結論
用 AppPorts 遷移過微信等應用程式的容器資料、並且當時選了「同意重簽名」的使用者，升級到 macOS 27 後這些應用程式**可能**按兩下秒退（微信會，QQ 音樂等實測仍能開啟）。**資料沒有壞**，也不需要重新遷移。把資料還原回本機、從官方管道重新安裝應用程式即可恢復；之後想繼續放在外接磁碟，用新的[掛載遷移](/zh-Hant/datamigrae/mount-migration)。
:::

## 誰會受影響

| 項目 | 說明 |
|------|------|
| 觸發條件 | 升級到 macOS 27 |
| 受影響應用程式 | 遷移過 `~/Library/Containers/` 或 `~/Library/Group Containers/` 資料，且執行過 Ad-hoc 重簽名的應用程式；或者手動右鍵重簽名過的沙盒應用程式 |
| 典型表現 | Finder / Dock 按兩下無反應，圖示閃一下就消失，沒有報錯對話框。並非所有重簽名過的應用程式都會這樣：QQ 音樂在同一臺 27 上正常執行 |
| 資料 | 完好，包括聊天記錄和登入狀態 |
| 已確認案例 | 微信 4.1.15，macOS 27.0 (26A428) |

原因簡單說：重簽名把應用程式的沙盒身分拆掉了，macOS 27 核對"這個應用程式有沒有資格碰這個容器"時，如果系統裡已經存著這個應用程式原來簽名的授權記錄，新簽名對不上就被拒絕（微信的日誌：`Failed to match existing code requirement`）。沒有舊記錄的應用程式（如 QQ 音樂）目前能放行，但鑰匙圈登入狀態等遺失的授權同樣找不回來。原理見[容器資料、沙盒與簽名身分](/zh-Hant/datamigrae/container-identity)。

## 還沒升級：先檢查

下面的指令碼會列出被 AppPorts 替換過簽名的應用程式。有輸出的都是升級後可能出問題的物件。

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

建議升級前就按下面的[修復](#修復)步驟處理完。至少把名單記下來，升級後知道該修哪些。

## 已升級：確認症狀

```bash
# 1. 签名（出现 Signature=adhoc 且 TeamIdentifier=not set 即已被重签名）
codesign -dv --verbose=4 /Applications/WeChat.app 2>&1 | grep -E "Authority|TeamIdentifier|Signature"

# 2. 复现并看系统日志
open -a /Applications/WeChat.app; sleep 3
log show --last 1m --style compact 2>/dev/null | grep -i "rejected approval request"
```

第 2 步出現 `kTCCServiceSystemPolicyAppData ... denied` 即可確認。更完整的自查表見[容器資料、沙盒與簽名身分](/zh-Hant/datamigrae/container-identity#自查)。

## 修復

AppPorts 1.8.2 會自動找出這類應用程式：應用程式清單裡帶紅色「簽名已替換」徽章，啟動時彈一次提醒。右鍵應用程式選擇「檢視修復步驟」會開啟修復面板，面板按下面的順序列出每一步的狀態和按鈕，全程不刪除任何資料。手動操作也是同樣的順序，**順序不能變**。

### 第 1 步：把容器資料還原回本機

修復面板裡按一下「全部還原」；或者開啟「資料目錄」→「應用程式資料」，選取該應用程式，把所有狀態為「已連結」的容器目錄逐個按一下「還原」。應用程式本來就打不開，不會被"正在執行"攔住。

為什麼必須先做這一步：重新安裝完的應用程式是正常的沙盒應用程式，它讀不到符號連結後面的資料，你會看到"重新安裝了還是空白"，誤以為沒修好。

還原完成後可以確認一下：

```bash
find ~/Library/Containers/<Bundle ID> -maxdepth 6 -type l -exec readlink {} \; 2>/dev/null
# 没有输出，或输出里没有 /Volumes/... 就对了
```

### 第 2 步：應用程式本體遷回本機

只有應用程式本體已經遷移到外接磁碟時才需要這一步。此時 `/Applications` 裡的是 AppPorts 的啟動殼，直接覆蓋安裝會把殼蓋掉，外接磁碟上的副本變成孤兒。修復面板裡按一下「遷回本機」，或在「外部儲存」裡選取它按一下「遷回本機」。裝完想繼續放在外接磁碟，再遷移一次應用程式本體即可。

### 第 3 步：重新安裝應用程式（打不開時才需要）

如果應用程式在 27 上仍能正常開啟，這一步可以跳過，直接做第 4 步把資料換成掛載遷移。需要重新安裝時：完全退出應用程式，從官方管道覆蓋安裝：App Store 應用程式用 App Store（面板有「打開 App Store」按鈕），官網應用程式從官網下載。**不要刪除容器目錄**，重新安裝不會動它，聊天記錄、登入狀態都還在。

裝完在面板裡按一下「重新檢查」，或用第 1 條自查命令確認簽名恢復成 `Authority=Developer ID Application: ...` 或 `Apple Mac OS Application Signing`。簽名恢復後「簽名已替換」徽章會消失。一般掃描會保留備份；透過 AppPorts 完成恢復後才清理對應備份。

::: tip 完整備份可直接恢復，舊備份需要原版應用程式
新版「恢復原始簽名」使用完整原始應用程式備份，不需要開發者私鑰。舊版只有簽名身分名稱的記錄仍無法直接恢復，可選擇同版本官方原版 `.app` 補救，或按上述步驟重新安裝。無論哪種方式，都應先還原經典模式的容器資料。詳見[簽名備份與恢復](/zh-Hant/datamigrae/resign#簽名備份與恢復)。
:::

### 第 4 步（可選）：用掛載遷移把資料放回外接磁碟

重新安裝後再開啟 AppPorts，容器目錄會顯示「掛載遷移」而不是「遷移」。點它，按提示走。第一次開啟應用程式時系統會彈「取用可移除式卷宗」授權對話框，**按一下允許**。外接磁碟必須是未加密的 APFS，AppPorts 會先檢查並告訴你下一步；外接磁碟不是 APFS 時，讓資料留在本機也完全可以，見[為什麼外接磁碟必須是 APFS](/zh-Hant/why-apfs#what-to-do)。

## 不要做的事

| 做法 | 為什麼沒用 |
|------|-----------|
| 只把資料還原回本機就當修好了 | 還原只解決"讀不到外接磁碟資料"，無法修復簽名。重簽名過的應用程式還原後照樣秒退 |
| 再按一下「重簽名此應用」 | 重簽名就是病因，只會再抹一次授權 |
| 把應用程式加進「完整磁碟取用權限」 | 可能繞過容器驗證，但鑰匙圈授權已丟，登入狀態照樣有問題。只能當暫時措施 |
| 用"終端裡能開啟"當作修好了 | 終端啟動時借用了終端的權限，是假象。以 Finder / Dock 按兩下為準 |

## AppPorts 1.8.2 做了什麼

- 容器目錄不再提供符號連結遷移，一律走[掛載遷移](/zh-Hant/datamigrae/mount-migration)，不看主程式是不是沙盒。
- 沙盒應用程式在所有入口都拒絕重簽名：右鍵選單、「遷移后重签名」開關、開機自動重簽名指令碼。
- 「恢復原始簽名」改為還原完整原始應用程式及其簽名、授權，無需開發者私鑰；舊記錄可選擇同版本官方原版補救。
- 自動偵測簽名被替換的應用程式：紅色「簽名已替換」徽章、啟動提醒、右鍵「檢視修復步驟」開啟修復面板。
- 舊版本遷移的容器符號連結仍能辨識為「已連結」，「還原」按鈕照常可用；「整理」「接回」對容器目錄禁用，避免重建符號連結。
- 保留了一個**經典資料遷移模式**給已經依賴舊方法的使用者，預設關閉，開啟前需確認風險，見[設定](/zh-Hant/settings#classic-data-migration-mode)。外接磁碟不是 APFS 的話，建議讓容器資料留在本機，不必為此開啟它。

已經被重簽名過的應用程式不會因為升級 AppPorts 自動恢復，仍需按上面的步驟處理。

## 常見疑問

### 聊天記錄會不會丟？

不會。容器資料不受重新安裝影響，重新安裝後應用程式繼續讀原有資料。整個過程 AppPorts 也沒有刪除過資料。

### 我還原了資料還是打不開？

因為簽名還沒修。還原和重新安裝是兩個獨立的步驟，缺一不可，見[修復](#修復)。

### 只有微信會這樣嗎？

不一定。同一臺 27 上，重簽名過的 QQ 音樂能正常開啟。目前的證據指向"系統裡是否已存有該應用程式舊簽名的授權記錄"，無法提前判斷，所以把所有被替換過簽名的應用程式都列出來供你檢查。用[升級前檢查](#還沒升級-先檢查)的指令碼能掃出完整名單。

### 是 AppPorts 把資料弄壞了嗎？

不是，資料完好。但故障的直接來源確實是 AppPorts 舊版本的「同意重簽名」選項，1.8.2 已經拿掉了這條路。

## 相關文件

- [容器資料、沙盒與簽名身分](/zh-Hant/datamigrae/container-identity)：原理
- [掛載遷移](/zh-Hant/datamigrae/mount-migration)：新方案
- [為什麼外接磁碟必須是 APFS](/zh-Hant/why-apfs)
- [重簽名與當機防護](/zh-Hant/datamigrae/resign)
