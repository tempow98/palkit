# sdk-notes.md — classes, propriétés et hooks de Palworld

> **Le fichier le plus important du dépôt.** Le Lua, on sait l'écrire ; ce qu'on ne peut pas
> deviner, ce sont les noms de classes et de propriétés internes de Palworld. Tout ce qui est
> écrit ici vient d'un dump, du Live View ou d'un header — **jamais d'une supposition**.

## Règles de tenue

1. Une entrée n'est validée que si elle porte **sa source** et **sa date**. Un patch majeur
   change le build moteur : sans la source, on ne peut pas revalider, et l'entrée devient un
   piège plutôt qu'une aide.
2. Statuts : ⬜ à identifier · 🟡 hypothèse non vérifiée · 📘 signature lue dans un header
   1.0 · ✅ vérifié en jeu · ❌ signature confirmée, mais **appel Lua échoué en jeu**
3. Une hypothèse 🟡 ne part **jamais** en production. Elle doit passer par un test de Lucas.
4. **📘 est exploitable pour coder, pas pour publier.** La signature est certaine (elle vient
   du header de la version 1.0), mais rien ne prouve que l'objet existe au runtime, ni qu'il
   soit joignable depuis le Lua. Une entrée 📘 porte `ModdingKit <sha> — <Fichier>.h` en
   source, et passe en ✅ après un aller-retour en jeu — jamais avant.
5. **❌ vaut mieux que 📘 pour une signature qui a échoué.** Une ligne qui reste 📘 après un
   échec en jeu invite à réessayer la même chose. ❌ dit : le nom est bon, c'est le **chemin
   d'accès** qui est à trouver — et l'entrée porte alors les voies déjà essayées.

## Contexte de version

| Élément | Valeur | Source | Date |
|---|---|---|---|
| Version du jeu | 1.0.3 | patch notes publics | 2026-08-15 |
| Sortie 1.0 | 10 juillet 2026 | patch notes publics | 2026-08-15 |
| Fork UE4SS | Okaetsu, tag `experimental-palworld`, commit `c838a8a` | GitHub | 2026-08-15 |
| Build UE4SS requis | `UE4SS-Palworld_zDev.zip` (Dev) | GitHub releases | 2026-08-15 |
| Lua UE4SS | 5.4 | doc UE4SS | 2026-08-15 |
| **Headers Pal 1.0** | `localcc/PalworldModdingKit`, commit `62fad41` du 2026-07-11 (« update_10_patch1 »), 3 670 headers | `scripts/fetch-headers.sh` → `reference/` | 2026-08-15 |
| **ObjectDump** | `UE4SS_ObjectDump.txt`, 574 889 lignes / 127 Mo, monde `MainWorld_5` chargé, Palbox ouverte | `CTRL+J` de Lucas, déposé sur le Pi (`~/palkit/logs/`) | 2026-08-15 |
| Premier run en jeu | log UE4SS 17:00→17:12 : `PalKitBox` KO, `PalKitSpike` paliers 3–4 non atteints | `UE4SS.log` de Lucas | 2026-08-15 |

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

### Acquis du premier run en jeu (2026-08-15)

| Fait | Conséquence | Source |
|---|---|---|
| Moteur **UE 5.1** | Les signatures moteur (`K2_GetActorLocation`, etc.) sont celles de 5.1. | PS scan UE4SS |
| `ConsoleManagerSingleton` **introuvable** (2 valeurs candidates) | **Pas de console UE4SS** sur ce build : aucun repli par commande console, tout passe par le Lua. | `UE4SS.log` au démarrage |
| `FindAllOf("WidgetBlueprintGeneratedClass")` renvoie **0** | Alors que l'ObjectDump en compte **668**. Cette voie de découverte des classes d'UI est **morte** : passer par `StaticFindObject(<chemin>)` ou par la classe des instances vivantes. | log F5 + ObjectDump |
| Un `UserWidget` sous `/Game/….:WidgetTree.X` est un **modèle de CDO**, pas un widget affiché | Les instances réelles vivent sous `/Engine/Transient.PalGameEngine…`. Les « 3 204 UserWidget vivants » du premier log étaient, pour l'essentiel, des modèles — et instancier un modèle n'aurait rien affiché. | log F5 + ObjectDump |
| **Deux `BP_PalPlayerState_C` vivants** en solo (`_2147480325`, `_2147480221`), **un seul** porte une `PalPlayerDataPalStorage` | Cause la plus probable de l'échec `GetPalStorage` : la propriété moteur `PlayerState` n'offre aucune garantie de désigner le bon. | ObjectDump |
| Le pawn joueur est un **Blueprint dérivé** (`BP_Player_Female_C`), pas `APalPlayerCharacter` nu | Ne jamais tester une classe par égalité stricte ; toujours par héritage. | log F5 |
| L'arbre d'UI vivant est enraciné sous la **GameInstance** (`BP_PalGameInstance_C` → `WBP_PalOverallUILayout_C`), pas sous le PlayerController | C'est le conteneur auquel M1 devra s'accrocher. | log F5 |

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
| Voie d'affichage en Lua pur | ⬜ | **question du spike** — aucun header ne répond à ça. Toujours ouverte : au premier run, le palier 3 n'a pas été atteint (palier 2 sans candidat) | log F5 | 2026-08-15 |
| Texture de world map | 📘 | `APalWorldMapCapture` : props `worldMapTexture` (UTexture2D), `worldMapHeightTexture`, et `GetRenderedWorldMapTexture()` | ModdingKit 62fad41 — `PalWorldMapCapture.h` | 2026-08-15 |
| Widget de carte du jeu | 📘 | `UPalUIWorldMap` : `UPalUserWidgetOverlayUI` ; `CreateWorldMapData(EPalWorldMapType)`, `AddWorldMapIcon()`, `RemoveWorldMapIcon()`, `GetNearestIconWidget()` | ModdingKit 62fad41 — `PalUIWorldMap.h` | 2026-08-15 |
| Widget d'icône de carte | 📘 | `UPalUIWorldMapIcon` | ModdingKit 62fad41 — `PalUIWorldMapIcon.h` | 2026-08-15 |
| Zones de la carte (data table) | 📘 | `FPalWorldMapAreaDataRow`, accès via `UPalMasterDataTableAccess_WorldMapAreaData` | ModdingKit 62fad41 — `PalWorldMapAreaDataRow.h` | 2026-08-15 |
| Mapping monde → coordonnées carte | ✅ | **dans le Blueprint dérivé, comme supposé.** `WBP_Map_Body_C` porte `CalcMapImagePosition`, `GetMapCanvasPosition`, `AdjustScrollByWorldLocation`, `GetCursorWorldLocation`, `GetWIndowCenterWorldLocation` | ObjectDump 2026-08-15 | 2026-08-15 |
| Position d'une icône sur le relief | ✅ | `GetLocationOnLandscape()`, porté par `UPalUIWorldMapIcon` **et** par les icônes Blueprint (`WBP_Map_IconBoss/Custom/Tower_C`) | ObjectDump 2026-08-15 | 2026-08-15 |
| Données de carte du client | 📘 | `UPalUtility:GetLocalWorldMapData()` | ObjectDump 2026-08-15 | 2026-08-15 |

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

> ❌ **Cette chaîne a échoué au premier essai en jeu (2026-08-15)** : `GetPalStorage n'a rien
> renvoyé`. Le nom n'est pas en cause — l'ObjectDump du même run montre l'instance bien
> vivante, à `…:PersistentLevel.BP_PalPlayerState_C_2147480325.PalPlayerDataPalStorage_2147457951`.
> C'est le **chemin d'accès** qui est en cause, et le suspect est identifié : **deux
> `BP_PalPlayerState_C` coexistent**, un seul porte la Palbox. Voir les voies ci-dessous.

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

### Les quatre voies d'accès à la Palbox

Implémentées en cascade dans `shared/query.lua` (`query.palStorageRoutes`), essayées dans cet
ordre, et **diagnosticables une par une** avec `F9` de `PalKitBox`. La première qui rend un
objet *qui répond* (`GetPageNum` ou `PageNum` > 0) gagne, et son nom est journalisé — c'est
lui qui fera passer la ligne en ✅.

| # | Voie | Statut | Pourquoi elle est là | Source |
|---|---|---|---|---|
| 1 | `APalPlayerState:GetPalStorage()` | ❌ | Voie du premier essai. Signature bonne, retour vide | `PalPlayerState.h:573` |
| 2 | `APalPlayerState.PalStorage` (propriété) | ⬜ | `UPROPERTY(BlueprintReadWrite, Replicated)` : une propriété se lit souvent là où l'appel d'une `UFUNCTION` résiste | `PalPlayerState.h:180` |
| 3 | `UPalUtility.GetPalStorageDataByPlayerUID(world, uid)` | ⬜ | **Statique, via le CDO `/Script/Pal.Default__PalUtility`** : contourne entièrement le PlayerState, donc aussi l'ambiguïté des deux instances. Le `uid` vient de `APalPlayerController:GetPlayerUId()` | `PalUtility.h:1182` + ObjectDump |
| 4 | `FindAllOf("PalPlayerDataPalStorage")` | ⬜ | Filet. Parcours global, donc **hors boucle et une seule fois** (règle 2 de `query.lua`), en écartant le CDO `Default__` | ObjectDump |

> En amont des voies 1 et 2, le PlayerState lui-même se résout par
> `APalPlayerController:GetPalPlayerState()` (📘 `PalPlayerController.h:935`) **avant** la
> propriété moteur `PlayerState` : le getter Pal sait ce qu'est un PlayerState *Pal*, la
> propriété moteur n'en sait rien. C'est le correctif le plus direct du bug du 15/08.

### Conteneurs

| Cible | Statut | Classe | Fichier |
|---|---|---|---|
| Palbox (données joueur) | ❌ | `UPalPlayerDataPalStorage` — la classe et l'instance sont confirmées au runtime ; c'est l'**accès** qui reste à prouver (voir les quatre voies ci-dessus) | `PalPlayerDataPalStorage.h`, ObjectDump 2026-08-15 |
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
| Écran Palbox (le `WBP_` réel) | ✅ | `WBP_PalStorageMenu_C` → `WBP_IngameMenu_PalBox` → `WBP_BoxPalList` → `WBP_BoxPalListBase_C` | log F5 2026-08-15, Palbox ouverte |
| Widget d'une case | ✅ | `WBP_PalCommonCharacterSlot` → `WBP_PalCommonCharacterIcon_C` | log F5 2026-08-15 |
| Fenêtre de tri (le `WBP_` réel) | ✅ | `WBP_PalStorageSortSettingWindow_C`, avec `WBP_PalStorageSortElementFilterCheckBox_C`, `WBP_PalStorageSortWorkSuitabilityFilterCheckBox_C`, `WBP_PalGenderIcon_C`, `WBP_PalElementIcon_C`, `WBP_IconPalWork_C` | log F5 2026-08-15 |
| Mécanisme de surlignage | ⬜ | dépend du widget de case : à lire dans le détail de `WBP_BoxPalListBase_C` | |
| Capture du focus clavier | ⬜ | dépend de la voie de rendu tranchée par le spike | |

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
| **Mutation** (1.0) — paramètres | ✅ | `UPalGameSetting` : `Combi_MutationRate`, `Combi_MutationRankCoefficient`, `Combi_MutationRankDiffPenalty`, `Combi_MutationRandomCoefficient`, `Combi_MutationMinTalent` (uint8), `Combi_MutationInitialRank` (uint8) | `PalGameSetting.h:1865-1883`, confirmé ObjectDump |
| **Mutation** — bonus par objet | 📘 | `FPalBreedingItemEffectData.MutationRateBonusPercent` (à côté de `CombiRankBonus`) | `PalBreedingItemEffectData.h` |
| **Mutation** — œuf issu d'une mutation | 📘 | `FPalExtraEggCacheInfo.bIsMutationEgg` ; ids d'objets `MutationPalEggStaticItemIds`, `PalEggMapObjectId_Mutation` | ObjectDump 2026-08-15 |
| **Mutation** — compteur joueur | 📘 | `UPalPlayerRecordData.MutationCount` (et `FPalLoggedinPlayerSaveDataRecordData.MutationCount`) | ObjectDump 2026-08-15 |
| **Mutation** — passifs réservés | 📘 | `FPalPassiveSkillDatabaseRow.AddMutationPal`, table `MutationPalAssignableSkillMap` | ObjectDump 2026-08-15 |
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
>
> ⚠️ **Correction du 2026-08-15.** Ce document a affirmé qu'« aucun header ne mentionne
> Mutation ». **C'est faux** : `PalGameSetting.h:1865-1883` porte les six paramètres de la
> formule. Le premier grep avait été mené sur les seuls fichiers déjà cités dans ces notes,
> pas sur l'arbre complet. La leçon vaut au-delà de cette ligne : **une absence n'est un fait
> qu'accompagnée de la commande qui l'a établie** — et `grep -ril <terme> reference/` est le
> minimum avant d'écrire « n'existe pas ».
>
> Conséquence de fond : la formule de mutation est **paramétrée côté jeu**, pas codée en dur.
> `Combi_MutationRate` et consorts se lisent au runtime — les figer dans PalKit reproduirait
> exactement l'erreur des calculateurs web.

---

# Blueprints observés en jeu

Tout ce qui suit vient du run du **2026-08-15** — log `F5` (widgets vivants, Palbox ouverte)
et `UE4SS_ObjectDump.txt` (574 889 lignes). C'est la couche que Pocketpair a écrite en
Blueprint par-dessus le C++ : invisible aux headers, et indispensable à M1.

**Convention de nommage** : `WBP_<Domaine><Élément>_C` pour les widgets, `BP_<Classe>_C` pour
les acteurs. Domaines observés : `PalStorage`, `BoxPal`, `Map`, `IngameCompass`,
`MainMenu_Pal`, `PalCommon`, `Ingame`, `Option`, `Guild`, `Paldex`.

### Carte et boussole — les cibles de M1

Chemins complets, vérifiables par `grep -F "<chemin>" ~/palkit/logs/UE4SS_ObjectDump.txt` :

| Rôle | Classe | Chemin du package |
|---|---|---|
| Corps de carte (texture + scroll + zoom) | `WBP_Map_Body_C` | `/Game/Pal/Blueprint/UI/UserInterface/Map/WBP_Map_Body` |
| Écran de carte complet | `WBP_Map_Base_C` | `…/Map/WBP_Map_Base` |
| Curseur de carte | `WBP_Map_Cursor_C` | `…/Map/WBP_Map_Cursor` |
| Filtre d'icônes | `WBP_MapFilter_C`, `WBP_MapFilter_Content_C`, `WBP_MapFilter_Win_C` | `…/Map/` |
| Icônes de carte | `WBP_Map_Icon_C`, `_IconBoss_C`, `_IconCamp_C`, `_IconCustom_C`, `_IconPlayer_C`, `_IconTower_C`, `_IconFTTower_C`, `WBP_Map_StandAloneBossIcon_C` | `…/Map/` |
| **Boussole HUD** (affichée en jeu, en permanence) | `WBP_Ingame_Compass_C` | `/Game/Pal/Blueprint/UI/UserInterface/InGame/Compass/WBP_Ingame_Compass` |
| Icône de boussole (base) | `WBP_CompassIconBase_C` | `…/InGame/Compass/WBP_CompassIconBase` |
| Icônes de boussole spécialisées | `WBP_CompassIcon_ForPal_C`, `_ForMapObject_C`, `_ForLevelObject_C`, `WBP_IngameCompass_{arrow,camp,BossTower,CustomMarker,DeathMark,dungeonGoal,dungeonPortal,FastTravel,Quest,Supply,TreasureMapPoint,WarpPoint}_C` | `…/InGame/Compass/` |

> **La boussole est le meilleur point d'entrée de M1**, et c'est un acquis inattendu de ce
> run : `WBP_Ingame_Compass_C` est déjà un HUD conçu pour rester à l'écran pendant le jeu,
> peuplé d'icônes typées (Pal, camp, donjon, fast travel…) — soit exactement la sémantique
> d'une minimap, sans le problème de la texture de carte. Le spike la teste en deuxième
> cible, juste après `WBP_CompassIconBase_C` (plus légère, donc test d'affichage plus franc).

### Palbox et menus

| Rôle | Classes |
|---|---|
| Racine de tout l'UI vivant | `WBP_PalOverallUILayout_C`, sous `/Engine/Transient.PalGameEngine:BP_PalGameInstance_C` |
| Écran Palbox | `WBP_PalStorageMenu_C` → `WBP_IngameMenu_PalBox` → `WBP_BoxPalList` → `WBP_BoxPalListBase_C` |
| Tri Palbox | `WBP_PalStorageSortSettingWindow_C`, `WBP_PalStorageSortElementFilterCheckBox_C`, `WBP_PalStorageSortWorkSuitabilityFilterCheckBox_C` |
| Icônes de Pal | `WBP_PalCommonCharacterSlot`, `WBP_PalCommonCharacterIcon_C`, `WBP_PalGenderIcon_C`, `WBP_PalElementIcon_C`, `WBP_IconPalWork_C` |
| Slots d'objets | `WBP_PalInGameMenuItemSlot_C`, `WBP_PalInGameMenuItemSlotButton_C`, `WBP_PalInGameMenuItemIcon_C`, `WBP_InventoryEquipment_PalIcon_C`, `WBP_PalItemSlotDragDropIcon_C`, `WBP_PalLiftItem` |
| Fiche Pal (menu) | `WBP_MainMenu_Pal_WorkIconText_C`, `_WorkGauge_C`, `_WorkIcon_C`, `_FoodAmount_C`, `_FoodAmountIcon_C`, `WBP_MainMenu_Pal_Skill_Active_C`, `_Skill_Passive_C`, `WBP_MainMenu_Cursor_C` |
| Communs | `WBP_PalCommonWindow_C`, `WBP_CommonButton_C`, `WBP_PalCommonButton_C`, `WBP_PalInvisibleButton_C`, `WBP_PalKeyGuideIcon_C` |
| HUD divers | `WBP_PalHungerHud_C`, `WBP_PalHungerIcon_C`, `WBP_PalStatusPopup_C`, `WBP_Ingame_Interact_C`, `WBP_GameOver_Down_C`, `WBP_DyingFriendLoupe_C`, `WBP_GuildMemberGauge_C` |
| Mods (écran du jeu lui-même) | `WBP_ModDisclaimerDialog` |

### Acteurs et objets racines

| Rôle | Instance observée |
|---|---|
| Monde | `/Game/Pal/Maps/MainWorld_5/PL_MainWorld5` |
| PlayerController | `BP_PalPlayerController_C_2147480323` |
| PlayerState | `BP_PalPlayerState_C_2147480325` (**porte la Palbox**) et `BP_PalPlayerState_C_2147480221` (non) |
| Palbox | `…BP_PalPlayerState_C_2147480325.PalPlayerDataPalStorage_2147457951` |
| Pawn joueur | `BP_Player_Female_C_2147480255` |
| GameInstance / Engine | `BP_PalGameInstance_C_2147482476`, `PalGameEngine_2147482588` |

# Ce que les headers ne donnent pas

Les headers décrivent le code C++ du jeu. Ils sont muets sur trois choses, et ces trois
choses restent la raison d'être des dumps in-game :

| Manque | Conséquence | Ce qui le comble |
|---|---|---|
| **Les Blueprints dérivés** (`BP_*`, `WBP_*`) | Toute la couche que Pocketpair a écrite en Blueprint par-dessus le C++ est invisible : widgets réels de la Palbox, icônes de carte, conversion monde → carte | ✅ **fait** — `CTRL + J` du 2026-08-15, dépouillé dans « Blueprints observés en jeu » |
| **Ce qui existe au runtime** | Une classe présente dans un header peut n'être jamais instanciée, ou seulement dans certaines zones | ✅ en partie — le même ObjectDump donne les instances vivantes. `CTRL + NUM_7` reste utile pour une passe **en extérieur** (Pals sauvages, coffres, donjons), que ce dump-là ne couvre pas |
| **Ce qui est joignable depuis le Lua** | Une `UFUNCTION` peut exister sans être appelable via UE4SS (paramètres non marshalables, `FFixedPoint64`, out-params) | ⬜ **le seul vrai manque restant** — et le run du 15/08 vient d'en donner le premier exemple avec `GetPalStorage`. C'est ce qui fait passer 📘 → ✅ ou → ❌ |

Autrement dit : les headers ont supprimé le besoin du dump `CTRL + H`, et l'ObjectDump du
2026-08-15 a réglé les deux premières lignes. Ne reste que la troisième, qui ne se règle que
manette en main. Le `.usmap` (`CTRL + NUM_6`) reste facultatif — il sert aux outils de
sauvegarde, pas à nous.

> ⚠️ **Un dump n'est pas une preuve d'accessibilité.** L'ObjectDump prouve qu'un objet existe
> et sous quel chemin ; il ne dit rien de ce qu'UE4SS sait en faire. `GetPalStorage` est
> présente dans le dump, avec son `ReturnValue` — et elle a quand même rendu vide. Les deux
> questions sont indépendantes, et seule la seconde décide de ce qui part en production.

## Journal des découvertes

| Date | Découverte | Impact |
|---|---|---|
| 2026-08-15 | Pas d'ImGui côté Lua ; PalMiniMap dépend d'un `.pak` | Voie d'affichage de M1 non prouvée → spike de rendu créé avant tout code de minimap |
| 2026-08-15 | Les headers UHT de la 1.0 sont publiés dans `localcc/PalworldModdingKit` (`62fad41`, 2026-07-11) | Le dump `CTRL+H` n'est plus un prérequis. Statut 📘 créé, matrice de cibles remplie hors jeu |
| 2026-08-15 | La Palbox est lisible via `APalPlayerState:GetPalStorage()`, sans ouvrir l'écran | **M2 est débloqué sans le spike de rendu** : le volet lecture/export ne touche pas à l'UI |
| 2026-08-15 | Aucun header ne mentionne « Mutation » | Le mécanisme 1.0 porte un autre nom interne ou vit en Blueprint → seule piste restante, l'ObjectDump |
| 2026-08-15 | `FPalBreedingItemEffectData.CombiRankBonus` existe | Le CombiRank est modifiable par objet en 1.0 : une table de rangs figée serait fausse même sans patch |
| 2026-08-15 (run en jeu) | `GetPalStorage()` rend vide alors que l'instance existe au runtime | La chaîne M2 passe 📘 → ❌. Statut ❌ créé, cascade de 4 voies écrite dans `query.lua`, sonde `F9` ajoutée à `PalKitBox` |
| 2026-08-15 (run en jeu) | **Deux `BP_PalPlayerState_C` vivants**, un seul porte la Palbox | Suspect n°1 de l'échec ci-dessus. `GetPalPlayerState()` passe devant la propriété moteur `PlayerState` partout dans `query.lua` |
| 2026-08-15 (run en jeu) | `FindAllOf("WidgetBlueprintGeneratedClass")` rend 0 pour 668 classes réelles | Le palier 2 du spike ne pouvait pas produire de candidat : paliers 3 et 4 jamais atteints. Découverte refondée sur `StaticFindObject(<chemin>)` + classes des instances vivantes |
| 2026-08-15 (run en jeu) | Les `UserWidget` sous `/Game/….:WidgetTree.X` sont des **modèles de CDO** | Les « 3 204 widgets vivants » étaient trompeurs. Le spike distingue désormais instances (`/Engine/Transient`) et modèles — instancier un modèle n'aurait rien affiché |
| 2026-08-15 (ObjectDump) | La conversion monde → carte vit bien dans le Blueprint : `WBP_Map_Body_C:CalcMapImagePosition` & co. | Dernier ⬜ structurel de M1 comblé. Reste la seule question du spike : peut-on **afficher** |
| 2026-08-15 (ObjectDump) | `WBP_Ingame_Compass_C` et ses icônes typées existent | Point d'entrée de M1 plus prometteur que la carte : un HUD déjà fait pour rester à l'écran. Devient la 2ᵉ cible du spike |
| 2026-08-15 (ObjectDump) | La formule de mutation est **paramétrée** dans `UPalGameSetting` (`Combi_Mutation*`) | Le trou M4 est comblé — et l'affirmation « aucun header ne mentionne Mutation » était fausse : elle venait d'un grep partiel. Voir l'encadré de correction en M4 |
