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
| **UE4SS expose les `UFunction` comme des `userdata` appelables**, pas comme des `function` Lua | `type(obj.Methode) == "userdata"`, et pourtant `obj:Methode()` fonctionne. **Ne jamais filtrer sur `type(...) == "function"`** avant d'appeler : c'est le bug qui a fait échouer les runs 1 et 2. Tenter l'appel sous `pcall` est le seul test valable. | run 2, 2026-08-15 |
| **Les valeurs de retour aussi sont des `userdata`** (FName, FText, enums) | Elles ne sont pas sérialisables telles quelles — un seul champ de ce type a fait perdre un export de 723 Pals déjà lus. Conversion, dans cet ordre : `ToString()` (FName/FString/FText), `get()` (RemoteUnrealParam), `GetValue()` (enums). Ce qui résiste aux trois est **écarté et nommé**, jamais transformé en `"userdata: 0x…"`. | run 3, 2026-08-15 |
| Les **`UFUNCTION static`** sont appelables via leur CDO | `StaticFindObject("/Script/Pal.Default__PalUtility")` puis appel normal. Un `FGuid` passe en paramètre sans conversion. Ouvre `UPalUtility`, `UPalBreedingUtility` et la famille `UPalMasterDataTableAccess_*` — donc M4. | run 3, 2026-08-15 |
| La conversion **`TArray` → table Lua** marche : **`ForEach`** | Les passifs sortent (`Legend`, `ElementBoost_Dark_2_PAL`…). L'échec du run 3 n'était pas la conversion mais l'objet : sur un slot non répliqué, le TArray n'a pas d'UObject propriétaire. Élément déballé par `:get()`. | run 4, 2026-08-15 |
| **La réplication ne couvre que la page courante de la Palbox** | 30 slots sur 960 portent des données. Voir l'encadré M2. C'est le verrou majeur restant. | run 4, 2026-08-15 |
| Un **slot occupé n'est pas un Pal lisible** | `IsEmpty()` répond `false` sur des slots dont aucun champ ne sort. Ne jamais compter les Pals sur l'occupation d'un slot : le champ témoin est l'espèce. | run 4, 2026-08-15 |
| **`GetDesiredSize()` vaut 0×0 dans la frame de l'`AddToViewport`** | Slate n'a pas encore fait sa passe de layout. Au run 4, les cinq cibles — y compris la carte entière — rendaient `0×0`, ce qui n'avait aucun sens. Mesurer après un délai (`ExecuteWithDelay`, 500 ms). | run 4, 2026-08-15 |
| Le logger PalKit **dédoublonne sur la chaîne de format** (fenêtre 60 s) | Un message paramétré émis pour dix méthodes différentes n'apparaît **qu'une fois**. Dans un diagnostic, utiliser `always(niveau, …)`, qui ne dédoublonne pas — sinon la cause racine reste invisible. | run 2, 2026-08-15 |
| `ExecuteInGameThread` est **asynchrone** | Ce qui suit l'appel s'exécute *avant* le callback. Au run 2, le palier 4 du spike a conclu « aucun widget affiché » 8 ms avant que le widget soit créé. Tout ce qui dépend du résultat doit être enchaîné **dans** la continuation. | run 2, 2026-08-15 |
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
| Voie d'affichage en Lua pur — **API** | ✅ | **`UWidgetBlueprintLibrary::Create(world, class, controller)` puis `AddToViewport(0)` fonctionnent.** Widget construit sous la GameInstance (`…BP_PalGameInstance_C_2147482476.WBP_CompassIconBase_C_2147419588`), `AddToViewport` sans erreur. Le CDO se prend par `StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")` | log F5 run 2 | 2026-08-15 |
| Voie d'affichage en Lua pur — **visibilité à l'écran** | ⬜ | Confirmé au run 3 : `IsInViewport = true`, jeu toujours répondant, curseur non capturé. Reste à établir qu'un widget est **visible** — le spike mesure désormais `IsVisible`, `RenderOpacity` et `DesiredSize` (une taille nulle = attaché mais sans place), et change de cible à chaque `F5` | log F5 run 3 | 2026-08-15 |
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

> ✅ **Cause de l'échec des runs 1 et 2 : un bug de PalKit, pas du jeu.** `query.call`
> n'appelait une méthode que si `type(fn) == "function"`. Or **UE4SS expose les `UFunction`
> comme des userdata appelables** (`__call`), jamais comme des fonctions Lua : ce garde
> rejetait donc *toutes* les méthodes du jeu, en silence. `GetPalStorage`,
> `GetPalPlayerState`, `GetPageNum`, `GetSlot` — un seul et même défaut.
>
> Le 2e run l'a rendu visible (`GetPalPlayerState : membre présent mais non appelable
> (type userdata)`), et une seule ligne l'a montré : le logger dédoublonne sur la chaîne de
> format, identique pour toutes les méthodes, si bien que les échecs suivants étaient
> supprimés. Corrigé des deux côtés — l'appel ne teste plus le type, et les messages de
> diagnostic passent par `always("DEBUG")`, sans dédoublonnage.
>
> **L'hypothèse « deux `BP_PalPlayerState_C`, un seul porte la Palbox » n'était donc pas la
> cause** — mais l'observation reste vraie, et la cascade de voies qu'elle a motivée reste
> utile : c'est elle qui a permis de lire la Palbox par `.PalStorage` alors qu'aucun appel
> ne passait.

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

| # | Voie | Statut | Résultat au run 3 (garde d'appel corrigé) | Source |
|---|---|---|---|---|
| 1 | `APalPlayerState:GetPalStorage()` | ✅ | **Voie retenue.** La plus propre, et elle passe : `PageNum = 32`, `SlotNumInPage = 30`, `GetSlot(0,0)` rend un slot | `PalPlayerState.h:573` |
| 2 | `APalPlayerState.PalStorage` (propriété) | ✅ | Rend le même objet. Utile comme repli : une propriété se lit là où un appel échoue | `PalPlayerState.h:180` |
| 3 | `UPalUtility.GetPalStorageDataByPlayerUID(world, uid)` | ✅ | Fonctionne, **CDO statique compris** (`/Script/Pal.Default__PalUtility`) : preuve qu'on peut appeler les `UFUNCTION static` du jeu, et que `FGuid` passe en paramètre | `PalUtility.h:1182` |
| 4 | `FindAllOf("PalPlayerDataPalStorage")` | ✅ | Même objet, CDO écarté. Filet fonctionnel, mais parcours global : hors boucle et une seule fois | ObjectDump |

> Les quatre voies convergent sur la même instance. La voie 3 est celle qui **généralise le
> plus** : appeler une fonction statique par son CDO ouvre tout `UPalUtility`, `UPalBreedingUtility`
> et la famille `UPalMasterDataTableAccess_*` — donc M4.

> En amont des voies 1 et 2, le PlayerState se résout par
> `APalPlayerController:GetPalPlayerState()` (📘 `PalPlayerController.h:935`) **avant** la
> propriété moteur `PlayerState`.
>
> ⚠️ **Les dimensions ne prouvent rien.** `PageNum` et `SlotNumInPage` sont deux propriétés
> répliquées : elles se lisent parfaitement sur un storage dont plus aucune méthode ne
> répond. Au run 2, une voie annonçant 32 × 30 a été retenue alors que `GetSlot(0,0)` rendait
> `nil` — et l'export a produit « 0 Pal, 960 slots illisibles » en se déclarant satisfait.
> Le seul test qui engage est **de sortir un slot**, et c'est désormais celui qu'applique
> `query.storageAnswers`.

### Conteneurs

| Cible | Statut | Classe | Fichier |
|---|---|---|---|
| Palbox (données joueur) | ✅ | `UPalPlayerDataPalStorage`, atteint par `APalPlayerState.PalStorage`. 32 pages × 30 slots lus en jeu | run 2, 2026-08-15 |
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

> ✅ **Chaîne validée en jeu au run 3** : 723 Pals lus sur 960 slots (237 vides, **0
> illisible**), en une passe et sans ouvrir l'écran. Les statuts ci-dessous marqués ✅ ont été
> effectivement lus ; la source est `run 3, 2026-08-15`.
>
> ⛔ **Mais seule la page courante porte des données (run 4).** L'export du run 4 contient
> 727 entrées dont **30 seulement — exactement une page de 30 slots — ont des champs**. Les
> 697 autres sont des coquilles : le slot existe, `IsEmpty()` répond `false`, et tout accès
> aux données rend « *Tried calling a member function but the UObject instance is nullptr* ».
>
> **Cause : la réplication.** `UPalPlayerDataPalStorage` porte `SyncPageIndex` et
> `bIsForceSyncAllSlot`, et `UPalIndividualCharacterSlot` ne réplique ses données que via
> `ReplicateHandleID` / `ReplicateIndividualParameter` (`ReplicatedUsing=…`). Le client ne
> reçoit donc que la page synchronisée — même en solo, où le jeu tourne malgré tout en
> client/serveur local. Le résumé du run 3 (« 723 Pals ») était faux pour la même raison : il
> comptait un Pal dès qu'un slot était occupé, sans vérifier qu'un champ en sortait.
>
> ❌ **Les deux contournements en lecture seule ont échoué (run 5).** `TargetContainer` rend
> bien **960 slots sur 960** — l'*accès* n'a jamais été le problème — mais les données
> restent absentes : toujours 30 Pals, 697 coquilles, une seule page.
> `CachedNonEmptySlots_InServer` est vide côté client. Ce n'est donc pas la pagination de
> l'accès qui bloque, c'est bien la **réplication**.
>
> ✅ **Solution retenue : `APalPlayerState::RequestPalBoxSyncPage_ToServer(pageIndex)`**
> (📘 `PalPlayerState.h:338`, `UFUNCTION(BlueprintCallable, Reliable, Server)`, confirmée au
> runtime par l'ObjectDump). C'est la fonction que l'écran Palbox appelle lui-même quand le
> joueur tourne les pages. Le mod la boucle sur les pages, lit après chaque réponse
> (250 ms), puis **restaure la page d'origine**.
>
> ⚠️ **Cela sort du read-only strict du brief §3.2** — pas parce qu'on modifie une donnée
> (aucune sauvegarde n'est touchée : on demande l'envoi de données qui existent déjà), mais
> parce qu'on change un état de synchronisation. **Arbitré avec Lucas le 2026-08-15.**
> `syncPages = false` rend au mod un comportement strictement passif.

| Champ | Statut | Propriété `SaveParameter` | Getter |
|---|---|---|---|
| Espèce | ✅ | `CharacterID` (FName → `ToString()`), ex. `BOSS_IceHorse_Dark` | `GetCharacterID()` |
| Surnom | ✅ | `NickName` (vide sur les Pals non renommés), `FilteredNickName` | `GetNickNameWithOnlineID(out)` / `GetNickNameByCheckBlockedUser(out)` |
| Genre | 📘 | `Gender` (`EPalGenderType`) | `GetGenderType()` |
| Niveau | ✅ | `Level` (uint8), `Exp` (int64) | `GetLevel()` ✅ **appelable** — les getters de `UPalIndividualCharacterParameter` sont donc exploitables, `GetWorkSuitabilityRanksWithCharacterRank()` en tête |
| IVs | 📘 | `Talent_HP`, `Talent_Melee`, `Talent_Shot`, `Talent_Defense` (uint8) | — |
| Passifs | ✅ | `PassiveSkillList` (TArray\<FName\>) — lu **via `ForEach`**, élément déballé par `:get()`. Ex. `Legend`, `ElementBoost_Dark_2_PAL`, `PAL_Sanity_Up_2` | `GetPassiveSkillList()` — désormais tenté **avant** la propriété : le TArray d'un struct n'a pas toujours d'UObject propriétaire |
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
| 2026-08-15 (run 2) | **Cause racine des deux échecs : `type(fn) == "function"` dans `query.call`.** UE4SS rend des `userdata` appelables | Un seul défaut, chez nous, expliquait `GetPalStorage`, `GetPalPlayerState`, `GetPageNum` et `GetSlot`. L'hypothèse « deux PlayerState » est **infirmée** comme cause (l'observation reste vraie). Le garde de type est supprimé : on tente l'appel |
| 2026-08-15 (run 2) | Le dédoublonnage du logger masquait 3 échecs sur 4 (même chaîne de format) | Les messages de diagnostic passent en `always("DEBUG")`. Une sonde qui dédoublonne cache précisément ce qu'elle cherche |
| 2026-08-15 (run 2) | **La Palbox est lue** : `.PalStorage` → 32 pages × 30 slots | Voie 2 retenue. Les voies 1 et 3 sont à revalider maintenant que les appels passent |
| 2026-08-15 (run 2) | Un storage peut annoncer ses dimensions **sans qu'aucun slot ne réponde** | `PageNum`/`SlotNumInPage` sont des propriétés répliquées. `storageAnswers` exige désormais un `GetSlot(0,0)` valide — sinon l'export sort « 0 Pal » en se déclarant satisfait |
| 2026-08-15 (run 2) | **`Create()` + `AddToViewport()` fonctionnent en Lua pur** | La question centrale de M1 est tranchée côté API : pas besoin de `.pak` pour instancier un widget du jeu. Reste la visibilité à l'écran |
| 2026-08-15 (run 2) | `ExecuteInGameThread` est asynchrone : le palier 4 jugeait 8 ms trop tôt | Tout ce qui dépend d'un résultat du game thread s'enchaîne désormais dans la continuation |
| 2026-08-15 (run 3) | **La Palbox est entièrement lue : 723 Pals, 0 slot illisible** | M2 v0 est atteint. Les 4 voies d'accès répondent, la voie 1 (la plus propre) est retenue. Les getters de `UPalIndividualCharacterParameter` sont appelables → toute la colonne « Getter » devient exploitable |
| 2026-08-15 (run 3) | Les **valeurs de retour** sont des `userdata` (FName, enums), pas seulement les fonctions | Un seul champ de ce type a fait perdre l'export complet de 723 Pals déjà lus. Cascade de conversion `ToString`/`get`/`GetValue` au point de lecture, **plus** un filet avant écriture : une valeur exotique ne doit jamais coûter le fichier entier |
| 2026-08-15 (run 3) | Les **`UFUNCTION static` passent par le CDO** (`Default__PalUtility`), `FGuid` compris | Débloque `UPalUtility`, `UPalBreedingUtility` et les `UPalMasterDataTableAccess_*` : c'est la voie d'accès aux data tables, donc à M4 |
| 2026-08-15 (run 3) | **La conversion `TArray` → Lua résiste** (`PassiveSkillList`) | Dernier verrou de M2 v1 : passifs, `EquipWaza`, `CraftSpeeds` en dépendent tous. 4 API tentées, erreur exacte conservée pour trancher au prochain run |
| 2026-08-15 (run 4) | **L'export sort, et les `TArray` se lisent via `ForEach`** | Passifs confirmés. Le verrou du run 3 n'était pas la conversion mais l'objet sous-jacent |
| 2026-08-15 (run 4) | **Seule la page courante est répliquée : 30 Pals réels sur 727 annoncés** | Le verrou majeur de M2. Le comptage était faux (un slot occupé ≠ un Pal lu), ce qui a masqué le problème deux runs de suite. Deux contournements en lecture seule implémentés : `TargetContainer` et `CachedNonEmptySlots_InServer` |
| 2026-08-15 (run 4) | `GetDesiredSize()` mesuré dans la frame de l'ajout vaut toujours `0×0` | La mesure du spike était prise avant la passe de layout de Slate — verdict sans valeur sur les 5 cibles. Différée de 500 ms |
| 2026-08-15 (run 5) | **Le comptage honnête confirme le verrou** : 30 lus / 697 coquilles, 1 page sur 32 | Le rapport dit enfin ce qu'il lit. `TargetContainer` rend 960/960 slots : l'accès n'était pas le problème, la réplication l'est |
| 2026-08-15 (run 5) | **`RequestPalBoxSyncPage_ToServer` existe** (`PalPlayerState.h:338`, Reliable/Server) | La fonction que l'UI utilise pour tourner les pages. Seule voie vers un export complet ; sort du read-only strict, **arbitré avec Lucas** ; page d'origine restaurée, désactivable par `syncPages` |
