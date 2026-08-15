# sdk-notes.md — classes, propriétés et hooks de Palworld

> **Le fichier le plus important du dépôt.** Le Lua, on sait l'écrire ; ce qu'on ne peut pas
> deviner, ce sont les noms de classes et de propriétés internes de Palworld. Tout ce qui est
> écrit ici vient d'un dump, du Live View ou d'un header — **jamais d'une supposition**.

## Règles de tenue

1. Une entrée n'est validée que si elle porte **sa source** et **sa date**. Un patch majeur
   change le build moteur : sans la source, on ne peut pas revalider, et l'entrée devient un
   piège plutôt qu'une aide.
2. Statuts : ⬜ à identifier · 🟡 hypothèse non vérifiée en jeu · ✅ vérifié en jeu
3. Une hypothèse 🟡 ne part **jamais** en production. Elle doit passer par un test de Lucas.

## Contexte de version

| Élément | Valeur | Source | Date |
|---|---|---|---|
| Version du jeu | 1.0.3 | patch notes publics | 2026-08-15 |
| Sortie 1.0 | 10 juillet 2026 | patch notes publics | 2026-08-15 |
| Fork UE4SS | Okaetsu, tag `experimental-palworld`, commit `c838a8a` | GitHub | 2026-08-15 |
| Build UE4SS requis | `UE4SS-Palworld_zDev.zip` (Dev) | GitHub releases | 2026-08-15 |
| Lua UE4SS | 5.4 | doc UE4SS | 2026-08-15 |

## Acquis d'environnement (vérifié hors jeu)

| Fait | Conséquence | Source |
|---|---|---|
| UE4SS n'expose **aucun binding ImGui au Lua** | Les tabs GUI sont réservés aux mods C++. Pas d'overlay ImGui possible. | doc UE4SS + issue #1072 |
| PalMiniMap **embarque un `.pak`** dans LogicMods | Le brief §3 se trompe en le donnant pour 100 % Lua. Sa robustesse ne vient pas de là. | README + arbo d'install du mod |
| PalMiniMap est sous **licence MIT** | Réutilisation possible **avec attribution**. À ce jour aucun code n'en est repris. | GitHub |
| UE4SS ne fournit **pas de bibliothèque JSON** au Lua | `shared/json.lua` est une implémentation PalKit. | doc UE4SS |
| `package.path` contient le dossier `Scripts/` du mod courant | Sert à résoudre le dossier du mod sans chemin en dur (`shared/config.lua`). | comportement UE4SS |

---

# M1 — Minimap

### Pawn joueur et position

| Cible | Statut | Nom exact | Source | Date |
|---|---|---|---|---|
| PlayerController | ⬜ | | | |
| Pawn joueur (classe) | ⬜ | | | |
| Lecture position monde | ⬜ | | | |
| Lecture rotation / cap | ⬜ | | | |

> ⚠️ **Perf.** Lire le pawn par un appel moteur direct depuis le PlayerController.
> Certains helpers parcourent tout le tableau UObject à chaque appel — inacceptable dans une
> boucle de minimap.

### Rendu de la carte

| Cible | Statut | Nom exact | Source | Date |
|---|---|---|---|---|
| Voie d'affichage en Lua pur | ⬜ | **question du spike** | | |
| Texture / asset de world map | ⬜ | | | |
| Mapping monde → coordonnées carte | ⬜ | | | |
| Widget de carte du jeu | ⬜ | | | |

> Contrainte §3.3 : **pas de `SceneCaptureComponent2D`**. Une seconde caméra rendant le monde
> vu du dessus à chaque frame est une passe de rendu complète supplémentaire. On dessine la
> texture de world map déjà présente dans le jeu.

### Acteurs à marquer

| Type | Statut | Classe | Source | Date |
|---|---|---|---|---|
| Pals sauvages | ⬜ | | | |
| Joueurs | ⬜ | | | |
| PNJ humains | ⬜ | | | |
| Coffres | ⬜ | | | |
| Donjons | ⬜ | | | |
| Points de fast travel | ⬜ | | | |
| Tours | ⬜ | | | |
| Camps de base | ⬜ | | | |
| Camps ennemis | ⬜ | | | |
| Objets ramassables (effigies, notes) | ⬜ | | | |
| Data table des icônes/portraits PNJ | ⬜ | | | |

### États d'interface

| Cible | Statut | Nom exact | Source | Date |
|---|---|---|---|---|
| Détection menu ouvert (Esc, inventaire, coffre) | ⬜ | | | |
| Détection « joueur dans un camp de base » | ⬜ | | | |
| Détection téléport / écran de chargement | ⬜ | | | |

> Les passes d'icônes doivent se **mettre en pause ~12 s** au téléport ou au chargement
> (pawn absent, ou saut de position supérieur à tout déplacement possible). C'est là que se
> produisent les crashes.

---

# M2 / M3 — Recherche Palbox et Palpedia

### Conteneurs

| Cible | Statut | Classe | Source | Date |
|---|---|---|---|---|
| Palbox | ⬜ | | | |
| Stockage global | ⬜ | | | |
| Stockage dimensionnel | ⬜ | | | |
| Condenseur | ⬜ | | | |
| Marchands | ⬜ | | | |
| Expéditions | ⬜ | | | |

### Structure d'un Pal individuel

| Champ | Statut | Propriété | Source | Date |
|---|---|---|---|---|
| Espèce | ⬜ | | | |
| Surnom | ⬜ | | | |
| Genre | ⬜ | | | |
| Niveau | ⬜ | | | |
| IVs | ⬜ | | | |
| Passifs | ⬜ | | | |
| Compétences actives apprises | ⬜ | | | |
| Aptitudes au travail | ⬜ | | | |
| Âme | ⬜ | | | |
| Rang (condensation) | ⬜ | | | |

### Widgets UMG

| Cible | Statut | Classe | Source | Date |
|---|---|---|---|---|
| Liste Palbox | ⬜ | | | |
| Item de liste | ⬜ | | | |
| Pagination | ⬜ | | | |
| Mécanisme de surlignage | ⬜ | | | |
| Capture du focus clavier | ⬜ | | | |

> Le palier 2 du spike logge les `UserWidget` **vivants**. Le relancer **Palbox ouverte**
> donne directement les noms de cette section.

---

# M4 — Breeding

| Cible | Statut | Nom exact | Source | Date |
|---|---|---|---|---|
| `DT_PalMonsterParameter` | ⬜ | | | |
| Champ CombiRank | ⬜ | | | |
| Table des combinaisons uniques | ⬜ | | | |
| Fermes de reproduction (instances) | ⬜ | | | |
| Paire en cours / progression | ⬜ | | | |
| Œufs : type, incubateurs, état | ⬜ | | | |
| Système de **Mutation** (1.0) | ⬜ | | | |
| Système d'**Awakening** (1.0) | ⬜ | | | |

> ⚠️ **Ne hardcoder aucune table de rangs.** Elle deviendrait fausse au prochain patch, et
> c'est précisément l'avantage d'un mod in-game sur un calculateur web.
>
> Formule à revérifier contre le jeu : moyenne des deux CombiRank arrondie, l'espèce dont le
> rang est le plus proche l'emporte, **égalité → la valeur la plus haute gagne** (le cas que
> la plupart des outils datés ratent). Combos uniques et reproduction même-espèce
> court-circuitent la formule. L'ordre des parents est indifférent.
>
> **Mutation et Awakening sont des ajouts de la 1.0** : absents des calculateurs web, donc
> à la fois un risque de spec et notre principal différenciateur sur ce module.

---

## Journal des découvertes

| Date | Découverte | Impact |
|---|---|---|
| 2026-08-15 | Pas d'ImGui côté Lua ; PalMiniMap dépend d'un `.pak` | Voie d'affichage de M1 non prouvée → spike de rendu créé avant tout code de minimap |
