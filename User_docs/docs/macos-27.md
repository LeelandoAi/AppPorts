---
outline: deep
---

# macOS 27 升级说明

::: tip 一句话结论
用 AppPorts 迁移过微信等应用的容器数据、并且当时选了「同意重签名」的用户，升级到 macOS 27 后这些应用**可能**双击秒退（微信会，QQ 音乐等实测仍能打开）。**数据没有坏**，也不需要重新迁移。把数据还原回本地、从官方渠道重装应用即可恢复；之后想继续放外置盘，用新的[挂载迁移](/datamigrae/mount-migration)。
:::

## 谁会受影响

| 项目 | 说明 |
|------|------|
| 触发条件 | 升级到 macOS 27 |
| 受影响应用 | 迁移过 `~/Library/Containers/` 或 `~/Library/Group Containers/` 数据，且执行过 Ad-hoc 重签名的应用；或者手动右键重签名过的沙盒应用 |
| 典型表现 | Finder / Dock 双击无反应，图标闪一下就消失，没有报错弹窗。并非所有重签名过的应用都会这样：QQ 音乐在同一台 27 上正常运行 |
| 数据 | 完好，包括聊天记录和登录态 |
| 已确认案例 | 微信 4.1.15，macOS 27.0 (26A428) |

原因简单说：重签名把应用的沙盒身份拆掉了，macOS 27 核对"这个应用有没有资格碰这个容器"时，如果系统里已经存着这个应用原来签名的授权记录，新签名对不上就被拒绝（微信的日志：`Failed to match existing code requirement`）。没有旧记录的应用（如 QQ 音乐）目前能放行，但钥匙串登录态等丢失的授权同样找不回来。原理见[容器数据、沙盒与签名身份](/datamigrae/container-identity)。

## 还没升级：先检查

下面的脚本会列出被 AppPorts 替换过签名的应用。有输出的都是升级后可能出问题的对象。

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

建议升级前就按下面的[修复](#修复)步骤处理完。至少把名单记下来，升级后知道该修哪些。

## 已升级：确认症状

```bash
# 1. 签名（出现 Signature=adhoc 且 TeamIdentifier=not set 即已被重签名）
codesign -dv --verbose=4 /Applications/WeChat.app 2>&1 | grep -E "Authority|TeamIdentifier|Signature"

# 2. 复现并看系统日志
open -a /Applications/WeChat.app; sleep 3
log show --last 1m --style compact 2>/dev/null | grep -i "rejected approval request"
```

第 2 步出现 `kTCCServiceSystemPolicyAppData ... denied` 即可确认。更完整的自查表见[容器数据、沙盒与签名身份](/datamigrae/container-identity#自查)。

## 修复

AppPorts 1.8.2 会自动找出这类应用：应用列表里带红色「签名已替换」徽章，启动时弹一次提醒。右键应用选择「查看修复步骤」会打开修复面板，面板按下面的顺序列出每一步的状态和按钮，全程不删除任何数据。手动操作也是同样的顺序，**顺序不能变**。

### 第 1 步：把容器数据还原回本地

修复面板里点「全部还原」；或者打开「数据目录」→「应用数据」，选中该应用，把所有状态为「已链接」的容器目录逐个点「还原」。应用本来就打不开，不会被"正在运行"拦住。

为什么必须先做这一步：重装完的应用是正常的沙盒应用，它读不到符号链接后面的数据，你会看到"重装了还是空白"，误以为没修好。

还原完成后可以确认一下：

```bash
find ~/Library/Containers/<Bundle ID> -maxdepth 6 -type l -exec readlink {} \; 2>/dev/null
# 没有输出，或输出里没有 /Volumes/... 就对了
```

### 第 2 步：应用本体迁回本地

只有应用本体已经迁移到外置盘时才需要这一步。此时 `/Applications` 里的是 AppPorts 的启动壳，直接覆盖安装会把壳盖掉，外置盘上的副本变成孤儿。修复面板里点「迁回本地」，或在「外部应用库」里选中它点「迁回本地」。装完想继续放外置盘，再迁移一次应用本体即可。

### 第 3 步：重装应用（打不开时才需要）

如果应用在 27 上仍能正常打开，这一步可以跳过，直接做第 4 步把数据换成挂载迁移。需要重装时：完全退出应用，从官方渠道覆盖安装：App Store 应用用 App Store（面板有「打开 App Store」按钮），官网应用从官网下载。**不要删除容器目录**，重装不会动它，聊天记录、登录态都还在。

装完在面板里点「重新检查」，或用第 1 条自查命令确认签名恢复成 `Authority=Developer ID Application: ...` 或 `Apple Mac OS Application Signing`。签名恢复后「签名已替换」徽章会消失。普通扫描会保留备份；通过 AppPorts 完成恢复后才清理对应备份。

::: tip 完整备份可直接恢复，旧备份需要原版应用
新版「恢复原始签名」使用完整原始应用备份，不需要开发者私钥。旧版只有签名身份名称的记录仍无法直接恢复，可选择同版本官方原版 `.app` 补救，或按上述步骤重装。无论哪种方式，都应先还原经典模式的容器数据。详见[签名备份与恢复](/datamigrae/resign#签名备份与恢复)。
:::

### 第 4 步（可选）：用挂载迁移把数据放回外置盘

重装后再打开 AppPorts，容器目录会显示「挂载迁移」而不是「迁移」。点它，按提示走。第一次打开应用时系统会弹「访问可移动宗卷」授权框，**点允许**。外置盘必须是未加密的 APFS，AppPorts 会先检查并告诉你下一步；外置盘不是 APFS 时，让数据留在本机也完全可以，见[为什么外置盘必须是 APFS](/why-apfs#what-to-do)。

## 不要做的事

| 做法 | 为什么没用 |
|------|-----------|
| 只把数据还原回本地就当修好了 | 还原只解决"读不到外置盘数据"，修不好签名。重签名过的应用还原后照样秒退 |
| 再点一次「重签名」 | 重签名就是病因，只会再抹一次授权 |
| 把应用加进「完全磁盘访问权限」 | 可能绕过容器校验，但钥匙串授权已丢，登录态照样有问题。只能当临时手段 |
| 用"终端里能打开"当作修好了 | 终端启动时借用了终端的权限，是假象。以 Finder / Dock 双击为准 |

## AppPorts 1.8.2 做了什么

- 容器目录不再提供符号链接迁移，一律走[挂载迁移](/datamigrae/mount-migration)，不看主程序是不是沙盒。
- 沙盒应用在所有入口都拒绝重签名：右键菜单、「迁移后重签名」开关、开机自动重签名脚本。
- 「恢复原始签名」改为还原完整原始应用及其签名、授权，无需开发者私钥；旧记录可选择同版本官方原版补救。
- 自动检测签名被替换的应用：红色「签名已替换」徽章、启动提醒、右键「查看修复步骤」打开修复面板。
- 旧版本迁移的容器符号链接仍能识别为「已链接」，「还原」按钮照常可用；「整理」「接回」对容器目录禁用，避免重建符号链接。
- 保留了一个**经典数据迁移模式**给已经依赖旧方法的用户，默认关闭，开启前需确认风险，见[设置](/settings#classic-data-migration-mode)。外置盘不是 APFS 的话，建议让容器数据留在本机，不必为此打开它。

已经被重签名过的应用不会因为升级 AppPorts 自动恢复，仍需按上面的步骤处理。

## 常见疑问

### 聊天记录会不会丢？

不会。容器数据不受重装影响，重装后应用继续读原有数据。整个过程 AppPorts 也没有删除过数据。

### 我还原了数据还是打不开？

因为签名还没修。还原和重装是两个独立的步骤，缺一不可，见[修复](#修复)。

### 只有微信会这样吗？

不一定。同一台 27 上，重签名过的 QQ 音乐能正常打开。目前的证据指向"系统里是否已存有该应用旧签名的授权记录"，无法提前判断，所以把所有被替换过签名的应用都列出来供你检查。用[升级前检查](#还没升级-先检查)的脚本能扫出完整名单。

### 是 AppPorts 把数据弄坏了吗？

不是，数据完好。但故障的直接来源确实是 AppPorts 旧版本的「同意重签名」选项，1.8.2 已经拿掉了这条路。

## 相关文档

- [容器数据、沙盒与签名身份](/datamigrae/container-identity)：原理
- [挂载迁移](/datamigrae/mount-migration)：新方案
- [为什么外置盘必须是 APFS](/why-apfs)
- [重签名与崩溃防护](/datamigrae/resign)
