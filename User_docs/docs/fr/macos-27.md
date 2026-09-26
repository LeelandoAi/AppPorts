---
outline: deep
---

# Guide de mise à niveau vers macOS 27

::: tip L’essentiel
Si vous avez migré les données de conteneur de WeChat ou d’une autre application avec AppPorts et accepté la re-signature, ces applications **peuvent** quitter immédiatement après un double-clic sous macOS 27. C’est le cas de WeChat ; QQ Music et d’autres s’ouvrent encore lors des essais. **Les données ne sont pas endommagées** et il n’est pas nécessaire de les migrer de nouveau. Restaurez-les localement, puis réinstallez l’application depuis une source officielle. Pour les remettre ensuite sur le disque externe, utilisez la nouvelle [migration par montage](/fr/datamigrae/mount-migration).
:::

## Qui est concerné ?

| Élément | Explication |
|------|------|
| Déclencheur | Mise à niveau vers macOS 27 |
| Applications concernées | Applications dont les données de `~/Library/Containers/` ou `~/Library/Group Containers/` ont été migrées puis re-signées avec Ad-hoc, ou applications en bac à sable re-signées manuellement par le menu contextuel |
| Symptômes typiques | Aucune réaction au double-clic dans Finder / Dock ; l’icône apparaît brièvement puis disparaît, sans dialogue d’erreur. Toutes les applications re-signées ne sont pas touchées : QQ Music fonctionne sur le même Mac sous 27 |
| Données | Intactes, y compris l’historique et la session de connexion |
| Cas confirmé | WeChat 4.1.15, macOS 27.0 (26A428) |

La re-signature retire l’identité de bac à sable. Quand macOS 27 vérifie le droit de l’application à accéder à son conteneur, une autorisation déjà enregistrée pour l’ancienne signature peut ne plus correspondre à la nouvelle. L’accès est alors refusé ; WeChat journalise `Failed to match existing code requirement`. Les applications sans ancien enregistrement, comme QQ Music, passent actuellement, mais leurs autorisations perdues, notamment celles du trousseau, ne sont pas rétablies. Voir [Données de conteneur, bac à sable et identité de signature](/fr/datamigrae/container-identity).

## Avant la mise à niveau : vérifier

Le script suivant liste les applications dont AppPorts a remplacé la signature. Chaque résultat est une application susceptible de rencontrer ce problème après mise à niveau.

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

Effectuez si possible les étapes de [réparation](#reparation) avant la mise à niveau. Au minimum, conservez la liste pour savoir quelles applications vérifier ensuite.

## Après la mise à niveau : confirmer les symptômes

```bash
# 1. 签名（出现 Signature=adhoc 且 TeamIdentifier=not set 即已被重签名）
codesign -dv --verbose=4 /Applications/WeChat.app 2>&1 | grep -E "Authority|TeamIdentifier|Signature"

# 2. 复现并看系统日志
open -a /Applications/WeChat.app; sleep 3
log show --last 1m --style compact 2>/dev/null | grep -i "rejected approval request"
```

La présence de `kTCCServiceSystemPolicyAppData ... denied` à l’étape 2 confirme le problème. Une liste plus complète se trouve dans la [vérification de l’identité du conteneur](/fr/datamigrae/container-identity#verification).

## Réparation

AppPorts 1.8.2 détecte automatiquement ces applications, affiche le badge rouge « Signature remplacée » et un rappel au lancement. Le menu contextuel « Voir les étapes de réparation » ouvre un panneau présentant l’état et les boutons de chaque étape, sans supprimer de données. Les opérations manuelles suivent le même ordre. **Ne changez pas cet ordre.**

### Étape 1 : restaurer les données de conteneur localement

Cliquez sur « Tout restaurer » dans le panneau, ou ouvrez « Répertoires de données » → « App Data », sélectionnez l’application et utilisez « Restaurer » pour chaque conteneur à l’état « Lié ». Une application qui ne s’ouvre plus ne sera pas bloquée par le contrôle d’exécution.

Cette étape doit venir en premier : après réinstallation, l’application retrouve son bac à sable et ne peut pas lire les données derrière les liens symboliques. Elle semblerait encore vide, donnant l’impression que la réparation a échoué.

Après restauration, vous pouvez vérifier :

```bash
find ~/Library/Containers/<Bundle ID> -maxdepth 6 -type l -exec readlink {} \; 2>/dev/null
# 没有输出，或输出里没有 /Volumes/... 就对了
```

### Étape 2 : ramener l’application sur ce Mac

Uniquement si l’application elle-même est sur le disque externe. Dans ce cas, `/Applications` contient le lanceur AppPorts. Réinstaller par-dessus écraserait ce lanceur et laisserait la copie externe orpheline. Cliquez sur « Ramener sur ce Mac » dans le panneau ou sélectionnez l’application dans « Disque externe » et utilisez cette commande. Après réinstallation, vous pourrez migrer de nouveau l’application sur le disque externe.

### Étape 3 : réinstaller l’application si elle ne s’ouvre pas

Si l’application fonctionne encore normalement sous 27, passez directement à l’étape 4. Sinon, quittez-la complètement et réinstallez-la par-dessus depuis sa source officielle : App Store pour une application App Store, avec le bouton « Ouvrir l’App Store » du panneau, ou le site officiel pour les autres. **Ne supprimez pas les conteneurs.** La réinstallation ne les modifie pas ; historique et session restent présents.

Cliquez ensuite sur « Vérifier à nouveau » ou utilisez la première commande de vérification pour confirmer une signature `Authority=Developer ID Application: ...` ou `Apple Mac OS Application Signing`. Le badge « Signature remplacée » disparaît après restauration de la signature. Une analyse ordinaire conserve les sauvegardes ; elles ne sont supprimées qu’après une restauration réussie via AppPorts.

::: tip Une sauvegarde complète suffit ; une ancienne sauvegarde exige l’application d’origine
« Restaurer la signature originale » utilise désormais une sauvegarde complète de l’application d’origine, sans clé privée du développeur. Un ancien enregistrement ne contenant que le nom de l’identité ne permet pas une restauration directe. Choisissez un `.app` officiel de même version ou réinstallez comme indiqué ci-dessus. Dans tous les cas, restaurez d’abord les données de conteneur migrées en mode classique. Voir [Sauvegarde et restauration de la signature](/fr/datamigrae/resign#sauvegarde-et-restauration-de-la-signature).
:::

### Étape 4, facultative : remettre les données sur le disque externe par montage

Après réinstallation, ouvrez AppPorts. Les conteneurs affichent « Migration par montage » au lieu de « Migrate ». Cliquez et suivez les indications. À la première ouverture de l’application, **autorisez** l’accès aux volumes amovibles. Le disque externe doit être APFS non chiffré. AppPorts vérifie d’abord sa situation et explique la suite. S’il n’est pas APFS, vous pouvez simplement laisser les données sur ce Mac ; voir [Pourquoi APFS](/fr/why-apfs#what-to-do).

## Ce qu’il ne faut pas faire

| Action | Pourquoi elle ne suffit pas |
|------|------|
| Considérer la seule restauration des données comme une réparation | Elle rétablit l’accès aux données externes, pas la signature. Une application re-signée peut toujours quitter immédiatement |
| Re-signer une nouvelle fois | C’est la cause du problème ; cela retire encore les autorisations |
| Ajouter l’application à Accès complet au disque | Peut contourner le contrôle du conteneur, mais les autorisations du trousseau sont perdues et la session reste problématique. Solution temporaire seulement |
| Considérer l’ouverture depuis Terminal comme une réparation | L’application emprunte les permissions de Terminal. Vérifiez avec Finder / Dock |

## Ce qu’AppPorts 1.8.2 a changé

- Les conteneurs utilisent la [migration par montage](/fr/datamigrae/mount-migration), sans lien symbolique, que le programme principal soit isolé ou non.
- Les applications en bac à sable ne sont plus re-signées par le menu contextuel, « Re-signer après la migration » ou le script de connexion.
- « Restaurer la signature originale » restaure l’application d’origine complète, sa signature et ses autorisations, sans clé privée ; un ancien enregistrement permet de choisir l’original officiel de même version.
- Les signatures remplacées sont détectées : badge rouge « Signature remplacée », rappel au lancement et panneau « Voir les étapes de réparation ».
- Les anciens liens de conteneurs restent reconnus comme « Lié » et « Restaurer » reste disponible. « Normaliser » et « Relier » sont désactivés pour éviter de recréer des liens symboliques.
- Un **mode classique de migration des données**, désactivé par défaut et soumis à confirmation, reste disponible pour les utilisateurs dépendant de l’ancienne méthode. Voir les [réglages](/fr/settings#classic-data-migration-mode). Un disque non APFS ne nécessite pas de l’activer : gardez les données de conteneur localement.

La mise à jour d’AppPorts ne restaure pas automatiquement une application déjà re-signée. Suivez les étapes ci-dessus.

## Questions fréquentes

### Vais-je perdre mon historique ?

Non. Réinstaller ne modifie pas les données de conteneur et l’application continue de lire les données existantes. AppPorts ne les supprime à aucun moment de cette procédure.

### J’ai restauré les données, mais l’application ne s’ouvre toujours pas

La signature n’est pas encore réparée. Restauration et réinstallation sont deux étapes distinctes, toutes deux nécessaires. Voir [Réparation](#reparation).

### Cela ne concerne-t-il que WeChat ?

Pas forcément. QQ Music, re-signé sur le même Mac sous 27, fonctionne normalement. Les éléments actuels indiquent que la présence d’une ancienne autorisation liée à la signature est déterminante, ce qui ne peut pas être prévu. Toutes les applications dont la signature a été remplacée sont donc proposées à la vérification. Le script [avant mise à niveau](#avant-la-mise-a-niveau-verifier) donne la liste complète.

### AppPorts a-t-il endommagé mes données ?

Non, elles sont intactes. Toutefois, l’origine directe de la panne est bien l’option d’acceptation de la re-signature des anciennes versions. La version 1.8.2 a retiré cette voie.

## Documents associés

- [Données de conteneur, bac à sable et identité de signature](/fr/datamigrae/container-identity) : fonctionnement
- [Migration par montage](/fr/datamigrae/mount-migration) : nouvelle méthode
- [Pourquoi le disque externe doit être APFS](/fr/why-apfs)
- [Re-signature et prévention des plantages](/fr/datamigrae/resign)
