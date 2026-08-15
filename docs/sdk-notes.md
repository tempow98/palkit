# sdk-notes.md — classes, propriétés et hooks de Palworld

> **Le fichier le plus important du dépôt.** Le Lua, on sait l'écrire ; ce qu'on ne peut pas
> deviner, ce sont les noms de classes et de propriétés internes de Palworld. Tout ce qui est
> écrit ici vient d'un dump, du Live View ou d'un header — **jamais d'une supposition**.

## Règles de tenue

1. Une entrée n'est validée que si elle porte **sa source** et **sa date**. Un patch majeur
   change le build moteur : sans la source, on ne peut pas revalider, et l'entrée devient un
   piège plutôt qu'une aide.
2. Statuts : ⬜ à identifier · 🟡 hypothèse non vérifiée · 📘 signature lue dans un header
   1.0 · ✅ vérifié en jeu
3. Une hypothèse 🟡 ne part **jamais** en production. Elle doit passer par un test de Lucas.
4. **📘 est exploitable pour coder, pas pour publier.** La signature est certaine (elle vient
   du header de la version 1.0), mais rien ne prouve que l'objet existe au runtime, ni qu'il
   soit joignable depuis le Lua. Une entrée 📘 porte `ModdingKit <sha> — <Fichier>.h` en
   source, et passe en ✅ après un aller-retour en jeu — jamais avant.

## Contexte de version

| Élément | Valeur | Source | Date |
|---|---|---|---|
| Version du jeu | 1.0.3 | patch notes publics | 2026-08-15 |
| Sortie 1.0 | 10 juillet 2026 | patch notes publics | 2026-08-15 |
| Fork UE4SS | Okaetsu, tag `experimental-palworld`, commit `c838a8a` | GitHub | 2026-08-15 |
| Build UE4SS requis | `UE4SS-Palworld_zDev.zip` (Dev) | GitHub releases | 2026-08-15 |
| Lua UE4SS | 5.4 | doc UE4SS | 2026-08-15 |
| **Headers Pal 1.0** | `localcc/PalworldModdingKit`, commit `62fad41` du 2026-07-11 (« update_10_patch1 »), 3 670 headers | `scripts/fetch-headers.sh` → `reference/` | 2026-08-15 |

### D'où viennent les entrées 📘

Le dump `CTRL+H` d'UE4SS n'est plus un prérequis : le `PalworldModdingKit` publie les mêmes
signatures (`UCLASS` / `UFUNCTION` / `UPROPERTY`, format UHT) et il est à jour pour la 1.0.
`bash scripts/fetch-headers.sh` les pose dans `reference/PalworldModdingKit/` (gitignoré) ;
le SHA amont exact est dans `reference/PalworldModdingKit/.palkit-version`.

Chaque chemin `/Script/Pal.X:Y` cité plus bas est vérifiable localement :

```sh
grep -rn "GetPalStorage" reference/PalworldModdingKit/Source/Pal/Public/
```

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
| PlayerController | 📘 | `APalPlayerController` (hérite `APlayerController`) | ModdingKit 62fad41 — `PalPlayerController.h` | 2026-08-15 |
| Pawn joueur (classe) | 📘 | `APalPlayerCharacter` : `APalCharacter` → `ACharacter` | ModdingKit 62fad41 — `PalPlayerCharacter.h`, `PalCharacter.h` | 2026-08-15 |
| PlayerState (porte les données joueur) | 📘 | `APalPlayerState` | ModdingKit 62fad41 — `PalPlayerState.h` | 2026-08-15 |
| Lecture position monde | 📘 | `AActor:K2_GetActorLocation()` sur le pawn | moteur UE 5.1 (hors headers Pal) | 2026-08-15 |
| Lecture rotation / cap | 📘 | `AActor:K2_GetActorRotation()` sur le pawn | moteur UE 5.1 (hors headers Pal) | 2026-08-15 |

> Chemin d'accès complet, sans parcours du tableau UObject :
> `UEHelpers.GetPlayerController()` → `:K2_GetPawn()` → `K2_GetActorLocation()`.
> Le controller est aussi la porte d'entrée de M2 (voir plus bas), donc `shared/query.lua`
> le met en cache et l'invalide au rechargement de monde.

> ⚠️ **Perf.** Lire le pawn par un appel moteur direct depuis le PlayerController.
> Certains helpers parcourent tout le tableau UObject à chaque appel — inacceptable dans une
> boucle de minimap.

### Rendu de la carte

| Cible | Statut | Nom exact | Source | Date |
|---|---|---|---|---|
| Voie d'affichage en Lua pur | ⬜ | **question du spike** — aucun header ne répond à ça | | |
| Texture de world map | 📘 | `APalWorldMapCapture` : props `worldMapTexture` (UTexture2D), `worldMapHeightTexture`, et `GetRenderedWorldMapTexture()` | ModdingKit 62fad41 — `PalWorldMapCapture.h` | 2026-08-15 |
| Widget de carte du jeu | 📘 | `UPalUIWorldMap` : `UPalUserWidgetOverlayUI` ; `CreateWorldMapData(EPalWorldMapType)`, `AddWorldMapIcon()`, `RemoveWorldMapIcon()`, `GetNearestIconWidget()` | ModdingKit 62fad41 — `PalUIWorldMap.h` | 2026-08-15 |
| Widget d'icône de carte | 📘 | `UPalUIWorldMapIcon` | ModdingKit 62fad41 — `PalUIWorldMapIcon.h` | 2026-08-15 |
| Zones de la carte (data table) | 📘 | `FPalWorldMapAreaDataRow`, accès via `UPalMasterDataTableAccess_WorldMapAreaData` | ModdingKit 62fad41 — `PalWorldMapAreaDataRow.h` | 2026-08-15 |
| Mapping monde → coordonnées carte | ⬜ | aucune fonction de conversion publique trouvée dans `PalUIWorldMap.h` — probablement dans le Blueprint dérivé, donc **hors headers** | | |

> ⚠️ `APalWorldMapCapture` porte un `USceneCaptureComponent2D`. C'est exactement ce que le
> brief §3.3 interdit de faire tourner nous-mêmes : on **lit** `worldMapTexture`, on ne
> déclenche jamais `CaptureWorldMapTexture_*`.
>
> `AddWorldMapIcon` prend un `UPalUIWorldMapIcon*` déjà construit : instancier ce widget
> reste suspendu à la réponse du spike.

> Contrainte §3.3 : **pas de `SceneCaptureComponent2D`**. Une seconde caméra rendant le monde
> vu du dessus à chaque frame est une passe de rendu complète supplémentaire. On dessine la
> texture de world map déjà présente dans le jeu.

### Acteurs à marquer

Toutes les classes ci-dessous viennent des headers `ModdingKit 62fad41` (2026-08-15). Ce que
les headers **ne disent pas** : lesquelles sont réellement instanciées dans le monde chargé,
et sous quel nom de Blueprint dérivé — c'est le rôle du dump d'acteurs (`CTRL + NUM_7`).

| Type | Statut | Classe | Fichier |
|---|---|---|---|
| Pals sauvages | 📘 | `APalCharacter` (base commune) — un Pal sauvage se distingue par son `UPalIndividualCharacterParameter` : `IsPlayer == false` et `OwnerPlayerUId` vide | `PalCharacter.h` |
| Joueurs | 📘 | `APalPlayerCharacter` | `PalPlayerCharacter.h` |
| PNJ humains | 📘 | `APalNPC` (hérite `APalCharacter`) | `PalNPC.h` |
| Coffres | 📘 | `APalMapObjectTreasureBox` (hérite `APalMapObject`) | `PalMapObjectTreasureBox.h` |
| Donjons | 📘 | `APalDungeonEntrance` (entrée), `APalDungeonExit` | `PalDungeonEntrance.h` |
| Points de fast travel | 📘 | `APalLevelObjectUnlockableFastTravelPoint` | `PalLevelObjectUnlockableFastTravelPoint.h` |
| Tours | 📘 | `APalBossTower`, point de repère `APalLocationPoint_BossTower` | `PalBossTower.h` |
| Camps de base | 📘 | `UPalBaseCampModel` (UObject, **pas un acteur**) + `UPalBaseCampManager` | `PalBaseCampModel.h` |
| Objets ramassables (effigies, notes) | 📘 | `APalLevelObjectItemPickup` (hérite `APalLevelObjectObtainable`) | `PalLevelObjectItemPickup.h` |
| Camps ennemis | ⬜ | seuls des *spawners* apparaissent (`APalNPCCampSpawnerBase`) ; le marqueur affiché en jeu ne leur correspond pas forcément | |
| Data table des icônes/portraits PNJ | ⬜ | à sortir de l'ObjectDump | |

### États d'interface

| Cible | Statut | Nom exact | Source | Date |
|---|---|---|---|---|
| Détection « joueur dans un camp de base » | 📘 | `UPalInsideBaseCampCheckComponent:IsInsideBaseCamp()` / `GetInsideBaseCampModel()`, composant porté par `APalPlayerCharacter` | ModdingKit 62fad41 — `PalInsideBaseCampCheckComponent.h` | 2026-08-15 |
| Détection menu ouvert (Esc, inventaire, coffre) | 🟡 | piste : le HUD est piloté par des `FPalHUDDispatchParameter_*` (un par écran) + `EPalHUDDisplayType` ; pas de prédicat « un menu est ouvert » trouvé | ModdingKit 62fad41 — `EPalHUDDisplayType.h` | 2026-08-15 |
| Détection téléport / écran de chargement | ⬜ | rien de concluant dans les headers. Repli prévu par le brief : pawn absent, ou saut de position supérieur à tout déplacement possible | | |

> Les passes d'icônes doivent se **mettre en pause ~12 s** au téléport ou au chargement
> (pawn absent, ou saut de position supérieur à tout déplacement possible). C'est là que se
> produisent les crashes.

---

# M2 / M3 — Recherche Palbox et Palpedia

### Chaîne d'accès à la Palbox — **sans passer par l'interface**

C'est l'acquis le plus important de la passe headers : les Pals de la Palbox sont lisibles
depuis les données du joueur, donc **sans dépendre du spike de rendu ni de l'écran ouvert**.

```
UEHelpers.GetPlayerController()            -- APalPlayerController
  → .PlayerState                           -- APalPlayerState (propriété moteur)
  → :GetPalStorage()                       -- UPalPlayerDataPalStorage
  → :GetPageNum()                          -- int32
  → :GetSlotsInPage(pageIndex, out Slots)  -- TArray<UPalIndividualCharacterSlot*>
    → slot:IsEmpty() / :IsLocked() / :GetSlotIndex()
    → slot:GetHandle()                     -- UPalIndividualCharacterHandle
      → :TryGetIndividualParameter()       -- UPalIndividualCharacterParameter
        → .SaveParameter                   -- FPalIndividualCharacterSaveParameter (tous les champs)
```

⚠️ `GetSlotsInPage` a un **paramètre de sortie** (`TArray<...>& Slots`) : côté UE4SS Lua il
faut passer une table vide et relire l'argument après appel, pas espérer une valeur de retour.
Repli si ça résiste : `UPalPlayerDataPalStorage:GetSlot(pageIndex, slotIndex)`, un slot à la
fois, avec `GetSlotCountInPage` côté modèle UI — plus lent mais sans out-param.

### Conteneurs

| Cible | Statut | Classe | Fichier |
|---|---|---|---|
| Palbox (données joueur) | 📘 | `UPalPlayerDataPalStorage`, obtenu par `APalPlayerState:GetPalStorage()` | `PalPlayerDataPalStorage.h`, `PalPlayerState.h` |
| Conteneur générique de Pals | 📘 | `UPalIndividualCharacterContainer : UPalContainerBase` — `Num()`, `GetSlots()`, `Get(i)`, `FindByHandle()` | `PalIndividualCharacterContainer.h` |
| Stockage dimensionnel | 📘 | `UPalPlayerDataPalDimensionStorage`, obtenu par `UPalPlayerDataPalStorage:GetDimensionStorage()` | `PalPlayerDataPalDimensionStorage.h` |
| Stockage global (transfert entre mondes) | 📘 | `UPalGlobalPalStorageSubsystem`, `FPalGlobalPalStorageSaveParameter` | `PalGlobalPalStorageSubsystem.h` |
| Condenseur | 📘 | `UPalMapObjectRankUpCharacterModel`, utilitaire `UPalCharacterRankUpUtility` | `PalMapObjectRankUpCharacterModel.h` |
| Marchands | 📘 | `UPalShopManager`, `UPalShopBase`, produits `UPalShopProductBase` (dont `PalShopProduct_PalSaveParameter`) | `PalShopManager.h` |
| Expéditions | 🟡 | `FPalGuildExpeditionSaveData` côté sauvegarde ; l'assignation d'un Pal se lit sur le paramètre : `IsAssignedToExpedition()` | `PalGuildExpeditionSaveData.h`, `PalIndividualCharacterParameter.h` |

### Structure d'un Pal individuel

Deux voies pour chaque champ : la **propriété** de `FPalIndividualCharacterSaveParameter`
(`param.SaveParameter.X`, lecture directe) ou le **getter** de
`UPalIndividualCharacterParameter` (`param:GetX()`, qui applique les bonus). Le getter est
préférable partout où il existe : le rang d'aptitude au travail, par exemple, dépend du rang
de condensation et des passifs, ce que la propriété brute ne reflète pas.

Tout vient de `ModdingKit 62fad41` — `PalIndividualCharacterSaveParameter.h` et
`PalIndividualCharacterParameter.h`, 2026-08-15.

| Champ | Statut | Propriété `SaveParameter` | Getter |
|---|---|---|---|
| Espèce | 📘 | `CharacterID` (FName) | `GetCharacterID()` |
| Surnom | 📘 | `NickName`, `FilteredNickName` (FString) | `GetNickNameWithOnlineID(out)` / `GetNickNameByCheckBlockedUser(out)` |
| Genre | 📘 | `Gender` (`EPalGenderType`) | `GetGenderType()` |
| Niveau | 📘 | `Level` (uint8), `Exp` (int64) | `GetLevel()`, `IsLevelMax()` |
| IVs | 📘 | `Talent_HP`, `Talent_Melee`, `Talent_Shot`, `Talent_Defense` (uint8) | — |
| Passifs | 📘 | `PassiveSkillList` (TArray\<FName\>) | `GetPassiveSkillList()` |
| Compétences actives | 📘 | `EquipWaza`, `MasteredWaza` (TArray\<`EPalWazaID`\>) | — |
| Aptitudes au travail | 📘 | `CraftSpeeds` (TArray\<`FPalWorkSuitabilityInfo`\>) | `GetWorkSuitabilityRanksWithCharacterRank()` ⬅️ **à préférer** |
| Âme (soul upgrades) | 📘 | `Rank_HP`, `Rank_Attack`, `Rank_Defence`, `Rank_CraftSpeed` (uint8) | — |
| Rang (condensation) | 📘 | `Rank` (uint8), `RankUpExp` (uint16) | `GetRank()` |
| Bonus 1.0 : rare / awakening | 📘 | `IsRarePal`, `bIsAwakening` | `IsRarePal()`, `IsAwakening()` |
| Propriétaire | 📘 | `OwnerPlayerUId` (FGuid), `IsPlayer` (bool) | — |
| Statut d'affectation | 📘 | — | `IsAssignedToExpedition()`, `IsFavoritePal()`, `IsExcludedFromTeamMission()` |

> `Hp` / `MaxHP` / `ShieldHP` sont des `FFixedPoint64`, pas des nombres Lua : il faudra
> passer par leur champ interne. Non résolu tant que ça n'a pas été lu en jeu.
> Idem `EPalWazaID` et `EPalGenderType` : côté Lua ce sont des entiers, la table de
> correspondance est dans `EPalWazaID.h` / `EPalGenderType.h`.

### Widgets UMG

| Cible | Statut | Classe | Fichier |
|---|---|---|---|
| Écran Palbox | 📘 | `UPalUIPalBoxBase : UPalUserWidgetOverlayUI` | `PalUIPalBoxBase.h` |
| Modèle de la Palbox (pagination) | 📘 | `UPalUIPalBoxModel` : `GetWholePageCount()`, `GetSlotCountInPage()`, `GetCurrentPageSlots()`, `ToNextPage()`, `ToPrevPage()`, `CurrentPageIndex`, délégué `OnUpdatePageDelegate` | `PalUIPalBoxModel.h` |
| Item de liste (slot) | 📘 | `UPalIndividualCharacterSlot` — c'est le **modèle**, pas le widget | `PalIndividualCharacterSlot.h` |
| Fenêtre de tri | 📘 | `UPalUIPalBoxSortWindow` | `PalUIPalBoxSortWindow.h` |
| Sélection d'un slot | 📘 | `UPalUIPalBoxModel:SelectHandleSlot(DisplayIndex, EPalItemSlotPressType)` | `PalUIPalBoxModel.h` |
| Widget d'une case (le `WBP_` réel) | ⬜ | dérivé Blueprint : **hors headers**, sortira de l'ObjectDump | |
| Mécanisme de surlignage | ⬜ | idem, dépend du widget Blueprint | |
| Capture du focus clavier | ⬜ | dépend de la voie de rendu tranchée par le spike | |

> Le palier 2 du spike logge les `UserWidget` **vivants**. Le relancer **Palbox ouverte**
> donne les trois lignes ⬜ ci-dessus.
>
> **M2 v0 n'a besoin d'aucune de ces lignes** : la lecture passe par les données joueur
> (voir la chaîne d'accès plus haut). Seul l'affichage in-game en dépend.

---

# M4 — Breeding

Source de toutes les lignes 📘 : `ModdingKit 62fad41`, 2026-08-15.

| Cible | Statut | Nom exact | Fichier |
|---|---|---|---|
| Données d'espèce (ex-`DT_PalMonsterParameter`) | 📘 | `FPalCharacterParameterDatabaseRow : FTableRowBase` | `PalCharacterParameterDatabaseRow.h` |
| Champ CombiRank | 📘 | `FPalCharacterParameterDatabaseRow.CombiRank` (int32) | `PalCharacterParameterDatabaseRow.h:215` |
| Table des combinaisons uniques | 📘 | `FPalCombiUniqueDatabaseRow` : `ParentTribeA/B` (`EPalTribeID`), `ParentGenderA/B`, `ChildCharacterID` — **le genre des parents fait partie de la clé** | `PalCombiUniqueDatabaseRow.h` |
| Identifiant d'espèce (tribu) | 📘 | `EPalTribeID` (uint16, ~300 valeurs nommées) | `EPalTribeID.h` |
| Fermes de reproduction | 📘 | `APalBuildObjectBreedFarm`, travail groupé `UPalBaseCampGroupedWorkFarm` | `PalBuildObjectBreedFarm.h` |
| Progression / arrêt de la reproduction | 📘 | `UPalBreedingUtility:CanProceedBreeding(work)`, `CalcBreedBuffRate(work, baseCamp)`, `EPalBreedStoppedReason` | `PalBreedingUtility.h` |
| Objets qui modifient la reproduction | 📘 | `FPalBreedingItemEffectData` — porte **`CombiRankBonus`** (donc le CombiRank est modifiable par objet en 1.0) | `PalBreedingItemEffectData.h` |
| Œufs | 📘 | `FPalEggLotteryData`, `UPalDynamicPalEggItemDataBase`, `EPalEggSpecialType` | `PalEggLotteryData.h` |
| **Awakening** (1.0) | 📘 | `FPalAwakeningItemElementDataRow` (`ElementType`), état sur le Pal : `bIsAwakening` / `IsAwakening()`, délégué `OnAwakeningDelegate` | `PalAwakeningItemElementDataRow.h` |
| **Mutation** (1.0) | ⬜ | **aucun header ne contient « Mutation »**. Soit le mécanisme porte un autre nom interne, soit il vit dans des Blueprints. À rechercher dans l'ObjectDump | |
| Accès aux data tables depuis le Lua | 🟡 | famille `UPalMasterDataTableAccess_*` (une classe par table) — pas encore vérifié que ce soit joignable côté Lua | `PalMasterDataTableAccess_*.h` |

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

# Ce que les headers ne donnent pas

Les headers décrivent le code C++ du jeu. Ils sont muets sur trois choses, et ces trois
choses restent la raison d'être des dumps in-game :

| Manque | Conséquence | Ce qui le comble |
|---|---|---|
| **Les Blueprints dérivés** (`BP_*`, `WBP_*`) | Toute la couche que Pocketpair a écrite en Blueprint par-dessus le C++ est invisible : widgets réels de la Palbox, icônes de carte, conversion monde → carte | `CTRL + J` (ObjectDump) — le seul qui liste les objets par chemin complet |
| **Ce qui existe au runtime** | Une classe présente dans un header peut n'être jamais instanciée, ou seulement dans certaines zones | `CTRL + NUM_7` (dump d'acteurs), deux passes : extérieur, puis Palbox ouverte |
| **Ce qui est joignable depuis le Lua** | Une `UFUNCTION` peut exister sans être appelable via UE4SS (paramètres non marshalables, `FFixedPoint64`, out-params) | Le premier essai en jeu — c'est ce qui fait passer 📘 → ✅ |

Autrement dit : les headers ont supprimé le besoin du dump `CTRL + H`, pas celui des autres.
Le `.usmap` (`CTRL + NUM_6`) reste facultatif — il sert aux outils de sauvegarde, pas à nous.

## Journal des découvertes

| Date | Découverte | Impact |
|---|---|---|
| 2026-08-15 | Pas d'ImGui côté Lua ; PalMiniMap dépend d'un `.pak` | Voie d'affichage de M1 non prouvée → spike de rendu créé avant tout code de minimap |
| 2026-08-15 | Les headers UHT de la 1.0 sont publiés dans `localcc/PalworldModdingKit` (`62fad41`, 2026-07-11) | Le dump `CTRL+H` n'est plus un prérequis. Statut 📘 créé, matrice de cibles remplie hors jeu |
| 2026-08-15 | La Palbox est lisible via `APalPlayerState:GetPalStorage()`, sans ouvrir l'écran | **M2 est débloqué sans le spike de rendu** : le volet lecture/export ne touche pas à l'UI |
| 2026-08-15 | Aucun header ne mentionne « Mutation » | Le mécanisme 1.0 porte un autre nom interne ou vit en Blueprint → seule piste restante, l'ObjectDump |
| 2026-08-15 | `FPalBreedingItemEffectData.CombiRankBonus` existe | Le CombiRank est modifiable par objet en 1.0 : une table de rangs figée serait fausse même sans patch |
