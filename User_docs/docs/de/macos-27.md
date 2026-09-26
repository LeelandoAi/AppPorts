---
outline: deep
---

# Hinweise zum Upgrade auf macOS 27

::: tip Kurz erklärt
Wenn du mit AppPorts Containerdaten etwa von WeChat migriert und dabei dem erneuten Signieren zugestimmt hast, können diese Apps nach dem Upgrade auf macOS 27 **möglicherweise** direkt nach dem Doppelklick schließen. Bei WeChat passiert dies; QQ Music ließ sich im Test weiterhin öffnen. **Die Daten sind nicht beschädigt** und müssen nicht erneut migriert werden. Stelle die Daten lokal wieder her und installiere die App aus offizieller Quelle neu. Danach kannst du sie mit der neuen [Mount-Migration](/de/datamigrae/mount-migration) wieder extern ablegen.
:::

## Wer ist betroffen?

| Punkt | Beschreibung |
|------|------|
| Auslöser | Upgrade auf macOS 27 |
| Betroffene Apps | Apps, deren Daten unter `~/Library/Containers/` oder `~/Library/Group Containers/` migriert und mit Ad-hoc neu signiert wurden; außerdem manuell per Kontextmenü neu signierte Sandbox-Apps |
| Typisches Verhalten | Doppelklick im Finder / Dock zeigt keine Reaktion; das Symbol erscheint kurz und verschwindet ohne Fehlermeldung. Nicht jede neu signierte App ist betroffen: QQ Music läuft auf demselben Mac mit 27 normal |
| Daten | Intakt, einschließlich Chats und Anmeldesitzungen |
| Bestätigter Fall | WeChat 4.1.15, macOS 27.0 (26A428) |

Die kurze Erklärung: Erneutes Signieren entfernt die Sandbox-Identität. Wenn macOS 27 den Zugriff auf den Container prüft und bereits eine Berechtigungsregel für die alte Signatur gespeichert hat, wird die neue, nicht passende Signatur abgewiesen. Das WeChat-Protokoll meldet `Failed to match existing code requirement`. Apps ohne alte Regel wie QQ Music werden derzeit zugelassen. Verlorene Rechte etwa für Anmeldedaten im Schlüsselbund kehren dadurch aber nicht zurück. Siehe [Containerdaten, Sandbox und Signaturidentität](/de/datamigrae/container-identity).

## Vor dem Upgrade prüfen

Das folgende Skript listet Apps auf, deren Signatur AppPorts ersetzt hat. Jede ausgegebene App könnte nach dem Upgrade Probleme haben.

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

Am besten führst du die [Reparatur](#reparatur) schon vor dem Upgrade aus. Notiere zumindest die Liste, damit du danach weißt, welche Apps zu prüfen sind.

## Nach dem Upgrade die Symptome bestätigen

```bash
# 1. 签名（出现 Signature=adhoc 且 TeamIdentifier=not set 即已被重签名）
codesign -dv --verbose=4 /Applications/WeChat.app 2>&1 | grep -E "Authority|TeamIdentifier|Signature"

# 2. 复现并看系统日志
open -a /Applications/WeChat.app; sleep 3
log show --last 1m --style compact 2>/dev/null | grep -i "rejected approval request"
```

Erscheint in Schritt 2 `kTCCServiceSystemPolicyAppData ... denied`, ist die Ursache bestätigt. Eine vollständigere Prüftabelle steht unter [Containerdaten, Sandbox und Signaturidentität](/de/datamigrae/container-identity#selbst-prufen).

## Reparatur

AppPorts 1.8.2 erkennt diese Apps automatisch. Sie tragen die rote Markierung „Signatur ersetzt“, und beim Start erscheint einmal ein Hinweis. „Reparaturschritte anzeigen“ im Kontextmenü öffnet ein Fenster mit dem Status und den Schaltflächen für die folgenden Schritte. Dabei werden keine Daten gelöscht. Auch manuell gilt dieselbe Reihenfolge. **Ändere sie nicht.**

### Schritt 1: Containerdaten lokal wiederherstellen

Klicke im Reparaturfenster auf „Alle wiederherstellen“. Alternativ wählst du unter „Datenverzeichnisse“ → „App Data“ die App und stellst jeden mit „Verknüpft“ markierten Containerordner mit „Wiederherstellen“ zurück. Da die App ohnehin nicht öffnet, blockiert die Prüfung auf laufende Apps dies nicht.

Dieser Schritt muss zuerst kommen: Nach der Neuinstallation ist die App wieder eine normale Sandbox-App und kann Daten hinter symbolischen Links nicht lesen. Sonst bleibt sie leer, und es sieht aus, als sei die Reparatur fehlgeschlagen.

Prüfe nach der Wiederherstellung bei Bedarf:

```bash
find ~/Library/Containers/<Bundle ID> -maxdepth 6 -type l -exec readlink {} \; 2>/dev/null
# 没有输出，或输出里没有 /Volumes/... 就对了
```

### Schritt 2: Die App selbst lokal zurückholen

Nur nötig, wenn die App selbst bereits extern liegt. Unter `/Applications` befindet sich dann nur die AppPorts-Startapp. Darüberinstallieren überschreibt sie und lässt die externe Kopie ohne Verknüpfung zurück. Wähle im Reparaturfenster oder unter „Externes Laufwerk“ die App und klicke auf „Zurück auf diesen Mac“. Nach der Installation kannst du die App bei Bedarf erneut extern migrieren.

### Schritt 3: App neu installieren, falls sie nicht öffnet

Öffnet die App unter 27 weiterhin normal, kannst du diesen Schritt überspringen und mit Schritt 4 die Daten auf Mount-Migration umstellen. Andernfalls beende die App vollständig und installiere aus offizieller Quelle darüber: App Store-Apps aus dem App Store, wofür das Fenster „App Store öffnen“ anbietet, andere Apps von der offiziellen Website. **Lösche die Containerordner nicht.** Die Neuinstallation verändert sie nicht; Chats und Anmeldesitzungen bleiben erhalten.

Klicke danach auf „Erneut prüfen“ oder bestätige mit dem ersten Prüfbefehl eine Signatur wie `Authority=Developer ID Application: ...` oder `Apple Mac OS Application Signing`. Nach Wiederherstellung der Signatur verschwindet „Signatur ersetzt“. Normales Scannen bewahrt die Sicherungen; erst eine abgeschlossene Wiederherstellung durch AppPorts bereinigt die zugehörige Sicherung.

::: tip Vollständige Sicherungen lassen sich direkt wiederherstellen; alte benötigen die Original-App
„Originalsignatur wiederherstellen“ verwendet jetzt eine vollständige Sicherung der ursprünglichen App und benötigt keinen privaten Entwicklerschlüssel. Alte Datensätze, die nur den Identitätsnamen enthalten, reichen weiterhin nicht für eine direkte Wiederherstellung. Wähle dafür eine offizielle Original-`.app` derselben Version oder installiere wie oben neu. In beiden Fällen müssen zuerst die Containerdaten aus dem klassischen Modus zurückgeholt werden. Siehe [Signatur sichern und wiederherstellen](/de/datamigrae/resign#signatur-sichern-und-wiederherstellen).
:::

### Schritt 4, optional: Daten mit Mount-Migration wieder extern ablegen

Öffne AppPorts nach der Neuinstallation erneut. Bei Containerordnern erscheint „Mount-Migration“ statt „Migrate“. Klicke darauf und folge den Hinweisen. Beim ersten Öffnen der App fragt macOS nach Zugriff auf Wechselmedien. **Erlaube ihn.** Das externe Laufwerk muss unverschlüsseltes APFS verwenden. AppPorts prüft dies zuerst und erklärt den nächsten Schritt. Ohne APFS können die Daten problemlos lokal bleiben; siehe [Warum das externe Laufwerk APFS verwenden muss](/de/why-apfs#what-to-do).

## Was nicht hilft

| Versuch | Warum er nicht ausreicht |
|------|-----------|
| Nur Daten lokal wiederherstellen und die Reparatur als erledigt ansehen | Dies behebt nur den fehlenden Zugriff auf externe Daten, nicht die Signatur. Die neu signierte App schließt weiterhin sofort |
| Noch einmal neu signieren | Die Neusignierung ist die Ursache und entfernt nur erneut Berechtigungen |
| Der App Festplattenvollzugriff geben | Kann die Containerprüfung umgehen, stellt aber verlorene Schlüsselbundrechte nicht wieder her. Anmeldesitzungen bleiben problematisch; höchstens eine Übergangslösung |
| Einen erfolgreichen Terminalstart als Reparatur werten | Die App nutzt dabei Terminal-Berechtigungen mit. Entscheidend ist der Doppelklick im Finder / Dock |

## Änderungen in AppPorts 1.8.2

- Containerordner verwenden grundsätzlich [Mount-Migration](/de/datamigrae/mount-migration) statt symbolischer Links, unabhängig von der Sandbox-Eigenschaft der Haupt-App.
- Sandbox-Apps werden an allen Eingängen vom erneuten Signieren ausgeschlossen: Kontextmenü, „Nach Migration neu signieren“ und automatisches Signieren bei der Anmeldung.
- „Originalsignatur wiederherstellen“ stellt die vollständige Original-App samt Signatur und Berechtigungen wieder her, ohne privaten Entwicklerschlüssel. Alte Datensätze können mit einer offiziellen Original-App derselben Version ergänzt werden.
- Apps mit ersetzter Signatur werden automatisch erkannt: rote Markierung „Signatur ersetzt“, Starthinweis und „Reparaturschritte anzeigen“ im Kontextmenü.
- Frühere symbolische Containerlinks werden weiterhin als „Verknüpft“ erkannt, und „Wiederherstellen“ bleibt verfügbar. „Normalisieren“ und „Erneut verlinken“ sind für Container deaktiviert, damit keine neuen symbolischen Links entstehen.
- Ein **klassischer Datenmigrationsmodus** bleibt für Nutzer erhalten, die bereits auf die alte Methode angewiesen sind. Er ist standardmäßig aus und erfordert eine Risikobestätigung. Siehe [Einstellungen](/de/settings#classic-data-migration-mode). Ohne APFS sollten Containerdaten lokal bleiben; dafür muss der Modus nicht aktiviert werden.

Ein AppPorts-Update stellt bereits neu signierte Apps nicht automatisch wieder her. Führe die Schritte oben weiterhin selbst aus.

## Häufige Fragen

### Gehen Chats verloren?

Nein. Die Neuinstallation betrifft die Containerdaten nicht. Die App liest danach ihre bisherigen Daten weiter. Auch AppPorts löscht im gesamten Ablauf keine Daten.

### Warum öffnet die App nach dem Wiederherstellen der Daten noch nicht?

Die Signatur ist noch nicht repariert. Datenwiederherstellung und Neuinstallation sind zwei getrennte, notwendige Schritte. Siehe [Reparatur](#reparatur).

### Betrifft das nur WeChat?

Nicht unbedingt. Neu signiertes QQ Music öffnet sich auf demselben Mac mit 27 normal. Die bisherigen Hinweise sprechen dafür, dass eine gespeicherte Zugriffsregel für die alte Signatur entscheidend ist. Das lässt sich nicht vorab sicher vorhersagen. Deshalb werden alle Apps mit ersetzter Signatur zur Prüfung aufgelistet. Das Skript unter [Vor dem Upgrade prüfen](#vor-dem-upgrade-prufen) liefert die vollständige Liste.

### Hat AppPorts die Daten beschädigt?

Nein, die Daten sind intakt. Die unmittelbare Ursache des Fehlers ist aber tatsächlich die frühere AppPorts-Option zum Zustimmen zur Neusignierung. Dieser Weg wurde in 1.8.2 entfernt.

## Weitere Dokumentation

- [Containerdaten, Sandbox und Signaturidentität](/de/datamigrae/container-identity): Hintergründe
- [Mount-Migration](/de/datamigrae/mount-migration): neue Methode
- [Warum das externe Laufwerk APFS verwenden muss](/de/why-apfs)
- [Neusignierung und Schutz vor Abstürzen](/de/datamigrae/resign)
