# testing.md — installation et protocole de test

Ce document s'adresse à Lucas, qui est le **runtime** du projet : il installe, lance, teste et
renvoie les logs. Chaque étape est donc explicite jusqu'à la touche à presser.

> **État au 2026-08-15, après ton 4ᵉ run — l'export sort, mais il n'est pas complet.** Le JSON
> est écrit, avec espèce, IVs, rang, âmes et **passifs**. En l'analysant, un problème est
> apparu que les résumés précédents masquaient : sur 727 entrées, **30 seulement portent des
> données** — exactement une page. Le jeu ne réplique côté client que la page synchronisée,
> même en solo. Le mod comptait un Pal dès qu'un slot était *occupé*, d'où le « 723 Pals »
> rassurant des runs précédents. C'est corrigé : il compte maintenant ce qu'il lit vraiment,
> et deux nouvelles voies contournent la pagination. **Tu peux sauter les parties 1 et 2.**

## Par quoi commencer — 6ᵉ passe

| Priorité | Quoi | Ce qu'on cherche | Build Dev ? |
|---|---|---|---|
| 1 | **`F8`** (résumé, sans fichier) | `N Pals lus, M coquilles`. Attendu : **~727 lus, ~0 coquille** | **Non** |
| 2 | **`F7`** si `F8` est bon | Le JSON complet — le livrable de M2 v0 | **Non** |
| 3 | **`F5`** ×2, avec `F6` entre | La ligne `DesiredSize`, mesurée 500 ms après l'ajout | Oui |

**Nouveau : `F7` et `F8` prennent maintenant ~8 secondes** au lieu d'être instantanés. Le mod
parcourt les 32 pages en demandant au serveur de synchroniser chacune — c'est exactement ce
que fait le jeu quand tu tournes les pages de la Palbox, en plus rapide. Le log affiche
`Parcours des 32 pages avec resynchronisation` au démarrage. **Laisse-le finir avant de
presser autre chose.**

À surveiller pendant le parcours : si tu as **la Palbox ouverte à l'écran**, la page affichée
peut bouger. Ferme-la avant de presser `F7`, c'est plus sûr — et dis-moi si tu observes quoi
que ce soit d'anormal (page qui saute, ralentissement, message d'erreur du jeu).

**Ce que j'attends**, dans l'ordre :

1. **La ligne de résumé de `F8`** — c'est elle qui dit si le verrou est levé.
2. **Le JSON** (dépose-le à côté du log, comme les fois précédentes : je l'analyse
   directement, c'est lui qui fait foi, pas le résumé).
3. La ligne `DesiredSize` du spike : autre chose que `0.0x0.0` = un widget qui occupe une
   vraie place à l'écran, donc la réponse à la question de M1.

⚠️ **La sonde est sur `F11`**, pas F9 : ton `PalKitDump` occupe F9 (dump d'objets) et F10
(acteurs), et presser F9 déclenchait un dump de 127 Mo **avant** la sonde.

Le dump `CTRL + J` est **fait** (merci) et dépouillé : il a donné les noms de Blueprints, la
conversion monde → carte et les paramètres de mutation. Le seul dump encore utile est
`CTRL + NUM_7` **en extérieur**, pour les acteurs du monde (Pals sauvages, coffres, donjons)
— et il n'est pas urgent.

Le dump `CTRL + H` (headers) **n'est plus nécessaire** : les mêmes signatures sont publiées
dans le `PalworldModdingKit`, à jour pour la 1.0, et sont déjà dépouillées dans
`docs/sdk-notes.md`.

---

## Partie 1 — Installation d'UE4SS (à faire une seule fois)

### 1.1 Récupérer le bon build

Aller sur les releases du fork Okaetsu, tag **`experimental-palworld`** :
<https://github.com/Okaetsu/RE-UE4SS/releases/tag/experimental-palworld>

Deux zips y figurent. Il faut **`UE4SS-Palworld_zDev.zip`** — le build **Dev**.

> ⚠️ **Pas `UE4SS-Palworld.zip`.** C'est la version joueur : elle fait tourner les mods, mais
> elle n'a **ni Live View ni dumpers**. Or c'est exactement ce dont on a besoin, puisqu'on ne
> peut pas deviner les noms de classes internes de Palworld.

> ⚠️ **Ne pas passer par Vortex** pour cette étape. Vortex déploie des versions cassées
> d'UE4SS (brief §2). Installation manuelle uniquement.

### 1.2 Décompresser

Trouver le dossier d'installation de Palworld — celui qui contient le dossier `Pal`.
Typiquement :

```
C:\Program Files (x86)\Steam\steamapps\common\Palworld
```

Si Steam est sur un autre disque, chercher `steamapps\common\Palworld` sur ce disque.

Décompresser le contenu du zip en suivant les instructions de la release. Aucun fichier
existant ne doit être écrasé.

### 1.3 Repérer le dossier Mods, et me le dire

Le layout a changé entre l'Early Access et la 1.0, et **les deux coexistent** selon les
installations. Un seul des deux existera chez toi :

```
Palworld\Mods\NativeMods\UE4SS\Mods\          ← layout 1.0 (loader officiel / Workshop)
Palworld\Pal\Binaries\Win64\ue4ss\Mods\       ← layout historique / install manuelle
```

**Note-moi lequel des deux tu as.** C'est la seule information dont j'ai besoin pour calibrer
la suite, et le code s'y adapte tout seul (aucun chemin n'est écrit en dur).

### 1.4 Vérifier que le build Dev fonctionne

1. Lancer Palworld
2. Presser **`CTRL + O`**

**Attendu :** une fenêtre UE4SS s'ouvre par-dessus le jeu.

**Si rien ne s'ouvre :** c'est le zip joueur qui est installé, pas le Dev. Reprendre en 1.1.
C'est le point de contrôle le plus important de cette page — inutile d'aller plus loin tant
qu'il n'est pas franchi.

---

## Partie 2 — Générer les dumps

Ces dumps sont ce qui me permet d'arrêter de deviner. Il en reste **deux** qui comptent : les
headers, eux, sont désormais récupérés en ligne (voir `scripts/fetch-headers.sh`).

> **Sur un monde de test, jamais sur la sauvegarde principale.** Les dumps sont en lecture
> seule, mais le build Dev est instable par nature et on ne prend pas ce risque.

Jeu lancé, monde de test chargé :

| Ordre | Touches | Produit | Priorité |
|---|---|---|---|
| 1 | **`CTRL + J`** | `UE4SS_ObjectDump.txt` — tous les objets, **avec les Blueprints** | **la plus haute** |
| 2 | **`CTRL + NUM_7`** | dump de tous les acteurs | haute — voir ci-dessous |
| 3 | ~~`CTRL + H`~~ | headers C++ / SDK | **plus nécessaire** — remplacé par les headers publics 1.0. À ne faire que si je te le demande pour un contrôle croisé |
| 4 | **`CTRL + NUM_6`** | fichier `.usmap` | facultative — sert aux outils de sauvegarde, pas à PalKit |

Chaque dump prend de quelques secondes à une minute ; le jeu peut se figer pendant
l'opération, c'est normal.

### Le dump d'acteurs, à faire deux fois

`CTRL + NUM_7` ne capture que ce qui est **chargé à cet instant**. Deux passes, donc :

- **Passe A** — dehors, en extérieur, au milieu de Pals sauvages → nourrit M1 (marqueurs)
- **Passe B** — **Palbox ouverte à l'écran** → nourrit M2 (les widgets de la Palbox n'existent
  que quand l'écran est ouvert)

Renomme les fichiers `acteurs-exterieur.txt` et `acteurs-palbox.txt` pour que je les
distingue.

### Où les récupérer

Les fichiers sont écrits à côté du binaire UE4SS, dans le dossier repéré en 1.3 (souvent un
sous-dossier de `ue4ss`). Si tu ne les trouves pas, cherche `UE4SS_ObjectDump.txt` depuis la
racine de Palworld.

### Où les déposer

Sur **Google Drive** — ces fichiers font facilement plusieurs dizaines de Mo, ne les colle pas
dans le chat. J'irai les y lire directement.

---

## Partie 3 — Tester un mod

### Installation d'un mod PalKit

1. Récupérer le dossier `dist\<NomDuMod>\` du dépôt
2. Le copier dans le dossier Mods repéré en 1.3
3. Ouvrir `Mods\mods.txt` et y ajouter une ligne : `<NomDuMod> : 1`

Depuis Windows, `scripts\install-dev.ps1` fait les trois étapes automatiquement :

```powershell
.\install-dev.ps1 -Mod PalKitSpike
```

### La boucle de test

**`INS`** recharge les mods Lua **sans relancer le jeu**. C'est ce qui rend la boucle
supportable — utilise-la plutôt que de redémarrer.

> **En multi / serveur dédié :** il faut parfois presser `INS` **après** le chargement du
> monde pour que les mods s'initialisent. Le game state n'est pas réinitialisé comme en solo.

### Ce qu'il faut me renvoyer quand ça casse

1. **`UE4SS.log`** — toujours. C'est le seul canal de retour ; tout PalKit y écrit avec le
   préfixe `[PalKit]`.
2. Une **capture d'écran** si le problème est visuel.
3. Une précision qui change tout mon diagnostic : **le jeu a-t-il crashé, ou a-t-il seulement
   mal affiché ?** Ce sont deux causes différentes.

---

## Protocole par module

### PalKitBox — export de la Palbox *(à tester en premier)*

**Ce qu'on cherche à savoir :** la chaîne de lecture déduite des headers 1.0 tient-elle en jeu ?
Le mod parcourt les pages de la Palbox et écrit un JSON. Il **ne modifie rien** : aucun hook,
aucun setter — un échec ne peut pas abîmer une sauvegarde.

Il n'a besoin **ni du build Dev, ni du spike, ni de la Palbox ouverte à l'écran**.

- Copier : `dist\PalKitBox\` → dossier Mods ; ajouter `PalKitBox : 1` à `mods.txt`
- Lancer, charger un monde (de test de préférence, mais une vraie partie est plus parlante :
  plus il y a de Pals, mieux c'est)
- En multi / serveur dédié : presser `INS` une fois le monde chargé
- Presser **`F11`** → **la sonde, à faire en premier** (voir juste en dessous)
- Presser **`F7`** → export JSON
- Presser **`F8`** → même lecture, résumé dans le log seulement

#### `F11` — la sonde de diagnostic *(nouveau, à presser avant `F7`)*

Au premier run, `F7` a rendu une seule ligne : `GetPalStorage n'a rien renvoyé`. C'était vrai
mais inexploitable — ça ne disait pas *pourquoi*. `F11` essaie les **quatre voies d'accès**
connues à la Palbox et rend compte de chacune, même après qu'une ait réussi.

**Attendu dans `UE4SS.log` :** un bloc `======== Sonde Palbox ========` contenant

1. le PlayerController et le World,
2. le PlayerState vu par les **deux** voies (`GetPalPlayerState()` et `.PlayerState`) — s'ils
   diffèrent, un `WARN` le signale, et la cause du bug du 15/08 est trouvée,
3. les 4 voies, chacune avec son verdict et, si elle rend un objet, un test en profondeur
   (`GetPageNum`, `GetSlot(0,0)`, jusqu'à lire le `CharacterID` d'un vrai Pal),
4. une ligne finale `VERDICT : voie retenue -- <nom>`, ou l'échec des quatre.

| Résultat de `F11` | Ce qu'on en fait |
|---|---|
| `VERDICT : voie retenue -- …` | M2 est débloqué. `F7` doit produire le JSON dans la foulée |
| Les 4 voies échouent | Les lignes `DEBUG` du bloc disent, voie par voie, si le membre est **absent**, **non appelable** ou s'il **lève** — trois causes, trois corrections différentes. Renvoie le log, je tranche |

> **Ce qui a changé depuis le 2ᵉ run**, et qu'il faut regarder en priorité : une voie n'est
> retenue que si `GetSlot(0,0)` **sort un slot**. Au run précédent, une voie annonçait
> « 32 pages × 30 slots » puis se déclarait inexploitable deux lignes plus bas… et était
> quand même retenue ; `F7` sortait alors « 0 Pal » en annonçant « toutes les entrées header
> sont confirmées ». Les dimensions sont deux propriétés répliquées : elles se lisent même
> quand plus aucune méthode ne répond. Un export sans Pal se déclare désormais **en échec**.

**Attendu dans `UE4SS.log` :** un bloc `======== Export Palbox ========`, une ligne
`Palbox : N Pals, …`, trois exemples de Pals, puis `export ecrit : <chemin>`.

**À me renvoyer :**
1. `UE4SS.log`
2. **le fichier JSON produit** (il est écrit à côté du mod, nommé `palbox-export-<date>.json`)
3. de mémoire : le nombre de Pals que tu as réellement en Palbox, pour comparer

Le JSON contient un tableau `warnings` : c'est le cœur du test. Chaque ligne y est un champ
que le Lua n'a pas su lire. Vide = toutes les entrées 📘 de `sdk-notes.md` passent en ✅.

| Résultat | Ce qu'on en fait |
|---|---|
| JSON complet, `warnings` vide | La chaîne headers → Lua est prouvée. M2 v1 (recherche/tri) démarre |
| JSON produit, quelques `warnings` | On corrige champ par champ — c'est le cas le plus probable (`FFixedPoint64`, énumérations) |
| `Palbox inaccessible` dans le log | `GetPalStorage` ne répond pas : je reprends par le `PlayerState` |

### PalKitSpike — sonde de faisabilité du rendu

**Ce qu'on cherche à savoir :** peut-on afficher quelque chose à l'écran en Lua pur, sans
`.pak` ? Ce mod ne fait rien d'autre. Il sera supprimé une fois la réponse obtenue.

> **Ce qui a changé depuis ton essai du 15/08.** Le palier 2 ne pouvait pas produire de
> candidat — il n'interrogeait que `FindAllOf("WidgetBlueprintGeneratedClass")`, qui rend
> `0` sur ce build alors que le jeu en compte 668. Les paliers 3 et 4 étaient donc
> systématiquement sautés, et la question du spike restait sans réponse. Il vise maintenant
> des classes **nommées**, tirées de ton ObjectDump : la boussole du jeu d'abord
> (`WBP_CompassIconBase_C`, puis `WBP_Ingame_Compass_C`), la carte ensuite.

- Copier : `dist\PalKitSpike\` → dossier Mods détecté ; ajouter `PalKitSpike : 1` à `mods.txt`
- Lancer, charger **un monde de test**
- Presser **`F5`**, regarder l'écran, presser **`F6`**, puis **`F5`** à nouveau : chaque
  pression essaie **la cible suivante** (le log annonce `Cible N/12`). Quatre passes suffisent
  à couvrir les cibles nommées — icône de boussole, boussole complète, corps de carte, carte
- Attendu : `UE4SS.log` contient un bloc `======== SPIKE DE RENDU ========` avec les
  4 paliers. Le palier 2 doit annoncer `Palier 2 OK (N candidats)` et le palier 3 doit
  **s'exécuter** (quel que soit son verdict). Possiblement un élément d'interface apparaît.
- Presser **`F6`** pour retirer ce que F5 a ajouté et pouvoir recommencer.
- **Recommencer `F5` avec la carte du jeu ouverte** : certains packages d'UI ne sont chargés
  qu'à la première ouverture de l'écran concerné, et `StaticFindObject` ne trouve que le
  chargé. Si la voie A annonce des classes `absente (package non charge ?)`, c'est ça.
- À renvoyer : `UE4SS.log` + capture, **et la réponse à ces deux questions** :
  1. Vois-tu quelque chose de nouveau à l'écran ?
  2. Le jeu répond-il toujours (déplacement, caméra) ?

**Bonus utile :** relancer `F5` une seconde fois avec la **Palbox ouverte**. Le palier 2 liste
les widgets vivants — c'est de la reconnaissance directement réutilisable pour M2, gratuite.

Aucun des trois résultats possibles n'est un échec du projet :

| Résultat | Ce qu'on en fait |
|---|---|
| Widget instancié **et visible** | La voie Lua pur est prouvée → M1 V1 démarre |
| Instancié mais **invisible** | On vise un widget conteneur générique qu'on peuple nous-mêmes |
| **Rien d'instanciable** | On rouvre l'arbitrage `.pak`, avant d'avoir écrit la minimap |

> **Au 2ᵉ run, la ligne 1 est à moitié acquise** : `Create()` a construit le widget et
> `AddToViewport` l'a accepté sans erreur — donc « rien d'instanciable » est écarté. Ce qui
> manque est ta réponse à la question posée à l'écran : **as-tu vu quelque chose ?** Une
> icône de boussole seule (`WBP_CompassIconBase_C`) est probablement vide tant qu'on ne lui
> donne pas de données, donc « je n'ai rien vu » n'est pas un échec — mais ça décide de la
> cible du prochain essai (icône à peupler, ou widget autoporteur type
> `WBP_Ingame_Compass_C`).
