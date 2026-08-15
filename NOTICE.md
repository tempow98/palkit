# NOTICE

## Code tiers inclus dans PalKit

**Aucun, à ce jour.**

Tout le code de `shared/` et de `mods/` est une implémentation originale.

Ce point mérite d'être explicite pour `shared/json.lua` : UE4SS ne fournit pas de
bibliothèque JSON au Lua, et l'usage dans la scène est d'embarquer `rxi/json.lua` (MIT).
PalKit ne le fait pas, et a écrit son propre codec — le périmètre nécessaire (objets,
tableaux, chaînes, nombres, booléens, null) est un sous-ensemble strict, et cela évite
d'avoir à suivre et attribuer une dépendance externe pour trois types de valeurs.

Si du code tiers venait à être intégré, il serait listé ici **et** dans le README du module
concerné, conformément au brief §4.

## Sources consultées — lues, non copiées

Les projets ci-dessous ont servi de **spécification fonctionnelle et de preuve de
faisabilité**. Aucun de leur code ni de leurs assets n'est repris dans PalKit.

| Source | Licence | Usage |
|---|---|---|
| [PalMiniMap](https://github.com/jeankassio/PalMiniMap) — jeankassio, basé sur Paldar de T3R3NC3B | MIT | Architecture étudiée. **Constat retenu :** son visuel repose sur un `.pak` dans LogicMods, pas sur du Lua pur — ce qui a directement motivé le spike de rendu de PalKit. Aucun code repris. |
| [RE-UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) et le [fork Okaetsu](https://github.com/Okaetsu/RE-UE4SS) | voir dépôts | Dépendance d'exécution, non redistribuée. Documentation et exemples : usage normal. |
| Mods Nexus (Palbox Searchbar, Instant Palbox Search, Palbox Search Plus, Smart Breeding Planner, …) | permissions restrictives | Comportement observé et décrit, puis **réimplémenté**. Aucune copie de code ni d'asset — la plupart de ces mods l'interdisent explicitement. |

## Marques

Palworld est une marque de Pocketpair, Inc. PalKit est un projet indépendant, sans
affiliation ni approbation de Pocketpair. Aucun asset du jeu n'est redistribué : PalKit ne
contient que du code Lua, et n'utilise à l'exécution que du contenu déjà présent dans
l'installation du joueur.
