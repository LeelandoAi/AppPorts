---
outline: deep
---

# Hinweise zum Upgrade auf macOS 27

::: tip Kurz erklärt
Wenn WeChat oder eine andere App nach einer Neusignierung in einer älteren oder Testversion von AppPorts unter macOS 27 nicht mehr über Finder / Dock startet, beginne mit der Reparatur unten. Stelle alte Containerverknüpfungen zurück und danach die Original-App wieder her, oder installiere die offizielle Version neu. **Lösche keine Datenordner und signiere nicht erneut.** Ein Signaturfehler allein belegt keinen Datenverlust.
:::

## Reparatur

Klicke direkt auf **„Reparieren“** in der App-Zeile oder wähle „Reparaturschritte anzeigen“ im Kontextmenü. Terminalbefehle sind nicht erforderlich. Diese Anleitung beschreibt die aktuelle Entwicklungsversion; ohne Reparaturfenster kannst du die Schritte manuell ausführen. Verbinde das ursprüngliche externe Laufwerk, beende die App vollständig und bewahre Daten und Sicherungen auf.

::: tip Automatisches Neusignieren bei der Anmeldung
Die aktuelle Entwicklungsversion deaktiviert das automatische Neusignieren bei der Anmeldung unter macOS 27 oder neuer und beendet und entfernt die bisherige Anmeldeaufgabe. Falls die Bereinigung nicht abgeschlossen wurde, können Sie sie in den Einstellungen erneut versuchen.

**Aktualisieren und öffnen Sie AppPorts einmal, bevor Sie macOS aktualisieren**, damit die installierte Hintergrundaufgabe die Versionsprüfung erhält. Das Herunterladen der neuen Version allein aktualisiert die alte Aufgabe nicht.
:::

### 1. Über alte Links migrierte Containerdaten zurückholen

Findet das Fenster Containerverknüpfungen zum externen Laufwerk, wähle „Alle wiederherstellen“. Sonst entfällt dieser Schritt. Manuell: Datenverzeichnisse → App-Daten → App auswählen → verknüpfte Container zurückholen. Daten mit APFS-Mount-Migration müssen für eine Signaturreparatur nicht zurückgeholt werden.

### 2. Original-App wiederherstellen oder offiziell neu installieren

- **Vollständige Original-App gesichert:** Nutze „Originalsignatur wiederherstellen“. Auch die echte App auf dem externen Laufwerk lässt sich direkt wiederherstellen. Sie muss dafür nicht zurück auf den Mac. AppPorts prüft, ob die aktuelle App zur Sicherung passt. Eine aktualisierte oder veränderte App benötigt ein passendes offizielles Original.
- **Nur ein alter Identitätsnachweis vorhanden:** Wähle eine offizielle `.app` derselben Version oder installiere über App Store / Entwicklerwebsite neu. Ein Zertifikatsname allein stellt keine Entwicklersignatur wieder her.
- **Externe App durch Installation ersetzen:** Hole sie zuerst lokal zurück, damit der Installer nicht nur den lokalen Starter ersetzt.

**Lösche keine Containerdaten.** Sichere wichtige Daten separat. Der Zugriff auf Chats und Anmeldungen hängt auch von Versionen, Berechtigungen und dem Datenzustand ab. Siehe [Signatursicherung und Wiederherstellung](/de/datamigrae/resign).

### 3. Erneut prüfen und über Finder / Dock starten

Klicke auf „Erneut prüfen“ und öffne die App nach erfolgreicher Signaturprüfung über Finder / Dock. Prüfe auch die vorhandenen Daten. Eine nicht mögliche Prüfung bedeutet weder „ersetzt“ noch „repariert“: Laufwerk verbinden und erneut versuchen. Scans erhalten die Sicherungen. Eine noch startende App kannst du später behandeln; ihr Start beweist keine wiederhergestellte Originalsignatur.

### 4. Optional: Daten weiter migrieren

Wähle nach der Reparatur unter App-Daten das Verzeichnis und „Migrieren“. AppPorts prüft das Ziel und nutzt für Container [APFS-Mount-Migration](/de/datamigrae/mount-migration), ohne die Signatur zu ersetzen. Aktuell ist ein **unverschlüsseltes externes APFS-Laufwerk** erforderlich. Du kannst ein anderes Laufwerk wählen oder die Daten lokal lassen. Erlaube den Zugriff auf Wechselmedien, wenn macOS danach fragt, und verbinde das Laufwerk vor der App-Nutzung. Siehe [APFS vorbereiten](/de/why-apfs#what-to-do).

## Wer ist betroffen?

| Punkt | Beschreibung |
|------|------|
| Auslöser | Upgrade auf macOS 27 |
| Betroffene Apps | Apps, deren Daten unter `~/Library/Containers/` oder `~/Library/Group Containers/` migriert und mit Ad-hoc neu signiert wurden; außerdem manuell per Kontextmenü neu signierte Sandbox-Apps |
| Typisches Verhalten | Doppelklick im Finder / Dock zeigt keine Reaktion; das Symbol erscheint kurz und verschwindet ohne Fehlermeldung. Nicht jede neu signierte App ist betroffen: QQ Music läuft auf demselben Mac mit 27 normal |
| Daten | Ein Signaturfehler allein belegt keine Datenbeschädigung; Originaldaten und Sicherungen aufbewahren |
| Bestätigter Fall | WeChat 4.1.15, macOS 27.0 (26A428) |

Die kurze Erklärung: Erneutes Signieren entfernt die Sandbox-Identität. Wenn macOS 27 den Zugriff auf den Container prüft und bereits eine Berechtigungsregel für die alte Signatur gespeichert hat, wird die neue, nicht passende Signatur abgewiesen. Das WeChat-Protokoll meldet `Failed to match existing code requirement`. Apps ohne alte Regel wie QQ Music werden derzeit zugelassen. Verlorene Rechte etwa für Anmeldedaten im Schlüsselbund kehren dadurch aber nicht zurück. Siehe [Containerdaten, Sandbox und Signaturidentität](/de/datamigrae/container-identity).

AppPorts meldet einen Austausch nur bei gesicherter ursprünglicher Entwickleridentität und bestätigter aktueller Ad-hoc-Signatur der echten App. Zeitüberschreitungen und nicht lesbare externe Apps erfordern eine neue Prüfung. Eine ursprünglich Ad-hoc-signierte App, ihr Migrationsstatus oder ihr lokaler Starter rechtfertigen keine Neusignierung.

## Was nicht hilft

| Versuch | Warum er nicht ausreicht |
|------|-----------|
| Nur Daten lokal wiederherstellen und die Reparatur als erledigt ansehen | Dies behebt nur den fehlenden Zugriff auf externe Daten, nicht die Signatur. Die neu signierte App schließt weiterhin sofort |
| Noch einmal neu signieren | Die Neusignierung ist die Ursache und entfernt nur erneut Berechtigungen |
| Der App Festplattenvollzugriff geben | Kann die Containerprüfung umgehen, stellt aber verlorene Schlüsselbundrechte nicht wieder her. Anmeldesitzungen bleiben problematisch; höchstens eine Übergangslösung |
| Einen erfolgreichen Terminalstart als Reparatur werten | Die App nutzt dabei Terminal-Berechtigungen mit. Entscheidend ist der Doppelklick im Finder / Dock |

## Vor dem Upgrade prüfen

Prüfe zunächst die Markierung „Signatur ersetzt“ in AppPorts und folge der [Reparatur](#reparatur). Keine Warnung garantiert keine macOS-27-Kompatibilität. Das optionale Skript prüft nur erreichbare Pfade aus alten Sicherungen; verschobene Apps, getrennte Laufwerke und Starter können das Ergebnis unvollständig machen.

::: details Optional: technische Prüfung
```bash
BACKUP_DIR="$HOME/Library/Application Support/AppPorts/signature-backups"
for plist in "$BACKUP_DIR"/*.plist; do
  [ -f "$plist" ] || continue
  original=$(/usr/libexec/PlistBuddy -c "Print :signingIdentity" "$plist" 2>/dev/null)
  app=$(/usr/libexec/PlistBuddy -c "Print :originalPath" "$plist" 2>/dev/null)
  case "$original" in ""|ad-hoc) continue ;; esac
  [ -d "$app" ] || continue
  if codesign -dv "$app" 2>&1 | grep -q "Signature=adhoc"; then
    printf "%s\n    %s\n" "$app" "$original"
  fi
done
```
:::

## Nach dem Upgrade die Symptome bestätigen

Starte zuerst über Finder / Dock. Scheitert dies bei bestätigter ersetzter Signatur, folge der [Reparatur](#reparatur). Prüfe andernfalls auch Version, Berechtigungen und Laufwerk.

::: details Optional: technische Prüfung
Ersetze das Beispiel durch den **Pfad der echten App**, nicht ihres Starters. Die Befehle lesen nur Informationen. Vergleiche Ad-hoc mit dem ursprünglichen Eintrag; verweigerter Zugriff im Protokoll ist ein Hinweis, kein eindeutiger Ursachennachweis.

```bash
codesign -dv --verbose=4 "/Applications/WeChat.app" 2>&1 | grep -E "Authority|TeamIdentifier|Signature"
log show --last 1m --style compact 2>/dev/null | grep -i "rejected approval request"
```
:::

## Änderungen in AppPorts 1.8.2

Dies beschreibt die aktuelle Entwicklungsversion:

- Im Standardmodus werden Container per APFS-Mount migriert; Sandbox-Apps werden nicht neu signiert.
- Vollständige Sicherungen stellen die Original-App wieder her. Alte Einträge benötigen eine passende offizielle App.
- Bestätigte Signaturwechsel und nicht mögliche Prüfungen werden getrennt angezeigt; Wiederherstellungsmaterial bleibt erhalten.
- Der [klassische Datenmigrationsmodus](/de/settings#classic-data-migration-mode) ist standardmäßig aus. Ein AppPorts-Update stellt ersetzte Signaturen nicht automatisch wieder her.

## Häufige Fragen

### Gehen Chats verloren?

Ein Signaturfehler allein bedeutet keine beschädigten Chats. Bewahre Container, externe Daten und Sicherungen auf. Nutze keinen Uninstaller, der App-Daten löscht. Prüfe den Zugriff nach der Reparatur; Anmeldeberechtigungen müssen eventuell erneuert werden.

### Warum öffnet die App nach dem Wiederherstellen der Daten noch nicht?

Das Zurückholen der Daten stellt die Entwicklersignatur nicht wieder her. Stelle die Original-App aus einer vollständigen Sicherung wieder her oder installiere offiziell neu. Prüfe bei weiteren Fehlern Version und Berechtigungen.

### Betrifft das nur WeChat?

Nein. Vorhandene Tests zeigen unterschiedliche Ergebnisse. Die Warnung nennt ein zu prüfendes Risiko und sagt keinen Ausfall jeder App voraus.

### Hat AppPorts die Daten beschädigt?

Die beobachteten Startfehler hängen mit der früheren Neusignierung zusammen und belegen keine Datenbeschädigung. Bewahre Originaldaten für weitere Prüfungen auf. Die normale APFS-Containermigration erhält App-Signaturen.

## Weitere Dokumentation

- [Containerdaten, Sandbox und Signaturidentität](/de/datamigrae/container-identity): Hintergründe
- [Mount-Migration](/de/datamigrae/mount-migration): neue Methode
- [Warum das externe Laufwerk APFS verwenden muss](/de/why-apfs)
- [Neusignierung und Schutz vor Abstürzen](/de/datamigrae/resign)
