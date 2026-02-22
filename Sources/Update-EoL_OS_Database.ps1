<#
.SYNOPSIS
    Wrapper pour la mise à jour de la base de données End-of-Life (EoL).

.DESCRIPTION
    Ce script expose la fonction Update-EoL_OS_Database (alias : Update-EoL)
    qui charge EoL-Functions.ps1 puis appelle Update-EoLFromAPI pour
    récupérer les dates de fin de support depuis l'API endoflife.date.

    Ce fichier a été extrait de ModernActiveDirectoryEnhanced.psm1 pour
    faciliter le troubleshooting indépendamment du module principal.

.PARAMETER Products
    Liste des produits à mettre à jour.
    Défaut : "windows", "windows-server", "ubuntu", "macos", "debian", "rhel", "sles"

.PARAMETER Force
    Force la mise à jour même si les données sont récentes.

.EXAMPLE
    # Dot-sourcer le fichier puis appeler la fonction
    . .\Update-EoL_OS_Database.ps1
    Update-EoL_OS_Database

.EXAMPLE
    . .\Update-EoL_OS_Database.ps1
    Update-EoL -Products "windows-server" -Force

.NOTES
    Prérequis : EoL-Functions.ps1 doit être dans le même dossier que ce fichier.
#>

function Update-EoL_OS_Database {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string[]]$Products = @("windows", "windows-server", "ubuntu", "macos", "debian", "rhel", "sles"),
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    # TOUJOURS recharger EoL-Functions.ps1 pour prendre en compte les modifications
    $modulePath = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

    if ($modulePath) {
        $eolPath = Join-Path $modulePath "EoL-Functions.ps1"
        if (Test-Path $eolPath) {
            try {
                # Forcer le rechargement à chaque appel
                . $eolPath
                Write-Verbose "EoL-Functions.ps1 rechargé depuis: $eolPath"
            } catch {
                Write-Host ""
                Write-Host "[ERROR] Impossible de charger EoL-Functions.ps1: $($_.Exception.Message)" -ForegroundColor Red
                Write-Host ""
                return
            }
        } else {
            Write-Host ""
            Write-Host "[ERROR] Fichier EoL-Functions.ps1 introuvable dans: $modulePath" -ForegroundColor Red
            Write-Host ""
            return
        }
    }
    
    # Appeler la fonction originale — elle gère elle-même l'affichage complet (header + footer)
    Update-EoLFromAPI -Products $Products -Force:$Force
}

Set-Alias -Name "Update-EoL" -Value "Update-EoL_OS_Database" -ErrorAction SilentlyContinue
