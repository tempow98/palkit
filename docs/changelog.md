# Changelog

Format : [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/).

## [Non publié]

### Corrigé — 2026-08-15 — Le `settings.json` est créé au premier lancement

`config.load()` se contentait d'appliquer ses défauts en mémoire quand le fichier était
absent. Il n'y avait donc **rien à éditer, et rien qui documente les réglages disponibles** —
Lucas a cherché un `settings.json` que le mod n'avait jamais écrit. Le fichier est désormais
créé avec les valeurs par défaut, requêtes comprises, et le log dit où il est.

### Ajouté — 2026-08-15 — M2 v1 : recherche, tri et doublons dominés

- `shared/palfilter.lua` — moteur de requête **pur** : `match`, `filter`, `sort`, `top`,
  `dominates`, `findDominated`. Aucune dépendance au jeu — ce qui change tout pour ce
  projet : chaque aller-retour de test coûte une session de jeu à Lucas, alors qu'un module
  pur se valide **sur l'export réel**. Les 743 Pals du run 6 ont servi de banc d'essai avant
  la moindre ligne livrée. Le même moteur servira tel quel à M3 (Paldeck)
- `mods/PalKitBox` — touche **`F12`** : exécute les requêtes déclarées dans `settings.json`,
  résume dans le log et écrit `palbox-recherche-<date>.json`
- Quatre requêtes livrées par défaut : meilleurs IVs, légendaires, rares, **doublons dominés**
- `scripts/test-shared.lua` — 120 tests (28 de plus)

**La dominance repose sur trois choix explicites**, tous documentés dans le module : même
espèce ; **même genre par défaut** (conseiller de relâcher la seule femelle d'une espèce
serait un mauvais conseil pour l'élevage — `ignoreGender` pour passer outre) ; et l'on compare
**l'inné, pas l'acquis** — IVs et passifs sont fixés à la naissance, tandis que niveau,
condensation et âmes se rattrapent. Un niveau 1 aux IVs parfaits n'est donc pas dominé par un
niveau 50 médiocre. Deux Pals strictement identiques ne se dominent pas mutuellement : seul le
second est signalé, sinon on relâcherait la paire entière.

Sur l'export réel : **14 dominés sur 743**, calculés en 2 ms, sans une seule incohérence
(aucun « dominé » n'a d'IV supérieur à son dominant).

### Validé — 2026-08-15 (run 6) — M2 v0 terminé, et M1 débloqué

**Deux verrous tombent le même soir.**

**M2 v0 est terminé.** Le parcours synchronisé fonctionne : **743 Pals lus, 0 coquille,
0 avertissement**, 32 pages en 8,2 s, page de synchronisation restaurée à sa valeur d'origine.
Les données sont cohérentes de bout en bout — 310 espèces, niveaux 1→80, IVs 0→100, 674 Pals
sur 743 portent au moins un passif, 5 rares. Le JSON fait 446 Ko contre 119 Ko au run
précédent, pour le même nombre d'entrées : c'est la mesure de ce qui manquait.

**M1 est débloqué, et l'arbitrage `.pak` est clos.** Avec les mesures prises 500 ms après
l'ajout — le temps que Slate fasse sa passe de layout — deux widgets du jeu occupent une
place réelle à l'écran, instanciés en Lua pur :

| Widget | `IsVisible` | `DesiredSize` |
|---|---|---|
| `WBP_Ingame_Compass_C` | `true` | **800 × 122** |
| `WBP_Map_Body_C` | `true` | **155,75 × 332,75** |
| `WBP_CompassIconBase_C` | `false` | `0 × 0` — une icône attend des données que `Create()` ne fournit pas |

Le jeu reste jouable, le curseur n'est pas capturé. **La minimap n'a pas besoin d'un `.pak`.**
Leçon retenue : viser les widgets **autoporteurs**, pas leurs briques.

- `shared/json.lua` — `json.array()` : marque une table comme liste, même vide. Sans ça, un
  export sans avertissement sortait `"warnings": {}` et un export dégradé `"warnings": [...]` —
  un champ qui change de type selon son contenu est un piège pour qui lit le fichier
- `mods/PalKitBox` — `warnings` et `notes` sont marquées comme listes
- `docs/sdk-notes.md` — `EPalGenderType` confirmé (`0 = None`, `1 = Male`, `2 = Female`) ;
  M2 et la voie d'affichage passent en ✅
- `scripts/test-shared.lua` — 92 tests (4 de plus) sur le marquage des listes

### Ajouté — 2026-08-15 (run 5) — Parcours synchronisé des pages de la Palbox

Le comptage honnête a confirmé le diagnostic : **30 Pals lus, 697 coquilles, 1 page sur 32**.
Et il a écarté une hypothèse — `TargetContainer` rend **960 slots sur 960**, donc l'*accès*
n'a jamais été en cause. C'est bien la **réplication** : le client ne reçoit que la page
synchronisée. `CachedNonEmptySlots_InServer` est vide côté client.

Le jeu expose la solution : **`APalPlayerState::RequestPalBoxSyncPage_ToServer(pageIndex)`**
(`UFUNCTION(BlueprintCallable, Reliable, Server)`), la fonction que l'écran Palbox appelle
lui-même quand le joueur tourne les pages.

- `mods/PalKitBox` — la collecte devient une passe asynchrone : demande de synchronisation,
  attente de la réponse (250 ms), lecture de la page, page suivante. ~8 s pour 32 pages. La
  page d'origine est **restaurée** en fin de parcours
- `mods/PalKitBox` — `syncPages` / `syncDelayMs` dans `settings.json` : `syncPages = false`
  rend au mod un comportement strictement passif, au prix d'un export limité à la page
  courante
- `mods/PalKitBox` — le cartouche du fichier ne prétend plus que le mod « ne modifie rien » :
  il ne modifie **aucune donnée**, mais il change un état de synchronisation, et c'est écrit
  noir sur blanc avec la raison

**Ce choix sort du read-only strict du brief §3.2** — non parce qu'une donnée serait modifiée
(aucune sauvegarde n'est touchée : on demande l'envoi de données déjà existantes), mais parce
qu'un état de synchronisation change. Arbitré avec Lucas avant implémentation.

### Corrigé — 2026-08-15 (run 4) — L'export sort, et il révèle que le comptage mentait

**Le JSON est écrit** : 727 entrées, avec espèce, genre, IVs, âmes, rang et **passifs**
(`Legend`, `ElementBoost_Dark_2_PAL`…). Les `TArray` se lisent via `ForEach` + `:get()`.

**Mais l'analyse du fichier contredit le résumé.** Sur 727 entrées, **30 seulement portent des
champs** — exactement une page de 30 slots. Les 697 autres sont des coquilles : le slot
existe, `IsEmpty()` répond `false`, et tout accès rend « *the UObject instance is nullptr* ».
Cause : **le jeu ne réplique que la page synchronisée** (`SyncPageIndex`,
`bIsForceSyncAllSlot`, et les propriétés `ReplicatedUsing` du slot). Même en solo.

Ce problème existait dès le run 3 et le résumé le cachait : il comptait un Pal dès qu'un slot
était **occupé**, sans vérifier qu'un champ en sortait. « 723 Pals, 0 illisible » était faux.

- `mods/PalKitBox` — comptage honnête : `palCount` ne compte que les Pals dont l'**espèce**
  est lue ; les autres deviennent `partialPals`. Le résumé affiche la répartition par page et
  nomme la cause quand une seule page répond
- `mods/PalKitBox` — `gatherSlots` : union dédoublonnée de **trois** sources, dont deux qui
  contournent la pagination sans rien écrire — `TargetContainer` (le conteneur complet,
  `Num()`/`Get(i)`) et `CachedNonEmptySlots_InServer` (la liste côté serveur, et en solo le
  joueur *est* le serveur)
- `mods/PalKitBox` — les passifs passent par `GetPassiveSkillList()` **avant** la propriété du
  struct : le TArray d'un struct n'a pas toujours d'UObject propriétaire
- `mods/PalKitBox` — les avertissements portent leur **fréquence** (`x697`). Sans elle, un
  échec sur un Pal et un échec sur tous s'affichent à l'identique — c'est ce qui a fait passer
  le blocage pour un détail
- `shared/query.lua` — `scalar` et `toList` remontent dans la lib commune : tout mod qui lit
  des données du jeu en a besoin, et **les tests portent désormais sur le vrai code** au lieu
  d'une copie de sa logique
- `shared/query.lua` — `toList` ne retient plus une liste vide au détriment d'une voie qui rend
  des données, et un objet qui refuse `ForEach` **et** `GetArrayNum` n'est plus déclaré
  « tableau vide » sur la foi d'un `#` à zéro : c'est un objet mort, et le dire vaut mieux
- `mods/PalKitSpike` — les mesures d'affichage sont différées de 500 ms. Slate ne calcule la
  taille désirée qu'à sa passe de layout : au run 4, les cinq cibles rendaient `0×0` — y
  compris la carte entière, ce qui n'avait aucun sens
- `scripts/test-shared.lua` — 88 tests (9 de plus) sur les quatre API `TArray`, la préférence
  aux données non vides et la conservation de l'erreur d'origine

### Corrigé — 2026-08-15 (run 3) — M2 v0 lit la Palbox : 723 Pals, 0 slot illisible

**La chaîne de lecture tient.** Les quatre voies d'accès répondent et convergent sur la même
instance ; la voie 1 (`APalPlayerState:GetPalStorage()`), la plus propre, est retenue.
960 slots parcourus, 723 Pals lus, 237 vides, **aucun illisible**. `GetLevel()` répond aussi,
donc toute la colonne « Getter » de `sdk-notes.md` devient exploitable — à commencer par
`GetWorkSuitabilityRanksWithCharacterRank()`, seul à tenir compte de la condensation.

Le spike confirme l'ordre des paliers corrigé (palier 4 après le 3) et `IsInViewport = true`,
jeu toujours répondant.

**L'export a quand même été perdu**, sur un seul champ : le moteur ne rend pas que des
nombres — un FName, un FText ou un enum arrivent en `userdata`, et le codec JSON, qui a
raison de ne rien deviner, refuse de les sérialiser. 723 Pals correctement lus, zéro écrit.

- `mods/PalKitBox` — `scalar()` réduit toute valeur moteur à un scalaire encodable :
  `ToString()`, puis `get()`, puis `GetValue()`. Ce qui résiste aux trois est **écarté et
  nommé**, jamais déguisé en `"userdata: 0x…"` — une valeur illisible doit se voir dans le
  rapport, pas s'y faire passer pour une donnée
- `mods/PalKitBox` — filet avant écriture : une passe récursive écarte l'inencodable en le
  nommant par son chemin, et **l'export part quand même**. Perdre 723 Pals sur un champ ne
  doit pas pouvoir se reproduire
- `mods/PalKitBox` — `toList` tente **quatre** API `TArray` (`ForEach`,
  `GetArrayNum`/`GetArrayElement`, `GetArrayNum`/index, `#`/index) et conserve l'erreur exacte
  de la première. `PassiveSkillList` résistait aux deux voies précédentes, et le mod se
  contentait d'un « TArray non convertible » sans piste. La voie qui répondra vaudra pour
  tous les TArray du jeu, donc pour M2 v1
- `mods/PalKitBox` — `notes` distinct de `warnings` : un constat de fonctionnement ne doit pas
  faire passer un export sain pour un export dégradé
- `mods/PalKitSpike` — le palier 4 mesure `IsVisible`, `RenderOpacity` et `DesiredSize` :
  `IsInViewport` dit seulement qu'un widget est *attaché*, pas qu'il occupe une place. Une
  taille nulle répond objectivement à « est-ce que ça s'affiche ? »
- `mods/PalKitSpike` — chaque `F5` avance d'une cible. La boucle utile est « F5, je regarde,
  F6, F5 » : quatre cibles en une minute, sans éditer de fichier ni quitter le jeu
- `scripts/test-shared.lua` — 79 tests (8 de plus), sur la cascade de conversion et le refus
  du codec

### Corrigé — 2026-08-15 (run 2) — La cause racine était chez nous

**`Create()` + `AddToViewport()` fonctionnent en Lua pur.** Le palier 3 du spike a construit
`WBP_CompassIconBase_C` sous la GameInstance et l'a ajouté au viewport sans erreur : la
question qui bloquait M1 depuis le début est tranchée **côté API**, sans `.pak`. Reste à
confirmer la visibilité à l'écran.

**Un seul bug expliquait tous les échecs d'appel, et il était de notre côté.** `query.call`
n'appelait une méthode que si `type(fn) == "function"` — or **UE4SS expose les `UFunction`
comme des `userdata` appelables**. Ce garde rejetait donc *toutes* les méthodes du jeu, en
silence : `GetPalStorage`, `GetPalPlayerState`, `GetPageNum`, `GetSlot`. L'hypothèse « deux
`BP_PalPlayerState_C` » du run 1 est **infirmée** comme cause (l'observation, elle, reste
vraie — et la cascade qu'elle a motivée a permis de lire la Palbox malgré le bug).

- `shared/query.lua` — plus aucun test de type avant d'appeler : on tente l'appel sous
  `pcall`, seul juge valable. Les diagnostics passent par `always("DEBUG")` : le logger
  dédoublonne sur la chaîne de format, identique pour toutes les méthodes, ce qui masquait
  3 échecs sur 4 et a coûté une passe de test entière
- `shared/query.lua` — `storageAnswers` exige désormais un `GetSlot(0,0)` valide.
  `PageNum`/`SlotNumInPage` sont des propriétés répliquées : elles se lisent parfaitement sur
  un storage dont plus aucune méthode ne répond
- `mods/PalKitBox` — le verdict de la sonde découle de la sonde en profondeur, au lieu d'un
  second test qui la contredisait à une ligne d'intervalle (« voie inexploitable » suivi de
  « voie retenue »). Un export sans Pal se déclare **en échec** au lieu d'annoncer « aucun
  champ illisible : toutes les entrées header sont confirmées » — la liste était vide parce
  qu'aucun champ n'avait pu être tenté
- `mods/PalKitBox` — la sonde passe de `F9` à **`F11`** : `PalKitDump` occupe F9/F10, et une
  pression déclenchait un dump de 127 Mo juste avant la sonde
- `mods/PalKitSpike` — paliers 4 et conclusion enchaînés **dans la continuation** du palier 3.
  `ExecuteInGameThread` est asynchrone : au run 2, le palier 4 concluait « aucun widget
  affiché » 8 ms avant que le widget soit créé
- `scripts/test-shared.lua` — 71 tests (3 de plus), dont **celui qui aurait attrapé le bug** :
  une table à métatable `__call` reproduit un `userdata` appelable d'UE4SS, appelable sans
  être de type `function`

### Corrigé — 2026-08-15 — Premier run en jeu : deux échecs, quatre trous comblés

Premier aller-retour manette en main. `PalKitBox` et `PalKitSpike` ont tous les deux échoué,
et c'est le run le plus productif du projet à ce jour : l'ObjectDump (`CTRL + J`, 574 889
lignes) déposé dans la foulée a comblé quatre ⬜ que les headers ne pouvaient pas remplir.

**`PalKitBox` — `GetPalStorage n'a rien renvoyé`.** Le nom n'était pas en cause : la
signature est bonne (`PalPlayerState.h:573`, `UFUNCTION BlueprintPure`) et l'ObjectDump
montre l'instance bien vivante. Ce qu'il montre aussi, et qui est le vrai suspect : **deux
`BP_PalPlayerState_C` coexistent en solo**, dont un seul porte la Palbox — or la propriété
moteur `PlayerState` n'offre aucune garantie de désigner celui-là.

- `shared/query.lua` — `query.palStorage` devient une **cascade de 4 voies nommées**
  (getter, propriété `PalStorage`, `UPalUtility.GetPalStorageDataByPlayerUID` via le CDO,
  puis balayage global en filet). La première qui rend un objet *qui répond* gagne, et son
  nom est journalisé puis reversé dans le JSON (`meta.storageRoute`). `GetPalPlayerState()`
  passe devant `.PlayerState` partout
- `shared/query.lua` — `query.callWhy()` : un appel qui **dit pourquoi il échoue** (membre
  absent / présent mais non appelable / lève). Les deux `return nil` muets de `query.call`
  sont la raison pour laquelle ce run ne se diagnostiquait pas tout seul
- `mods/PalKitBox` — **`F9`, sonde de diagnostic** : essaie les 4 voies, compare les deux
  PlayerState, et pour chaque voie descend jusqu'à lire le `CharacterID` d'un vrai Pal.
  Un `VERDICT` en fin de bloc

**`PalKitSpike` — paliers 3 et 4 jamais atteints.** Le palier 2 ne pouvait structurellement
pas produire de candidat : il n'alimentait `candidates` qu'avec
`FindAllOf("WidgetBlueprintGeneratedClass")`, qui rend **0** sur ce build alors que le jeu
compte 668 de ces classes — et les milliers de `UserWidget` trouvés juste après étaient
loggés puis jetés.

- `mods/PalKitSpike` — le palier 2 vise désormais des **classes nommées** issues de
  l'ObjectDump (`StaticFindObject`), puis retombe sur les classes des instances vivantes.
  Il distingue instances (`/Engine/Transient`) et **modèles de CDO** (`/Game/….:WidgetTree.X`)
  — instancier un modèle n'aurait jamais rien affiché. Filtre porté sur le nom de classe
  court, plus sur le chemin. Inventaire par classe au lieu d'une liste d'instances répétées
- Première cible du palier 3 : `WBP_CompassIconBase_C`, puis `WBP_Ingame_Compass_C` — **la
  boussole du jeu est un meilleur point d'entrée pour M1 que la carte** : un HUD déjà fait
  pour rester à l'écran, peuplé d'icônes typées (Pal, camp, donjon, fast travel)

**Comblé par l'ObjectDump** (détail dans `docs/sdk-notes.md`) : la conversion monde → carte
(`WBP_Map_Body_C:CalcMapImagePosition` & co., bien en Blueprint comme supposé) ; les widgets
réels de la Palbox ; la formule de **mutation**, paramétrée dans `UPalGameSetting`
(`Combi_Mutation*`) — au passage, l'affirmation « aucun header ne mentionne Mutation » était
**fausse**, elle venait d'un grep partiel, et la correction est consignée.

- `docs/sdk-notes.md` — nouveau statut **❌** (signature confirmée, appel Lua échoué), section
  « Blueprints observés en jeu », acquis d'environnement du run (UE 5.1, pas de console
  UE4SS, `FindAllOf` sur les classes de widgets inopérant), 8 entrées de journal
- `docs/testing.md` — protocole de 2ᵉ passe : `F9` avant `F7`, et `F5` à relancer carte ouverte
- `scripts/test-shared.lua` — 68 tests (11 de plus) : causes d'échec de `callWhy`, sélection
  d'un storage qui répond, forme des voies d'accès

### Ajouté — 2026-08-15 — Passe headers 1.0 et M2 v0

**Le blocage « pas de dumps » est levé pour l'essentiel.** Les headers UHT de Palworld 1.0
sont publiés dans [`localcc/PalworldModdingKit`](https://github.com/localcc/PalworldModdingKit)
(commit `62fad41` du 2026-07-11, « update_10_patch1 ») : 3 670 fichiers `Source/Pal/Public`,
au même format que le dump `CTRL + H` d'UE4SS, et pour la bonne version du jeu. Le dump de
headers n'est donc plus un prérequis — seuls l'ObjectDump et le dump d'acteurs le restent,
pour ce que les headers ne peuvent pas donner (Blueprints dérivés, objets vivants).

- `scripts/fetch-headers.sh` — sparse checkout des headers dans `reference/` (gitignoré),
  avec `.palkit-version` qui fige le SHA amont
- `docs/sdk-notes.md` — matrice de cibles remplie hors jeu. Nouveau statut **📘** :
  signature certaine côté C++, non prouvée côté Lua ; exploitable pour coder, jamais pour
  publier. Nouvelle section « Ce que les headers ne donnent pas »
- `shared/query.lua` — résolution d'objets : cache revalidé à chaque accès (jamais de
  pointeur pendouillant), appels et lectures sous garde, aucun parcours global en boucle
- `shared/palio.lua` — écriture des exports à côté du mod, noms horodatés
- `mods/PalKitBox` — **M2 v0** : export JSON de la Palbox, `F7` (fichier) / `F8` (log seul)
- `scripts/test-shared.lua` — 57 tests (23 de plus), couvrant `query` et `palio`

**Découverte structurante :** la Palbox se lit par
`APalPlayerState:GetPalStorage()` → `GetSlot(page, slot)` → `GetHandle()` →
`TryGetIndividualParameter()`, c'est-à-dire **sans ouvrir l'écran ni instancier le moindre
widget**. M2 n'est donc pas suspendu au spike de rendu, contrairement à M1.

L'export embarque un tableau `warnings` listant les champs que le Lua n'a pas su lire : le
premier run en jeu dira exactement quelles entrées 📘 passent en ✅, sans aller-retour.

Deux points restés ouverts, notés dans `sdk-notes.md` : aucun header ne contient
« Mutation » (le mécanisme 1.0 porte un autre nom interne ou vit en Blueprint), et la
conversion monde → coordonnées carte n'existe pas côté C++ — elle est dans le Blueprint.

### Ajouté — 2026-08-15 — Phase 0

- Squelette du dépôt et lib commune :
  - `shared/log.lua` — logging structuré `[PalKit][Module]`, 5 niveaux, DEBUG coupable,
    dédoublonnage des erreurs répétées (une émission par minute, avec le compte des
    occurrences supprimées), bannière de version au démarrage
  - `shared/safe.lua` — gardes d'exécution : `call`, `wrap`, `keybind`, `loop`, `hook`,
    `gameThread`, `isValid`, `get`. Double pcall à chaque frontière (enregistrement *et*
    exécution), pour qu'un échec isolé n'emporte jamais le mod
  - `shared/config.lua` — `settings.json` à côté du mod, résolution du dossier sans chemin
    en dur, fusion en profondeur avec les défauts, écriture atomique avec sauvegarde
  - `shared/json.lua` — codec JSON PalKit (UE4SS n'en fournit pas)
- `mods/PalKitSpike` — sonde de faisabilité du rendu, jetable
- `scripts/build.sh` — contrôle syntaxique + tests + duplication de la lib + zips
- `scripts/install-dev.ps1` — déploiement Windows avec détection du layout d'installation
- `scripts/test-shared.lua` — 34 tests de la lib commune, exécutables hors jeu
- `docs/sdk-notes.md`, `docs/testing.md`, `README.md`, `NOTICE.md`

### Notes de reconnaissance — 2026-08-15

Deux affirmations du brief ont été infirmées, et elles changent la conception :

- **PalMiniMap n'est pas 100 % Lua.** Il installe un `PalMiniMap.pak` dans LogicMods qui
  porte tout son visuel. L'argument de robustesse que le brief §3 en tirait ne tient pas.
- **UE4SS n'expose aucun binding ImGui au Lua** — les tabs GUI sont réservés aux mods C++.

Conséquence : sous la contrainte « zéro `.pak` », une seule voie d'affichage subsiste
(instancier un widget UMG déjà cuit dans le jeu, puis `AddToViewport`), et elle n'est pas
prouvée pour Palworld 1.0. D'où le spike, placé **avant** toute ligne de minimap.

Contexte vérifié : Palworld 1.0 sorti le 10 juillet 2026, patch courant 1.0.3 ; fork Okaetsu
tag `experimental-palworld` (commit `c838a8a`) ; la 1.0 ajoute **Mutation et Awakening** au
breeding, à intégrer dans M4.

### Écart assumé vs brief §7

`scripts/build.sh` remplace `build.ps1` comme script principal : le développement se fait sur
Raspberry Pi (Linux), le jeu tourne sur PC Windows. `install-dev.ps1` couvre la partie
Windows.

`shared/query.lua`, `shared/uipool.lua` et `shared/palio.lua` ne sont pas créés : leur design
dépend des dumps, et des fichiers vides ne seraient que du bruit.
*(Levé le 2026-08-15 pour `query.lua` et `palio.lua`, écrits sur la base des headers 1.0.
`uipool.lua` reste en attente : il dépend de la voie de rendu, que seul le spike tranchera.)*
