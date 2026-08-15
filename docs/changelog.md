# Changelog

Format : [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/).

## [Non publié]

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
