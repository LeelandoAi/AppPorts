#!/bin/bash
# AppPorts Auto Re-Sign LaunchAgent
# Runs at user login to re-sign migrated apps whose ad-hoc signatures
# may have been invalidated by macOS Gatekeeper after restart.
#
# Installed by AppPorts → ~/Library/Application Support/AppPorts/AppPorts-ReSign.sh
# Triggered by      → ~/Library/LaunchAgents/com.shimoko.AppPorts.re-sign.plist

set -euo pipefail

# 登录任务可能先于 AppPorts 启动；必须在读取偏好、备份或修改文件前检查系统版本。
# 无法识别版本时也跳过。经典模式不能绕过开机重签的版本限制。
SYSTEM_VERSION=$(/usr/bin/sw_vers -productVersion 2>/dev/null) || exit 0
SYSTEM_MAJOR="${SYSTEM_VERSION%%.*}"
case "$SYSTEM_MAJOR" in
    [1-9]|1[0-9]|2[0-6]) ;;
    *) exit 0 ;;
esac

BACKUP_DIR="$HOME/Library/Application Support/AppPorts/signature-backups"
LOG_DIR="$HOME/Library/Application Support/AppPorts"

# 读取 AppPorts 设置中的自定义日志路径，无则用默认路径
CUSTOM_LOG_PATH=$(defaults read com.shimoko.AppPorts LogFilePath 2>/dev/null || true)
if [ -n "$CUSTOM_LOG_PATH" ] && [ -d "$(dirname "$CUSTOM_LOG_PATH")" ]; then
    LOG_FILE="$CUSTOM_LOG_PATH"
else
    LOG_FILE="$LOG_DIR/AppPorts_Log.txt"
fi

mkdir -p "$LOG_DIR"

# 经典数据迁移模式（用户已确认风险）
CLASSIC_MODE=$(defaults read com.shimoko.AppPorts classicDataMigrationEnabled 2>/dev/null || echo 0)

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [RE-SIGN] $1" >> "$LOG_FILE"
}

log "=== 开机重签名任务开始 ==="

if [ ! -d "$BACKUP_DIR" ]; then
    log "签名备份目录不存在，跳过: $BACKUP_DIR"
    exit 0
fi

shopt -s nullglob
backup_files=("$BACKUP_DIR"/*.plist)
shopt -u nullglob

if [ ${#backup_files[@]} -eq 0 ]; then
    log "无签名备份文件，跳过"
    exit 0
fi

log "发现 ${#backup_files[@]} 个签名备份文件"

signed_count=0
skipped_count=0
failed_count=0

for plist in "${backup_files[@]}"; do
    # 完整快照必须由主应用按摘要校验、事务替换；旧脚本不能绕过这一流程。
    schema_version=$(/usr/libexec/PlistBuddy -c "Print :schemaVersion" "$plist" 2>/dev/null || true)
    if [ "$schema_version" = "2" ]; then
        log "SKIP 完整签名备份，请在 AppPorts 中执行签名操作: $(basename "$plist")"
        ((skipped_count++)) || true
        continue
    fi
    # 跳过 stub portal 备份（bundleIdentifier 含 .appports.stub）
    bundle_id=$(/usr/libexec/PlistBuddy -c "Print :bundleIdentifier" "$plist" 2>/dev/null || true)
    if [[ "$bundle_id" == *.appports.stub ]]; then
        log "SKIP stub: $(basename "$plist")"
        ((skipped_count++)) || true
        continue
    fi

    # 跳过非 ad-hoc 签名备份（有开发者证书的不需要重签）
    signing_id=$(/usr/libexec/PlistBuddy -c "Print :signingIdentity" "$plist" 2>/dev/null || true)
    if [ "$signing_id" != "ad-hoc" ] && [ -n "$signing_id" ]; then
        log "SKIP 非 ad-hoc: $(basename "$plist") ($signing_id)"
        ((skipped_count++)) || true
        continue
    fi

    app_path=$(/usr/libexec/PlistBuddy -c "Print :originalPath" "$plist" 2>/dev/null || true)
    if [ -z "$app_path" ] || [ ! -d "$app_path" ]; then
        log "SKIP 路径不存在: $(basename "$plist") → $app_path"
        ((skipped_count++)) || true
        continue
    fi

    # 检查是否可写（root 所有的跳过）
    if [ ! -w "$app_path" ]; then
        log "SKIP 不可写: $app_path"
        ((skipped_count++)) || true
        continue
    fi

    # 沙盒应用跳过：重签名会抹掉沙盒/钥匙串授权，系统升级后应用无法启动。
    # 经典数据迁移模式（用户已确认风险）下不跳过。
    # 不用管道，避免 pipefail 把 codesign 的非零退出误判成「不是沙盒应用」。
    if [ "$CLASSIC_MODE" != "1" ]; then
        entitlements=$(/usr/bin/codesign -d --entitlements - --xml "$app_path" 2>/dev/null || true)
        if [ -z "$entitlements" ]; then
            entitlements=$(/usr/bin/codesign -d --entitlements :- "$app_path" 2>/dev/null || true)
        fi
        case "$entitlements" in
            *com.apple.security.app-sandbox*)
                log "SKIP 沙盒应用: $app_path"
                ((skipped_count++)) || true
                continue
                ;;
        esac
    fi

    # 清理隔离属性
    /usr/bin/xattr -cr "$app_path" 2>/dev/null || true

    # 清理 bundle 根目录杂物
    for stray in .DS_Store __MACOSX .git .svn; do
        if [ -e "$app_path/$stray" ]; then
            rm -rf "$app_path/$stray" 2>/dev/null || true
        fi
    done

    # Ad-hoc 重签名
    if /usr/bin/codesign --force --deep --sign - "$app_path" 2>>"$LOG_FILE"; then
        log "OK  签名成功: $app_path"
        ((signed_count++)) || true
    else
        # 回退无 --deep 的浅层签名
        if /usr/bin/codesign --force --sign - "$app_path" 2>>"$LOG_FILE"; then
            log "OK  浅层签名: $app_path"
            ((signed_count++)) || true
        else
            log "FAIL 签名失败: $app_path"
            ((failed_count++)) || true
        fi
    fi
done

log "=== 完成: 成功=$signed_count 跳过=$skipped_count 失败=$failed_count ==="
