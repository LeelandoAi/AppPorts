---
outline: deep
---

# Changelog

## v1.8.2 (in Entwicklung)

### Wichtige Änderungen

- **Containerdaten verwenden jetzt die Mount-Migration**: Verzeichnisse unter `~/Library/Containers/` und `~/Library/Group Containers/` werden nicht mehr per symbolischem Link migriert. Stattdessen erstellt AppPorts ein eigenes Volume auf einem externen APFS-Laufwerk und bindet es am ursprünglichen Verzeichnis ein. Die App-Signatur bleibt unverändert. Ein externes APFS-Laufwerk ist erforderlich; beim ersten Öffnen der App müssen Sie den Zugriff auf „Wechselmedien“ erlauben. Siehe [Mount-Migration](/de/datamigrae/mount-migration).
- **Sandbox-Apps werden grundsätzlich nicht mehr neu signiert**: Kontextmenü, „Nach Migration neu signieren“ und das automatische Anmeldeskript überspringen Sandbox-Apps. Eine erneute Signierung durch ältere Versionen kann dazu führen, dass sie unter macOS 27 nicht mehr starten. Abhilfe finden Sie unter [Upgrade auf macOS 27](/de/macos-27).
- **„Originalsignatur wiederherstellen“ repariert**: Vor dem erneuten Signieren wird die Original-App vollständig gesichert. Die Signierung erfolgt in einer Arbeitskopie, die nach erfolgreicher Prüfung sicher eingesetzt wird. Originalsignatur und Berechtigungen können ohne privaten Entwicklerschlüssel wiederhergestellt werden. Für ältere Einträge lässt sich eine offizielle Original-App derselben Version auswählen. Bereits aktualisierte Apps und beschädigte Sicherungen werden nicht durch ein erzwungenes Ersetzen übergangen.
- **Apps mit ersetzter Signatur automatisch erkennen und reparieren**: Die App-Liste zeigt das rote Badge „Signatur ersetzt“, und beim Start erscheint einmalig ein Hinweis. „Reparaturschritte anzeigen“ im Kontextmenü öffnet die Reparaturansicht und führt durch Datenwiederherstellung, Zurückholen auf den Mac, Neuinstallation und Mount-Migration, ohne Daten zu löschen. Nach einer Neuinstallation ist die Originalsignatur wieder vorhanden und das Badge verschwindet. Scans bewahren Wiederherstellungsmaterial auf; erst nach einer erfolgreichen Wiederherstellung durch AppPorts werden die Sicherungen aufgeräumt.
- **Klassischer Datenmigrationsmodus**: Neuer, standardmäßig ausgeschalteter Schalter in den Einstellungen mit Risikobestätigung vor dem Aktivieren. Er stellt das Verfahren aus 1.8.1 mit symbolischen Links und erneutem Signieren wieder her und ist nur für Benutzer vorgesehen, die bereits davon abhängig sind. Verwendet das externe Laufwerk kein APFS, wird empfohlen, den aktuellen Zustand beizubehalten.
- „Automatische Neuzeichnung bei Anmeldung“ ist bei Neuinstallationen standardmäßig ausgeschaltet. Bei Benutzern mit bereits installiertem Anmeldeagenten bleibt die bisherige Einstellung erhalten.
- „Normalisieren“, „Erneut verlinken“ und „Linkdetails“ sind für Containerverzeichnisse außerhalb des klassischen Modus deaktiviert, damit keine symbolischen Links neu erstellt werden.

### Verbesserungen

- **„Mount-Migration“ prüft zuerst lesend und führt dann passend weiter**: Bei unverschlüsseltem APFS-Speicher erklärt AppPorts, wie viel Platz frei wird, dass beim ersten Öffnen der Zugriff erlaubt werden muss und dass das Laufwerk im Alltag angeschlossen bleiben muss. Bei exFAT / NTFS / HFS+, Verschlüsselung, zu wenig Platz oder fehlender Verbindung wird der Grund erklärt. Optionen wie „So belassen“, „Anderen Ort auswählen“ und „Vorbereitung ansehen“ stehen bereit, ohne Änderungen vorzunehmen. Die Bereitschaftsprüfung auf der Willkommensseite und in den Einstellungen verwendet dieselbe Anleitung und verweist Benutzer ohne APFS nicht mehr auf den klassischen Modus.
- **Datenvolumes erscheinen nicht mehr im Finder**: Neue Volumes werden nicht automatisch unter `/Volumes` eingebunden und erhalten beim Einbinden `nobrowse`. Volumes früherer Versionen werden beim nächsten Start oder Anschließen direkt an ihrem bestehenden Mountpunkt ausgeblendet, ohne sie auszuhängen.
- **Verschlüsselte APFS-Laufwerke unterstützen die Mount-Migration vorerst nicht**: Neue Datenvolumes übernehmen das Passwort des ursprünglichen Volumes nicht. AppPorts stoppt und erklärt dies, statt unbemerkt ein unverschlüsseltes Volume anzulegen.
- **Freien Platz vor Migration und Wiederherstellung prüfen**: Reicht der Platz auf dem externen Laufwerk oder dem Mac nicht aus, stoppt AppPorts vor der Volume-Erstellung oder dem Kopieren.
- **Sicherere Wiederherstellung**: Nach dem Aushängen wird nur ein leerer Mountpunkt gelöscht, nicht mehr rekursiv. Temporäre Verzeichnisse erhalten versteckte Namen. Scheitert der letzte Schritt, bleiben externes Volume und Eintrag unverändert, und AppPorts zeigt den Speicherort der lokalen Kopie an.
- **Nur eigene Volumes verändern**: Vor Einbinden, Aushängen und Wiederherstellen wird die Identität des Volumes am Mountpunkt geprüft. Ohne die gemeinsame Sperre mit dem Anmeldeagenten beginnt kein Vorgang. Eine unlesbare Migrationsdatei wird nicht als leer behandelt und überschrieben.
- **Pfad des Anmeldeagenten automatisch korrigieren**: Bei jedem Start prüft AppPorts den Programmpfad des Anmeldeagenten und aktualisiert ihn nach einem Verschieben oder Update. Wird AppPorts direkt aus einem DMG oder dem Ordner „Downloads“ unter einem temporären App Translocation-Pfad gestartet, werden neue Mount-Migrationen blockiert. AppPorts fordert dann dazu auf, die App zuerst in „Programme“ abzulegen.
- Auf Systemen wie macOS 12, die Administratorrechte verlangen, wird die Mount-Migration nach Anzeige des Systemdialogs für das Passwort erneut versucht.
- Container-Volumes werden nach der Anmeldung automatisch wieder eingebunden. Auch das Anschließen eines Laufwerks bei laufendem AppPorts löst das erneute Einbinden aus. Der Anmeldeagent überwacht zusätzlich `/Volumes`, damit das Einbinden vor dem Start der Apps in den Anmeldeobjekten abgeschlossen ist. Eine prozessübergreifende Sperre verhindert, dass Agent und AppPorts während Migration oder Wiederherstellung um Mountpunkte konkurrieren.
- **Der Anmeldeagent wird nicht mehr hinter Anmeldeobjekte eingereiht**: `KeepAlive` mit Neustart nur bei Fehlern kennzeichnet den Agenten als auszuführenden Dienst; `ProcessType: Background` wurde entfernt. Nach der Anmeldung befindet sich die Benutzerdomäne eine Zeit lang im Modus on-demand-only. Mit der alten Definition verzögerte launchd den Agenten um etwa 20 Sekunden, während Apps aus den Anmeldeobjekten bereits nach 3 Sekunden starteten.
- **Erneut einbinden, wenn das System das Volume zuvor automatisch eingebunden hat**: Ist ein Volume bereits unter `/Volumes` eingebunden, meldet `diskutil mount -mountPoint` keinen Fehler. Der Befehl ignoriert den Mountpunkt, gibt trotzdem `mounted` aus und beendet sich mit 0. Dies trat am 2026-09-21 und 09-23 jeweils einmal auf: Der Befehl war erfolgreich, der gewünschte Mountpunkt blieb leer, und WeChat las anschließend ein leeres Verzeichnis. AppPorts prüft jetzt nach jedem Einbinden den tatsächlichen Zielpfad. Stimmt er nicht, wird das Volume aus `/Volumes` ausgehängt und erneut eingebunden, mit höchstens 3 Durchläufen.
- **Die teuerste `diskutil`-Abfrage beim Systemstart entfällt**: Beim Start oder Anschließen bindet das System Volumes zuerst unter `/Volumes/<卷名>` ein. Der Agent erkennt sie jetzt direkt per `statfs` und Markierung im Volume-Wurzelverzeichnis im Mikrosekundenbereich. Die im Versuch 9 Sekunden dauernde Abfrage mit `diskutil info` entfällt. Auf echter Hardware bleiben vom Ermitteln des Mountpunkts bis zum fertigen Einbinden nur `unmount` und `mount`; der Durchlauf dauert etwa 1 Sekunde.
- **Der Anmeldeagent versucht es bei verspätet erscheinenden Laufwerken mehrfach**: Er überwacht `/Volumes` innerhalb seines Prozesses und versucht es bei der nächsten tatsächlichen Änderung erneut. Im Versuch dauerte es vom Erscheinen des Volumes bis zum abgeschlossenen Einbinden etwa 1 Sekunde. Ohne Ereignisse prüft er alle 20 Sekunden erneut, insgesamt bis zu 180 Sekunden lang. Während des Wartens belegt er die gemeinsame prozessübergreifende Sperre mit AppPorts nicht.
- **Leerlaufdurchläufe des Anmeldeagenten füllen das Protokoll nicht mehr**: launchd gleicht `WatchPaths` über FSEvents-Pfadpräfixe ab. Jeder Schreibzugriff auf dem externen Laufwerk weckt daher den Agenten, obwohl meistens nichts zu tun ist. Ein Leerlaufdurchlauf schreibt jetzt nur 3 Zeilen. Einzelheiten zu Einträgen erscheinen nur bei tatsächlichem Einbinden, nicht verfügbaren Volumes oder Fehlern.
- **Halb so viele diskutil-Aufrufe beim Einbinden**: Pro Volume sinkt die Zahl der Abfragen von 4 auf 2. Verfügbarkeit und aktueller Mountpunkt werden gemeinsam durch `diskutil info` ermittelt. Beim stark ausgelasteten Systemstart dauert eine Abfrage etwa eine Sekunde; diese Änderung spart direkt mehrere Sekunden.
- **Volumes werden nicht mehr von Spotlight indexiert**: Nach dem Erstellen schreibt AppPorts `.metadata_never_index` in das Wurzelverzeichnis und entfernt bereits angelegte `.Spotlight-V100`-Verzeichnisse, die bei den beiden getesteten WeChat-Volumes zusammen 110 MB belegten. Früher migrierte Volumes erhalten die Markierung beim nächsten Einbinden. Sie bleibt auf dem Volume und wird bei der Wiederherstellung nicht in das lokale Verzeichnis übernommen.
- Falsche Zuordnungen fremder App-Container behoben, wenn die Bundle ID mit allgemeinen Begriffen wie `mac` oder `desktop` endet, etwa wenn Termius Container von QQ Music anzeigte.
- Fehlende Unterverzeichnisse beim Scan behoben, wenn Containerpfade in der Form `/private/var` vorliegen.

## v1.8.0

### Neue Funktionen

- Benutzerdefinierte lokale Scan-Verzeichnisse: Der „Mac Lokale Apps"-Header hat jetzt einen „+"-Button zum Hinzufügen zusätzlicher lokaler App-Scan-Verzeichnisse. Nützlich für Tools wie JetBrains Toolbox und Steam, die Apps außerhalb von `/Applications` installieren. Hinzugefügte Verzeichnisse werden gespeichert und automatisch überwacht (#48).
- Stub Portal Versions-Synchronisierung: Wenn eine externe App über den App Store aktualisiert wird, werden die Versionsinformationen des lokalen Stub Portals automatisch synchronisiert und der macOS Launch Services-Cache aktualisiert. Das Menü „Öffnen mit" zeigt keine veralteten Versionsnummern mehr an (#50).
- Tool-Verzeichnis-Erkennung für Gradle (`~/.gradle`), Android-Entwicklungsdaten (`~/.android`) und Flutter/Dart-Pub-Cache (`~/.pub-cache`) hinzugefügt (#49).
- Verzeichnismigration hinzugefügt: Beliebige Benutzerordner können im Tab „Verzeichnismigration" hinzugefügt, große Projekte, Modelle, Asset-Bibliotheken oder Tool-Caches in externen Speicher migriert und später neu verlinkt oder wiederhergestellt werden (#54).
- Warnung für geschützte Apps hinzugefügt: Vor der Migration von App Store-Apps oder root-eigenen Apps warnt AppPorts, dass automatisches Löschen oder Ersetzen an Berechtigungen scheitern kann, und empfiehlt, die App zuerst manuell im Finder zu verschieben und danach einen Link zu erstellen (#55).

### Verbesserungen

- Schnellere App-Suche: Info.plist-Lesevorgänge pro App von 7 auf 1 reduziert (durch In-Memory-Cache).
- Scan-Timeout-Schutz: Der `codesign`-Unterprozess hat jetzt einen 10-Sekunden-Timeout.
- Sicherheitslimit für die Verzeichnisgrößenberechnung: Ein Limit von 500.000 Dateien wurde hinzugefügt.
- Scan-Protokollierung: Per-App-TRACE-Protokollierung wurde hinzugefügt.
- Präzisere Datenverzeichnis-Suche: Generische TLD-Wörter wie `app`, `com`, `org` werden jetzt gefiltert.
- Vollständigere Neuverlinkungs-Erkennung für Tool-Verzeichnisse: Wenn das lokale Tool-Verzeichnis fehlt, aber am kanonischen externen Speicherort noch ein verwaltetes Verzeichnis existiert, zeigt AppPorts „Neuverlinkung erforderlich" an; beim Wechsel des externen Speichers wird der Status automatisch aktualisiert.
- Verbesserte Lokalisierung und Barrierefreiheit: App-, Datenverzeichnis- und benutzerdefinierte Verzeichnisstatus, Sortier-/Filterbeschriftungen, Einstellungsschalter und Status-Badges folgen der gewählten Sprache konsistenter und bieten klarere Accessibility-Labels.
- App-Größen verwenden jetzt einen sitzungsweiten Cache, wodurch Fälle reduziert werden, in denen Größen nach dem Aktualisieren wieder als „Berechnung läuft" erscheinen oder verschwinden (#55).
- Sichererer Rollback bei Datenmigration: Vor dem Erstellen des Links benennt AppPorts die lokale Quelle in eine versteckte Sicherheitskopie um. Wenn Link-Erstellung oder Backup-Bereinigung fehlschlagen, bleiben lokale Sicherung und externe Kopie nach Möglichkeit erhalten (#54).

### Behoben

- Behoben: Trae und ähnliche Apps wurden extrem langsam gescannt.
- Behoben: Stub Portal-Versionsinformationen wurden nach App Store-Updates nicht aktualisiert.
- Behoben: Der Aktualisierungsbutton löste keine Versions-Synchronisierung aus.
- Behoben: Datenverzeichnis-Neuverlinkung oder -Normalisierung konnte eine externe normale Datei als Verzeichnis behandeln; normale Dateien werden jetzt zurückgewiesen und unverändert gelassen.
- Behoben: Mehrzeilige Dialogtexte konnten in manchen Sprachen auf Chinesisch zurückfallen; russische UI-Übersetzungen wurden ergänzt, und der Stub Portal-Systemdialog „externer Speicher nicht verbunden" folgt jetzt der Systemsprache (#55).

## v1.7.0

### Neue Funktionen

- Status „Auslagern ausstehend" hinzugefügt: Wenn die echte lokale App neuer ist als die gleichnamige App im externen Speicher, markiert AppPorts sie als ausstehend. Dies zeigt an, dass die lokale neue Version sicher in den externen Speicher migriert und die alte externe Kopie ersetzt werden kann.
- Bestätigung für Neusignierung bei Datenmigration hinzugefügt: Vor der Migration von Daten innerhalb eines App-Containers kann AppPorts fragen, ob die zugehörige App nach der Migration automatisch per Ad-hoc neu signiert werden soll. Dadurch sinkt das Risiko, dass Containerdaten nach der Migration nicht erkannt werden, Warnungen erscheinen oder die App nicht startet (#44).

### UI-Verbesserungen

- Obere Werkzeugleiste neu angeordnet: Die Umschaltflächen für App-Seite und Datenverzeichnis-Seite verwenden jetzt einen kompakteren Stil mit Symbol + Text.
- Aktionsleiste der Datenverzeichnis-Seite optimiert: Umschaltung „Tool-Verzeichnisse / App-Daten", Neusignierung nach Migration, Wiederherstellung der Originalsignatur und Aktualisieren befinden sich jetzt gemeinsam in der oberen Werkzeugleiste.
- App-Status-Badge „Auslagern ausstehend" hinzugefügt, um Apps zu kennzeichnen, deren lokale Version neuer ist als die alte externe Kopie.
- Dialog zur Neusignierungsbestätigung bei Datenmigration lokalisiert, einschließlich Titel, Text und Schaltflächen.

### Verbesserungen

- Sicherheit der App-Migration verbessert: Wenn das externe Ziel bereits existiert, bereinigt AppPorts es nur automatisch, wenn es als alter von AppPorts verwalteter Portal-Eintrag, altes Migrationsrelikt oder als Ziel einer App im Status „Auslagern ausstehend" erkannt wird.
- Prüfung der Datenverzeichnis-Wiederherstellung verstärkt: Automatische Wiederherstellung basiert nicht mehr auf ähnlicher Verzeichnisgröße, sondern erfordert vollständig passende AppPorts metadata.
- App-Datenscan stabiler gemacht: Ergebnisse älterer Scan-Aufgaben überschreiben beim schnellen Wechseln zwischen Apps nicht mehr die Datenverzeichnisliste der aktuell ausgewählten App.
- Escaping für Administratorbefehle und AppleScript verbessert: Pfade mit Anführungszeichen, Backslashes, Leerzeichen oder chinesischen Zeichen werden sicherer verarbeitet.
- Lokalisierung verbessert: Hilfetexte, Hinweise und Datenmigrationsbestätigungen bleiben nach Sprachwechsel nicht mehr teilweise auf Chinesisch oder unvollständig übersetzt; Übersetzungen für alle unterstützten Sprachen wurden ergänzt (#43).

### Fehlerbehebungen

- Behoben: Datenverzeichnismigration konnte ein echtes externes Verzeichnis fälschlich als wiederherstellbares Ziel behandeln.
- Behoben: App-Migration konnte versehentlich eine echte externe App mit gleichem Namen löschen.
- Behoben: Alte externe AppPorts portals / alte Migrationsreste wurden nicht stabil erkannt und bereinigt.
- Behoben: AppleScript oder Administratorbefehle konnten bei Sonderzeichen im Pfad falsch erzeugt werden.
- Behoben: Hintergrundmigration oder Neusignierung nach Migration konnte eine bereits gewechselte App lesen.
- Behoben: Status „Auslagern ausstehend" wurde nicht als Badge in der App-Liste angezeigt.

## v1.6.2

- Neu: Automatische Neuzeichnung bei Anmeldung. Signiert migrierte Apps mit abgelaufenen Signaturen bei jedem Benutzeranmeldung automatisch neu, ohne manuelle Aktion. Standardmäßig aktiviert, kann in den Einstellungen deaktiviert werden
- Verbesserung: Stub Portal verwendet jetzt einen nativen Mach-O-Binärstarter anstelle des Legacy-Bash-Skripts und behebt das Problem, dass doppelklick auf zugehörige Dokumente im Finder die externe App nicht öffnen konnte (#42)
- Verbesserung: Über-Seitenlayout mit scrollbarem Inhaltsbereich optimiert, sodass Inhalte bei kleinem Fenster nicht mehr abgeschnitten werden
- Behoben: Natives Stub Portal wurde fälschlicherweise als reguläre lokale App identifiziert
- Behoben: Natives Stub Portal konnte beim Zurückverschieben in den lokalen Speicher nicht korrekt bereinigt werden
- Behoben: App-Shell wurde bei der Rückverknüpfung als vollständige App behandelt
- Behoben: AutoResignInstaller hat bei fehlgeschlagener Installation stillschweigend Erfolg gemeldet

## v1.6.1

- Behoben: Automatische Neuzeichnung nach Datenverzeichnismigration signiert jetzt korrekt die echte externe App statt der lokalen Stub-Shell
- Behoben: Neuzeichnung- und Signaturwiederherstellungsoperationen lösen jetzt korrekt den echten Pfad für verknüpfte Apps auf
- Behoben: „Neu signiert"-Status-Erkennung für verknüpfte Apps erkennt jetzt korrekt den Signaturstatus der echten externen App
- Verbessert: Log-Ausgabe enthält strukturierte Fehlercodes und zugehörige Pfadinformationen

## v1.6.0

- Migrierte Apps zeigen keine Pfeil-Badges mehr an
- Auto-Update-Apps werden nach Migration durch Updates nicht mehr beschädigt
- App-Signaturverwaltungsfunktion hinzugefügt, um „Beschädigt"-Meldungen nach Migration zu beheben
- Externer Speicher-Trennung zeigt jetzt rote „Verwaiste Verbindung"-Warnungen
- macOS 15.1+ Benutzer können App Store-Apps direkt auf externe Laufwerke installieren
- Datenverzeichnismigration sicherer: Verhindert versehentliche Systemverzeichnis-Migration, automatische Wiederherstellung nach Unterbrechung
- Scannen und Größenberechnung schneller; Liste springt nicht mehr
- Dateikopie in externen Speicher stabiler; keine Fehler mehr bei Unterbrechung
- App-Status-Badges neu gestaltet mit reichhaltigeren Informationen und klickbaren Details
- App-Liste behält Auswahl nach Aktualisierung; Datenverzeichnisse unterstützen Baumansicht
- UI-Verbesserungen: Suche, Sortierung, Gruppenkarten, Icon-Laden usw.
- Martian-Sprachoption hinzugefügt
- Automatisierungstest-Updates

## v1.5.5

- macOS 15.1+ App Store-App externe Installationsunterstützung hinzugefügt
- Automatische Neuzeichnung-Funktion hinzugefügt (automatisch nach Datenverzeichnismigration ausgeführt)
- `LocalizationAuditTests` Lokalisierungsprüfungen hinzugefügt
- Stub Portal Info.plist Generierungslogik verbessert
- Launchpad-Icon-Verlust nach Migration bei einigen Apps behoben

## v1.4.0

- Datenverzeichnis-Baumansicht hinzugefügt
- Tool-Verzeichnis-Erkennung hinzugefügt (30+ Entwicklungstools)
- Diagnosepaket-Export-Funktion hinzugefügt
- Selbstupdate-Erkennung verbessert (Chrome, Edge und andere Custom Updater)
- Auto-Wiederherstellungsmechanismus nach Migrationsunterbrechung behoben

## v1.3.0

- Datenverzeichnismigration-Funktion hinzugefügt
- Code-Signatur-Verwaltung hinzugefügt (Sicherung/Wiederherstellung ursprünglicher Signaturen)
- Sparkle- und Electron-App-Autoerkennung hinzugefügt
- Gesperrte Migration verbessert (`chflags uchg`)
- Badge-Anzeigeprobleme im Finder behoben

## v1.2.0

- Stub Portal-Migrationsstrategie hinzugefügt (ersetzt Deep Contents Wrapper)
- iOS-App-Migrationsunterstützung hinzugefügt (Mac-Version iOS-Apps)
- Batch-Migrationsleistung verbessert
- Problem behoben, bei dem einige Apps nach der Wiederherstellung nicht gestartet werden konnten

## v1.1.0

- Mehrsprachige Unterstützung hinzugefügt (20+ Sprachen)
- App-Suite-Verzeichnismigration hinzugefügt (z. B. Microsoft Office)
- Externe Speicher-Offline-Erkennung verbessert
- Symbolische Link-Durchdringung bei Deep Contents Wrapper-Strategie behoben

## v1.0.0

- Erste offizielle Version
- App-Migration in den externen Speicher unterstützt (Deep Contents Wrapper / Whole App Symlink)
- App-Wiederherstellung und Link-Verwaltung unterstützt
- FolderMonitor-Echtzeit-Dateisystemüberwachung unterstützt
