# Changelog

Format : [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/).

## [Non publié]

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
