---
outline: deep
---

# Questions fréquentes

## Installation et autorisations

### Quelles autorisations AppPorts demande-t-il ?

AppPorts a besoin de l’**accès complet au disque** pour lire et modifier `/Applications`. Le premier lancement vous guide ; vous pouvez aussi ajouter AppPorts dans Réglages Système → Confidentialité et sécurité → Accès complet au disque.

### Quelles versions de macOS sont prises en charge ?

AppPorts exige au minimum macOS 12.0 (Monterey). macOS 15.1 (Sequoia) et versions ultérieures permettent aussi d’installer les applications App Store directement sur le stockage externe et de les y mettre à jour.

### Puis-je utiliser un NAS ou un disque réseau ?

AppPorts vise surtout les disques externes locaux, SSD ou boîtiers de disque. Les chemins NAS, SMB, rclone ou SFTP peuvent théoriquement être utilisés comme chemins de système de fichiers par macOS, mais leur stabilité, leurs permissions, leur latence et leur reprise après déconnexion dépendent du montage utilisé.

Testez d’abord avec une application sans importance ou des données recréables et vérifiez :

- Le chemin est accessible avant le lancement d’AppPorts.
- Après coupure réseau, il peut être remonté automatiquement au même endroit.
- Le système de fichiers respecte les permissions, attributs étendus et liens symboliques nécessaires.
- Ne commencez pas par WeChat, des machines virtuelles ou des bibliothèques de jeux : ces données sont précieuses ou fréquemment modifiées.

## Migration des applications

### Comment analyser les applications hors de /Applications ?

Cliquez sur « + » à droite de « Applications locales » et choisissez le répertoire supplémentaire. Cela convient à JetBrains Toolbox ou Steam, qui installent dans des emplacements personnalisés. Les répertoires sont enregistrés, analysés au prochain lancement et surveillés automatiquement. Leur nombre apparaît dans l’en-tête ; son menu permet de les consulter ou de les retirer.

### Que faire si l’application ne s’ouvre plus après migration ?

1. Vérifiez que le stockage externe est connecté et accessible.
2. Consultez les badges. « Lien orphelin » signifie que l’application externe a disparu et que le lien doit être supprimé manuellement.
3. Si macOS indique que l’application est endommagée, essayez d’abord une réinstallation, puis « Resigner cette app » dans le menu contextuel si nécessaire. Les applications en bac à sable sont refusées.
4. Si cela ne suffit pas, choisissez « Ramener sur ce Mac » dans la bibliothèque externe pour la faire fonctionner localement.
5. Si l’icône apparaît puis disparaît au double-clic, consultez le [guide macOS 27](/fr/macos-27).

### Que faire du message « application endommagée » ?

Le contrôle de signature de macOS a généralement détecté une modification de la structure de l’application :

1. Téléchargez et réinstallez depuis le site officiel ou l’App Store ; cela suffit souvent.
2. Si le message persiste, choisissez « Resigner cette app » dans le menu contextuel d’AppPorts. Il sauvegarde la signature d’origine et applique une signature Ad-hoc.
3. Les applications en bac à sable sont refusées, car une re-signature pourrait empêcher leur ouverture sous macOS 27. Réinstallez-les.

Voir [Re-signature et prévention des plantages](/fr/datamigrae/resign).

### L’application plante-t-elle si je débranche le stockage externe ?

Le lanceur local Stub Portal utilise `open` pour ouvrir l’application externe. Si le disque manque, l’application ne démarre pas, mais le lanceur lui-même ne plante pas. Reconnectez le disque pour retrouver un fonctionnement normal.

### Pourquoi reste-t-il une flèche de raccourci après migration ?

Cela peut provenir d’une ancienne version d’AppPorts. La version actuelle utilise par défaut Stub Portal pour les `.app` ordinaires et affiche une icône normale, généralement sans flèche.

Si la flèche reste visible, un ancien lien symbolique global est probablement encore utilisé. Ramenez l’application localement, puis migrez-la de nouveau avec la version actuelle.

### Les applications peuvent-elles encore se mettre à jour ?

Cela dépend de leur type :

| Type d’application | Mise à jour automatique | Explication |
|------|:---:|------|
| Application native sans outil de mise à jour intégré | ✓ | Conserve sa méthode habituelle |
| Chrome, Edge, actualiseur personnalisé | ✓ | La mise à jour s’installe localement ; AppPorts affiche « Sortie en attente » si cette version est plus récente |
| Sparkle / Electron | ✗ | Le verrouillage bloque les mises à jour internes ; ramenez l’application localement avant de la mettre à jour |
| App Store, macOS 15.1+ | ✓ | Mise à jour directement sur le disque externe |
| App Store, macOS <15.1 | ✗ | Nouvelle migration manuelle nécessaire |

### Que signifie « Sortie en attente » ?

« Sortie en attente » indique qu’une application réelle locale est plus récente que sa copie externe. Chrome, Edge ou un autre actualiseur personnalisé peut avoir installé la nouvelle version localement, laissant l’ancienne sur le disque externe.

Relancez la migration vers l’extérieur pour remplacer l’ancienne copie. AppPorts associe d’abord les Bundle ID, puis les noms normalisés. Si les versions manquent, ne sont pas comparables ou si des applications homonymes ont des Bundle ID différents, cet état n’apparaît pas.

### Une destination externe existante est-elle écrasée ?

Pas directement. AppPorts ne la nettoie automatiquement avant de poursuivre que dans ces cas :

- L’application est « Sortie en attente » et la destination est l’ancienne copie de la même application.
- La destination est reconnue comme un ancien Stub Portal, Deep Contents Wrapper ou lien symbolique global créé par AppPorts.
- Il s’agit d’un reste d’une ancienne opération de migration AppPorts.

Si une application ou un répertoire réel externe a une origine non confirmée, AppPorts signale un conflit et s’arrête pour éviter de supprimer des données utilisateur.

### Comment migrer une application App Store vers un disque externe ?

**macOS 15.1+** : activez « Télécharger et installer les apps volumineuses sur un disque distinct » dans les réglages de l’App Store et choisissez le même stockage que dans AppPorts.

**macOS <15.1** : activez la migration des applications App Store dans les réglages d’AppPorts. Cette méthode est manuelle ; après chaque mise à jour, migrez de nouveau pour remplacer la copie externe.

### Pourquoi un message d’application protégée apparaît-il ?

Les applications App Store ou appartenant à root sont souvent protégées par les permissions de macOS. AppPorts peut ne pas pouvoir supprimer ou remplacer leur copie locale. Le plus sûr est alors de déplacer l’application vers le stockage externe dans Finder, en saisissant le mot de passe administrateur demandé, puis de créer son lien local depuis AppPorts. La migration automatique reste possible, mais peut échouer faute de permissions.

### Pourquoi plusieurs choix « Ouvrir avec » ou des versions différentes après une mise à jour App Store ?

À partir de la version 1.8.0, AppPorts synchronise automatiquement la version externe avec le Stub Portal local et met à jour « Ouvrir avec ». Utilisez le bouton d’actualisation si un décalage subsiste.

Pour les versions 1.7.0 et antérieures :

1. Ouvrez AppPorts et actualisez les listes locale et externe.
2. Si la version locale est plus récente, migrez-la pour remplacer la copie externe.
3. Si seul le lanceur est incorrect, supprimez son lien puis utilisez « Lier à nouveau au local » depuis la bibliothèque externe.

Sous macOS 15.1+, privilégiez l’installation externe native de l’App Store pour limiter les versions divergentes.

### L’application s’ouvre au double-clic sur un document, mais pas le document

Cela concerne souvent Office ou WPS, qui utilisent les arguments d’association de fichiers. Un ancien Stub Portal pouvait lancer l’application sans transmettre le chemin du document. Mettez à jour vers la version 1.6.2 ou ultérieure, puis ramenez et remigrez l’application, ou utilisez de nouveau « Lier à nouveau au local » depuis la bibliothèque externe.

Si le problème persiste, exportez un diagnostic et ouvrez une Issue en indiquant la source de l’application, App Store, `.pkg` officiel, DMG, etc., ainsi que les étapes de reproduction.

### Peut-on migrer des suites comme Adobe ou Office ?

Vous pouvez essayer, mais il ne s’agit souvent pas d’un simple `.app` : plusieurs applications, composants partagés, services et modules de licence sont liés. AppPorts essaie de traiter la suite au niveau du répertoire ; la compatibilité dépend de sa structure.

Fermez toutes les applications de la suite et vérifiez la connexion ou l’activation avant migration. En cas de licence invalide, de documents impossibles à ouvrir ou de composants introuvables, ramenez la suite localement, puis ne migrez que les grosses applications indépendantes ou leurs données.

### La migration est lente ou semble bloquée

- Une pause d’une ou deux secondes vers 100 % peut correspondre à la création du lanceur et aux vérifications finales.
- Les grosses applications, comme Xcode ou Adobe, demandent naturellement plus de temps.
- Si la progression reste bloquée longtemps, vérifiez la stabilité du stockage externe.
- USB 2.0 est lent ; privilégiez USB 3.0 ou ultérieur, ou Thunderbolt.

## Migration des répertoires de données

### La migration peut-elle faire perdre les données ?

Normalement non. AppPorts copie d’abord toutes les données sur le stockage externe, vérifie la réussite, puis supprime le répertoire local d’origine et crée le lien symbolique. Il tente un retour arrière si une étape échoue.

Si la destination existe déjà, la reprise n’est possible que si `.appports-link-metadata.plist` correspond entièrement aux chemins source et destination ainsi qu’au type de données. Un répertoire réel sans métadonnées correspondantes est un conflit ; une taille similaire ne suffit pas à le reprendre ou l’écraser.

### Quand une migration de données peut-elle perturber l’application ?

- L’application utilise des verrous de fichiers ou un journal SQLite WAL.
- Les attributs étendus peuvent être perdus ou se comporter différemment lors de l’accès par lien symbolique.
- Plusieurs applications d’une même Team partagent `Group Containers`.

Les répertoires de `~/Library/Containers/` et `~/Library/Group Containers/` utilisent le montage plutôt que les liens symboliques. Ils demandent un disque APFS et l’acceptation du dialogue à la première ouverture. Voir [Migration par montage](/fr/datamigrae/mount-migration).

### Peut-on mettre l’historique WeChat sur un disque externe ?

Oui, avec « Migration par montage ». Sélectionnez WeChat dans « App Data ». Les sous-répertoires `xwechat_files` du groupe `Containers`, par compte, ainsi que `Application Support/com.tencent.xinWeChat` peuvent être migrés par montage. Le disque doit être APFS. Autorisez l’accès à la première ouverture de WeChat après migration.

**N’utilisez pas** l’ancienne méthode migration et re-signature : elle empêche WeChat de s’ouvrir sous macOS 27.

### L’historique WeChat n’apparaît plus après migration

Deux cas :

- **Migration par montage avec 1.8.2** : vérifiez le disque connecté, l’état « Monté » et que l’autorisation n’a pas été refusée. Voir le [dépannage](/fr/troubleshooting#l-application-ne-voit-pas-les-donnees-apres-migration-par-montage).
- **Ancienne migration par lien symbolique** : WeChat isolé ne peut pas lire les données hors du conteneur. C’est une restriction du système. Utilisez « Restaurer » pour revenir au local ; si vous aviez accepté la re-signature, réinstallez aussi WeChat depuis son site. Voir [Réparation sous macOS 27](/fr/macos-27#reparation).

**Ne re-signez pas pour réparer** : cela aggrave le problème.

### Mon disque est exFAT : puis-je migrer les données WeChat ?

Non, la migration par montage exige APFS. **Vous pouvez très bien ne rien changer** : laissez les données WeChat sur ce Mac et migrez l’application et les autres données normalement. Plus tard, choisir un autre disque APFS sera le plus simple. Sur le disque actuel, un espace non alloué peut accueillir une partition APFS si la disposition le permet. Si exFAT occupe tout le disque, ni les outils intégrés de macOS ni ceux de Windows ne peuvent le réduire directement : sauvegardez et repartitionnez. L’espace libre dans exFAT n’est pas de l’espace non alloué. L’alternative par image disque a été abandonnée après destruction complète de l’image lors des essais de débranchement. Voir [Pourquoi APFS](/fr/why-apfs#what-to-do). Les applications et autres répertoires ne sont pas soumis à cette restriction.

### La migration par montage ajoute-t-elle des icônes de disque dans Finder ?

Non. AppPorts masque les volumes de données dans la barre latérale et sur le bureau. Ils peuvent apparaître brièvement une ou deux secondes à la connexion, puis disparaître une fois remis en place. Utilitaire de disque affiche toujours les volumes `AppPorts-…` : ils contiennent vos données, ne les effacez pas. Voir [Utilisation quotidienne](/fr/datamigrae/mount-migration#utilisation-quotidienne).

### Pourquoi ne puis-je pas migrer par montage sur un disque chiffré ?

Le nouveau volume n’hérite pas du mot de passe d’origine. Migrer normalement placerait les données protégées sur un volume sans mot de passe. AppPorts s’arrête plutôt que de réduire discrètement leur protection. Voir [Disques externes chiffrés](/fr/why-apfs#encrypted-drives).

### Que faire avant de supprimer AppPorts ?

Si vous avez utilisé la migration par montage, restaurez d’abord ces répertoires localement avec « Restaurer » dans « App Data ». Sinon, les données restent sur les volumes externes, mais rien ne les remonte à la connexion et les applications voient des répertoires vides. Réinstaller et ouvrir AppPorts une fois rétablit l’accès.

### Une ancienne migration explique-t-elle qu’une application ne s’ouvre plus sous macOS 27 ?

Les données ne sont pas endommagées : c’est la signature. Si vous avez accepté une re-signature en migrant les conteneurs avec une ancienne version, l’identité de bac à sable a été retirée. macOS 27 refuse alors l’accès au propre conteneur de l’application. Restaurez les données puis réinstallez l’application ; voir le [guide macOS 27](/fr/macos-27).

### Crossover, Parallels, machines virtuelles et bibliothèques de jeux se prêtent-ils à la migration ?

L’application elle-même n’est pas toujours volumineuse. Ce sont souvent les images de machines virtuelles, conteneurs, jeux et caches de modèles qui occupent l’espace. Vérifiez d’abord les grands répertoires reconnus dans « Répertoires de données » et « Répertoires d'outils ».

Pour les disques virtuels, bases de données ou fichiers souvent modifiés, assurez-vous que le stockage externe est stable et faites une sauvegarde. Les montages réseau sont déconseillés pour ces écritures fréquentes.

### Comment restaurer un répertoire migré ?

Repérez-le dans la liste et cliquez sur « Restaurer ». Une migration par lien symbolique recopie les données localement, puis supprime le lien et la copie externe. Une migration par montage recopie les données du volume, puis supprime celui-ci. Gardez le disque externe connecté.

## Autres questions

### AppPorts collecte-t-il mes données ?

Non. AppPorts fonctionne entièrement hors ligne et ne collecte ni n’envoie vos données. Les journaux restent dans `~/Library/Application Support/AppPorts/`.

### Comment signaler un problème ?

Utilisez les [Issues du projet](https://github.com/wzh4869/AppPorts/issues). Joignez si possible un diagnostic depuis la barre des menus → Journaux → « Exporter le paquet de diagnostic » pour faciliter l’analyse.
