<#
    PalKit -- install-dev.ps1

    Deploie un mod construit directement dans le dossier Mods de Palworld, cote Windows.
    A lancer depuis le PC de jeu, sur un dossier dist/ recupere du depot.

    Le layout d'installation a bouge entre l'Early Access et la 1.0, et les deux coexistent
    selon les machines. Le script DETECTE le bon dossier au lieu de le supposer -- aucun
    chemin n'est ecrit en dur (brief SS2).

    Usage :
      .\install-dev.ps1 -Mod PalKitSpike
      .\install-dev.ps1 -Mod PalKitSpike -GameRoot "D:\Steam\steamapps\common\Palworld"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Mod,

    [string]$GameRoot
)

$ErrorActionPreference = "Stop"

function Find-GameRoot {
    if ($GameRoot) {
        if (-not (Test-Path $GameRoot)) { throw "GameRoot introuvable : $GameRoot" }
        return $GameRoot
    }

    # Emplacements Steam usuels, puis toutes les bibliotheques declarees dans
    # libraryfolders.vdf (Steam installe souvent les jeux sur un autre disque).
    $candidates = @(
        "C:\Program Files (x86)\Steam\steamapps\common\Palworld",
        "C:\Program Files\Steam\steamapps\common\Palworld"
    )

    $vdf = "C:\Program Files (x86)\Steam\steamapps\libraryfolders.vdf"
    if (Test-Path $vdf) {
        Select-String -Path $vdf -Pattern '"path"\s+"(.+?)"' -AllMatches |
            ForEach-Object { $_.Matches } |
            ForEach-Object {
                $lib = $_.Groups[1].Value -replace '\\\\', '\'
                $candidates += (Join-Path $lib "steamapps\common\Palworld")
            }
    }

    foreach ($c in $candidates) {
        if (Test-Path (Join-Path $c "Pal")) { return $c }
    }

    throw "Palworld introuvable. Relance avec -GameRoot '<chemin vers Palworld>'."
}

function Find-ModsDir($root) {
    # Layout 1.0 (loader officiel / Workshop) d'abord, puis le layout historique.
    $layouts = @(
        (Join-Path $root "Mods\NativeMods\UE4SS\Mods"),
        (Join-Path $root "Pal\Binaries\Win64\ue4ss\Mods")
    )

    foreach ($l in $layouts) {
        if (Test-Path $l) { return $l }
    }

    throw @"
Aucun dossier Mods UE4SS trouve sous :
  $($layouts -join "`n  ")
UE4SS est-il installe ? Voir docs/testing.md, section Installation.
"@
}

$root    = Find-GameRoot
$modsDir = Find-ModsDir $root

Write-Host "Palworld  : $root"
Write-Host "Mods UE4SS: $modsDir"

$source = Join-Path $PSScriptRoot "..\dist\$Mod"
if (-not (Test-Path $source)) {
    throw "dist\$Mod introuvable. Lancer d'abord build.sh cote Linux, puis copier dist\ ici."
}

$target = Join-Path $modsDir $Mod

# On supprime avant de recopier : un fichier .lua orphelin d'une version precedente est
# une source de confusion classique quand on debugge a distance.
if (Test-Path $target) {
    Write-Host "Suppression de l'installation precedente : $target"
    Remove-Item -Recurse -Force $target
}

Copy-Item -Recurse -Force $source $target
Write-Host "Copie : $source -> $target"

# Activation dans mods.txt
$modsTxt = Join-Path $modsDir "mods.txt"
if (Test-Path $modsTxt) {
    $content = Get-Content $modsTxt -Raw
    if ($content -notmatch [regex]::Escape($Mod)) {
        Add-Content $modsTxt "`n$Mod : 1"
        Write-Host "Ajoute a mods.txt : $Mod : 1"
    } else {
        Write-Host "Deja present dans mods.txt -- verifier que la valeur est bien 1."
    }
} else {
    Set-Content $modsTxt "$Mod : 1"
    Write-Host "mods.txt cree avec : $Mod : 1"
}

Write-Host ""
Write-Host "Termine. Lance le jeu, charge un MONDE DE TEST, puis presse la touche du mod."
Write-Host "Mods deja charges ? Presse INS en jeu pour recharger sans relancer."
