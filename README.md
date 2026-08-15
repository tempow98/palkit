# PalKit

Suite de mods QoL **client-side** pour **Palworld 1.0** (PC / Steam / Windows), en **Lua UE4SS
pur**.

> **État : Phase 0.** Infrastructure et reconnaissance. Aucun module n'est encore
> implémenté — voir [Feuille de route](#feuille-de-route).

## Modules prévus

| ID | Module | Contenu | État |
|----|--------|---------|------|
| M1 | Minimap | Minimap live avec marqueurs | bloqué par le spike de rendu |
| M2 | Recherche Palbox | Recherche multi-critères + détection de doublons dominés | en attente des dumps |
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
./scripts/build.sh              # contrôle syntaxique + tests + zips dans dist/
./scripts/build.sh PalKitSpike  # un seul module
lua scripts/test-shared.lua     # tests de la lib commune, hors jeu
```

```powershell
.\scripts\install-dev.ps1 -Mod PalKitSpike   # déploiement côté Windows
```

`build.sh` refuse de produire un paquet si le contrôle syntaxique ou les tests échouent.

## Feuille de route

- [x] Phase 0 — squelette, lib commune, logging, config, guide de dump
- [ ] **Spike de rendu** — prouver qu'un affichage est possible en Lua pur ⬅️ *en cours*
- [ ] M1 V1 — minimap socle
- [ ] M1 V2 — marqueurs et perf
- [ ] M2 — recherche Palbox
- [ ] M2+ — scoring de dominance
- [ ] M3 — Palpedia
- [ ] M4 — breeding

## Documentation

- **[docs/testing.md](docs/testing.md)** — installation d'UE4SS, génération des dumps, protocole de test
- **[docs/sdk-notes.md](docs/sdk-notes.md)** — classes et propriétés découvertes, avec leur source
- **[docs/changelog.md](docs/changelog.md)**
- **[NOTICE.md](NOTICE.md)** — attributions

## Licence et attributions

Tout le code de PalKit est original. Voir [NOTICE.md](NOTICE.md).
