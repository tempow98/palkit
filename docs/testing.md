# testing.md — installation et protocole de test

Ce document s'adresse à Lucas, qui est le **runtime** du projet : il installe, lance, teste et
renvoie les logs. Chaque étape est donc explicite jusqu'à la touche à presser.

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

Ces dumps sont ce qui me permet d'arrêter de deviner. Sans eux, je travaille à l'aveugle.

> **Sur un monde de test, jamais sur la sauvegarde principale.** Les dumps sont en lecture
> seule, mais le build Dev est instable par nature et on ne prend pas ce risque.

Jeu lancé, monde de test chargé :

| Ordre | Touches | Produit | Priorité |
|---|---|---|---|
| 1 | **`CTRL + J`** | `UE4SS_ObjectDump.txt` — tous les objets | **la plus haute** |
| 2 | **`CTRL + H`** | headers C++ / SDK avec offsets | haute |
| 3 | **`CTRL + NUM_6`** | fichier `.usmap` | moyenne |
| 4 | **`CTRL + NUM_7`** | dump de tous les acteurs | voir ci-dessous |

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

### PalKitSpike — sonde de faisabilité du rendu

**Ce qu'on cherche à savoir :** peut-on afficher quelque chose à l'écran en Lua pur, sans
`.pak` ? Ce mod ne fait rien d'autre. Il sera supprimé une fois la réponse obtenue.

- Copier : `dist\PalKitSpike\` → dossier Mods détecté ; ajouter `PalKitSpike : 1` à `mods.txt`
- Lancer, charger **un monde de test**
- Presser **`F5`**
- Attendu : `UE4SS.log` contient un bloc `======== SPIKE DE RENDU ========` avec les
  4 paliers. Possiblement un élément d'interface apparaît à l'écran.
- Presser **`F6`** pour retirer ce que F5 a ajouté et pouvoir recommencer.
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
