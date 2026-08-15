# PalKit

Suite de mods QoL **client-side** pour **Palworld 1.0** (PC / Steam / Windows), en **Lua UE4SS
pur**.

> **État : premier module en test.** `PalKitBox` exporte la Palbox en JSON et attend son
> premier passage en jeu — voir [Feuille de route](#feuille-de-route).

## Modules prévus

| ID | Module | Contenu | État |
|----|--------|---------|------|
| M1 | Minimap | Minimap live avec marqueurs | bloqué par le spike de rendu |
| M2 | Recherche Palbox | Recherche multi-critères + détection de doublons dominés | **v0 validée en jeu** (743 Pals exportés) ; **v1 livrée** (requêtes, tri, dominance) |
| M3 | Recherche Palpedia | Même moteur de requête sur le Paldeck | après M2 |
| M4 | Breeding | CombiRank, planificateur, multi-fermes, tracker de session | après M3 |

Chaque module s'installe séparément. Aucune dépendance croisée : la lib commune est
**dupliquée dans chaque mod au build**, donc supprimer un mod n'affecte jamais les autres.

## Principes

- **Lua UE4SS pur** — zéro `.pak`, zéro Blueprint, zéro asset cooké. Rien à écraser, rien à
  mettre en conflit. Désinstallation = supprimer le dossier.
- **Read-only strict** — aucune écriture dans la sauvegarde, aucune modification de stats,
  aucune accélération de breeding. Ces mods lisent et affichent. C'est aussi ce qui les rend
  acceptables en multi.
- **Client-side** — fonctionne en solo, en coop et sur serveur dédié, sans installation
  serveur. Un serveur officiel peut refuser un client modé : c'est attendu, on ne cherche pas
  à contourner.
- **Dégradation gracieuse** — chaque patch majeur change le build moteur et casse les
  loaders. C'est structurel. Chaque keybind, chaque timer, chaque hook s'enregistre
  indépendamment : un échec isolé n'emporte jamais le mod entier.

## Prérequis

- Palworld **1.0** (PC, Steam ou Microsoft Store)
- **RE-UE4SS, fork Okaetsu**, tag `experimental-palworld`
  → installation pas à pas dans **[docs/testing.md](docs/testing.md)**

> ⚠️ **Ne pas installer UE4SS via Vortex** : il déploie des versions cassées. Installation
> manuelle uniquement.

## Installation d'un module

1. Récupérer `dist/<NomDuMod>/`
2. Le copier dans le dossier Mods d'UE4SS. **Deux layouts coexistent en 1.0** — un seul
   existera chez vous :
   ```
   Palworld\Mods\NativeMods\UE4SS\Mods\        (layout 1.0 / Workshop)
   Palworld\Pal\Binaries\Win64\ue4ss\Mods\     (layout historique)
   ```
3. Ajouter `<NomDuMod> : 1` dans `Mods\mods.txt`

Sous Windows, `scripts\install-dev.ps1 -Mod <NomDuMod>` fait le tout et détecte le layout.

## Désinstallation

Supprimer le dossier du mod, et retirer sa ligne de `mods.txt`. Aucun résidu : PalKit
n'écrit qu'un `settings.json` à l'intérieur de son propre dossier.

## Configuration

Chaque module lit un `settings.json` placé à côté de lui. Le fichier est créé au premier
lancement avec les valeurs par défaut. Les clés inconnues sont conservées, et une clé ajoutée
par une future version apparaît avec son défaut **sans écraser vos réglages**.

Si le fichier est corrompu, le module tourne sur ses défauts et **conserve le fichier** en
l'état, pour qu'il puisse être analysé.

## Dépannage

| Symptôme | Piste |
|---|---|
| Aucune ligne `[PalKit]` dans `UE4SS.log` | Le mod n'est pas chargé : vérifier `mods.txt` et le dossier |
| `CTRL + O` n'ouvre rien | Build joueur installé au lieu du build **Dev** |
| Rien ne se passe en multi | Presser **`INS`** après le chargement du monde — le game state n'est pas réinitialisé comme en solo |
| Le mod répondait, puis plus rien | Chercher `[FATAL]` dans `UE4SS.log` : un module désactivé le dit en une ligne |
| Après une mise à jour du jeu | Attendu : le build moteur a changé. Chercher les `[ERROR]` de hooks, ils nomment la fonction disparue |

Le log est le canal de diagnostic principal : tout PalKit y écrit avec le préfixe
`[PalKit][<Module>]` et un niveau (`FATAL` / `ERROR` / `WARN` / `INFO` / `DEBUG`). Une erreur
qui se répète est résumée une fois par minute plutôt que d'inonder le fichier.

## Développement

Le code est développé sous Linux, le jeu tourne sous Windows — d'où deux scripts :

```bash
./scripts/fetch-headers.sh      # headers Pal 1.0 dans reference/ (hors git) — à faire une fois
./scripts/build.sh              # contrôle syntaxique + tests + zips dans dist/
./scripts/build.sh PalKitBox    # un seul module
lua scripts/test-shared.lua     # tests de la lib commune, hors jeu
```

`fetch-headers.sh` récupère les 3 670 headers UHT de Palworld 1.0 publiés dans
[`localcc/PalworldModdingKit`](https://github.com/localcc/PalworldModdingKit). C'est
l'équivalent du dump `CTRL + H` d'UE4SS, sans avoir à lancer le jeu : c'est de là que vient
tout ce qui est marqué 📘 dans `docs/sdk-notes.md`.

```powershell
.\scripts\install-dev.ps1 -Mod PalKitSpike   # déploiement côté Windows
```

`build.sh` refuse de produire un paquet si le contrôle syntaxique ou les tests échouent.

## Feuille de route

- [x] Phase 0 — squelette, lib commune, logging, config, guide de dump
- [x] Passe headers 1.0 — matrice de cibles remplie hors jeu (`docs/sdk-notes.md`)
- [x] **M2 v0 — export Palbox** (`PalKitBox`) : **validé en jeu le 2026-08-15** — 743 Pals,
      0 coquille, 32 pages en 8,2 s
- [x] **Spike de rendu** — **répondu** : `Create()` + `AddToViewport()` fonctionnent en Lua
      pur, `WBP_Ingame_Compass_C` s'affiche en 800 × 122. **Pas besoin de `.pak`**
- [x] **M2 v1 — recherche, tri et doublons dominés** (`shared/palfilter.lua`, touche `F12`) :
      moteur pur, validé sur l'export réel ⬅️ *à valider en jeu*
- [ ] M1 V1 — minimap socle
- [ ] M1 V2 — marqueurs et perf
- [ ] M2+ — affichage des résultats dans l'écran Palbox (dépend de la brique de rendu)
- [ ] M3 — Palpedia (même moteur de requête)
- [ ] M4 — breeding

### M2 v1 — comment ça s'utilise

Il n'y a pas de champ de saisie en jeu tant que la brique de rendu n'est pas écrite. Les
requêtes sont donc **déclaratives** : on les écrit dans `settings.json`, on presse `F12`, on
lit le résultat dans le log et dans `palbox-recherche-<date>.json`.

```jsonc
"queries": [
  { "name": "combattants",
    "criteria": { "ivMin": { "melee": 70 }, "levelMin": 40, "gender": 2 },
    "sort": [ { "field": "ivTotal", "desc": true } ], "limit": 10 },

  { "name": "a condenser", "dominated": true }
]
```

Critères : `species` (sous-chaîne), `speciesExact`, `levelMin`/`levelMax`, `ivTotalMin`,
`ivMin { hp, melee, shot, defense }`, `gender` (1 mâle / 2 femelle), `rankMin`, `rare`,
`awakening`, `locked`, `passives` (tous), `passivesAny` (au moins un), `page`.

**Doublons dominés** (`"dominated": true`) : liste les Pals qu'un autre surpasse sans
contrepartie — même espèce, même genre, aucun IV inférieur, aucun passif exclusif. Ceux-là
peuvent être condensés ou relâchés sans rien perdre. Le genre est pris en compte par défaut
(`"ignoreGender": true` pour l'ignorer) : conseiller de relâcher la seule femelle d'une
espèce serait un mauvais conseil pour l'élevage.

## Documentation

- **[docs/testing.md](docs/testing.md)** — installation d'UE4SS, génération des dumps, protocole de test
- **[docs/sdk-notes.md](docs/sdk-notes.md)** — classes et propriétés découvertes, avec leur source
- **[docs/changelog.md](docs/changelog.md)**
- **[NOTICE.md](NOTICE.md)** — attributions

## Licence et attributions

Tout le code de PalKit est original. Voir [NOTICE.md](NOTICE.md).
