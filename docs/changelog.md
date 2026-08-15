# Changelog

Format : [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/).

## [Non publié]

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
