# ============================================================================
# MODULE DE VERSIONING - Base de données EoL
# ============================================================================
# Gestion des versions et de l'historique des mises à jour
# Dépendance : EoL-Functions.ps1 (chargé automatiquement si absent)
# ============================================================================

#region Dépendances
# Get-EoLDatabasePath est défini dans EoL-Functions.ps1
# Ce guard permet l'utilisation de EoL-Versioning.ps1 de manière autonome
if (-not (Get-Command Get-EoLDatabasePath -ErrorAction SilentlyContinue)) {
    $eolFunctionsPath = Join-Path $PSScriptRoot "EoL-Functions.ps1"
    if (Test-Path $eolFunctionsPath) {
        . $eolFunctionsPath
        Write-Verbose "EoL-Functions.ps1 chargé automatiquement par EoL-Versioning.ps1"
    } else {
        throw "EoL-Versioning.ps1 requiert EoL-Functions.ps1 dans le même répertoire : $eolFunctionsPath"
    }
}
#endregion

#region Configuration
$script:HistoryFolder = ".eol-history"
$script:MaxHistoryVersions = 10  # Nombre de versions à conserver
#endregion

#region Fonctions de versioning

<#
.SYNOPSIS
Crée une sauvegarde versionnée de la base de données EoL.

.DESCRIPTION
Sauvegarde le fichier JSON actuel avec un timestamp et un numéro de version.

.PARAMETER SourcePath
Chemin du fichier JSON source

.PARAMETER Reason
Raison de la sauvegarde (ex: "Mise à jour API", "Ajout manuel")

.OUTPUTS
String - Chemin du fichier de sauvegarde créé
#>
function Backup-EoLDatabase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$SourcePath,
        
        [Parameter(Mandatory = $false)]
        [string]$Reason = "Sauvegarde manuelle"
    )
    
    if (-not $SourcePath) {
        $SourcePath = Get-EoLDatabasePath
    }
    
    if (-not (Test-Path $SourcePath)) {
        Write-Error "Fichier source introuvable: $SourcePath"
        return $null
    }
    
    # Créer le dossier d'historique si nécessaire
    $historyPath = Join-Path (Split-Path $SourcePath -Parent) $script:HistoryFolder
    if (-not (Test-Path $historyPath)) {
        New-Item -Path $historyPath -ItemType Directory -Force | Out-Null
        Write-Verbose "Dossier d'historique créé: $historyPath"
    }
    
    # Lire le JSON pour obtenir la version
    try {
        $jsonContent = Get-Content -Path $SourcePath -Raw -Encoding UTF8
        $database = $jsonContent | ConvertFrom-Json
        $version = $database.metadata.version
    } catch {
        $version = "unknown"
    }
    
    # Créer le nom du fichier de backup
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupFileName = "eol-database_v${version}_${timestamp}.json"
    $backupPath = Join-Path $historyPath $backupFileName
    
    # Copier le fichier
    Copy-Item -Path $SourcePath -Destination $backupPath -Force
    
    # Créer le fichier de métadonnées
    $metaFileName = "eol-database_v${version}_${timestamp}.meta.json"
    $metaPath = Join-Path $historyPath $metaFileName
    
    $metadata = @{
        version = $version
        timestamp = $timestamp
        datetime = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        reason = $Reason
        original_file = (Split-Path $SourcePath -Leaf)
        os_count = $database.os_database.PSObject.Properties.Count
    }
    
    $metadata | ConvertTo-Json | Set-Content -Path $metaPath -Encoding UTF8
    
    Write-Host "💾 Sauvegarde créée: $backupFileName" -ForegroundColor Green
    Write-Verbose "Raison: $Reason"
    Write-Verbose "Version: $version"
    Write-Verbose "Nombre d'OS: $($metadata.os_count)"
    
    # Nettoyer les anciennes versions si nécessaire
    Clear-OldBackups -HistoryPath $historyPath -KeepVersions $script:MaxHistoryVersions
    
    return $backupPath
}

<#
.SYNOPSIS
Nettoie les anciennes sauvegardes pour ne garder que les N plus récentes.

.PARAMETER HistoryPath
Chemin du dossier d'historique

.PARAMETER KeepVersions
Nombre de versions à conserver
#>
function Clear-OldBackups {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HistoryPath,
        
        [Parameter(Mandatory = $false)]
        [int]$KeepVersions = 10
    )
    
    if (-not (Test-Path $HistoryPath)) {
        return
    }
    
    # Récupérer tous les fichiers JSON de backup (pas les .meta)
    $backups = Get-ChildItem -Path $HistoryPath -Filter "eol-database_v*.json" | 
               Where-Object { $_.Name -notlike "*.meta.json" } |
               Sort-Object CreationTime -Descending
    
    if ($backups.Count -le $KeepVersions) {
        Write-Verbose "Nombre de backups ($($backups.Count)) <= $KeepVersions, aucun nettoyage nécessaire"
        return
    }
    
    # Supprimer les anciennes versions
    $toDelete = $backups | Select-Object -Skip $KeepVersions
    
    foreach ($file in $toDelete) {
        $baseName = $file.BaseName
        
        # Supprimer le fichier JSON
        Remove-Item -Path $file.FullName -Force
        
        # Supprimer le fichier .meta associé
        $metaFile = Join-Path $HistoryPath "$baseName.meta.json"
        if (Test-Path $metaFile) {
            Remove-Item -Path $metaFile -Force
        }
        
        Write-Verbose "🗑️  Supprimé: $($file.Name)"
    }
    
    Write-Host "🧹 Nettoyage: $($toDelete.Count) ancienne(s) version(s) supprimée(s)" -ForegroundColor Gray
}

<#
.SYNOPSIS
Liste toutes les versions de backup disponibles.

.PARAMETER ShowDetails
Affiche les détails de chaque version

.OUTPUTS
Array - Liste des backups disponibles
#>
function Get-EoLBackupHistory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$ShowDetails
    )
    
    $jsonPath = Get-EoLDatabasePath
    $historyPath = Join-Path (Split-Path $jsonPath -Parent) $script:HistoryFolder
    
    if (-not (Test-Path $historyPath)) {
        Write-Host "📁 Aucun historique de sauvegarde trouvé" -ForegroundColor Yellow
        return @()
    }
    
    $backups = Get-ChildItem -Path $historyPath -Filter "eol-database_v*.json" |
               Where-Object { $_.Name -notlike "*.meta.json" } |
               Sort-Object CreationTime -Descending
    
    if ($backups.Count -eq 0) {
        Write-Host "📁 Aucune sauvegarde trouvée" -ForegroundColor Yellow
        return @()
    }
    
    Write-Host ""
    Write-Host "📚 HISTORIQUE DES VERSIONS" -ForegroundColor Cyan
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    
    $results = @()
    
    foreach ($backup in $backups) {
        # Charger les métadonnées
        $metaPath = Join-Path $historyPath "$($backup.BaseName).meta.json"
        
        if (Test-Path $metaPath) {
            $meta = Get-Content -Path $metaPath -Raw | ConvertFrom-Json
            
            $result = [PSCustomObject]@{
                Version = $meta.version
                Date = $meta.datetime
                Reason = $meta.reason
                OSCount = $meta.os_count
                File = $backup.Name
                Path = $backup.FullName
                Size = [math]::Round($backup.Length / 1KB, 2)
            }
            
            if ($ShowDetails) {
                Write-Host ""
                Write-Host "  📌 Version $($meta.version)" -ForegroundColor White
                Write-Host "     Date      : $($meta.datetime)" -ForegroundColor Gray
                Write-Host "     Raison    : $($meta.reason)" -ForegroundColor Gray
                Write-Host "     OS        : $($meta.os_count)" -ForegroundColor Gray
                Write-Host "     Taille    : $($result.Size) KB" -ForegroundColor Gray
                Write-Host "     Fichier   : $($backup.Name)" -ForegroundColor DarkGray
            }
            
            $results += $result
        } else {
            # Pas de métadonnées, afficher info basique
            $result = [PSCustomObject]@{
                Version = "unknown"
                Date = $backup.CreationTime.ToString("yyyy-MM-dd HH:mm:ss")
                Reason = "N/A"
                OSCount = "N/A"
                File = $backup.Name
                Path = $backup.FullName
                Size = [math]::Round($backup.Length / 1KB, 2)
            }
            
            if ($ShowDetails) {
                Write-Host ""
                Write-Host "  📌 $($backup.Name)" -ForegroundColor White
                Write-Host "     Date      : $($backup.CreationTime)" -ForegroundColor Gray
                Write-Host "     Taille    : $($result.Size) KB" -ForegroundColor Gray
            }
            
            $results += $result
        }
    }
    
    if (-not $ShowDetails) {
        Write-Host ""
        $results | Format-Table Version, Date, Reason, OSCount, @{Label="Taille (KB)";Expression={$_.Size}} -AutoSize
    }
    
    Write-Host ""
    Write-Host "💡 Total: $($backups.Count) version(s) | Max conservé: $script:MaxHistoryVersions" -ForegroundColor Gray
    Write-Host "💡 Pour restaurer: Restore-EoLDatabase -BackupPath <chemin>" -ForegroundColor Gray
    
    return $results
}

<#
.SYNOPSIS
Restaure une version spécifique de la base de données.

.PARAMETER BackupPath
Chemin du fichier de backup à restaurer

.PARAMETER Force
Force la restauration sans demander confirmation

.EXAMPLE
Restore-EoLDatabase -BackupPath ".eol-history/eol-database_v2.0_20250215_143022.json"
#>
function Restore-EoLDatabase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BackupPath,
        
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    
    if (-not (Test-Path $BackupPath)) {
        Write-Error "Fichier de backup introuvable: $BackupPath"
        return
    }
    
    # Valider que c'est un JSON valide
    try {
        $backupContent = Get-Content -Path $BackupPath -Raw -Encoding UTF8
        $backupData = $backupContent | ConvertFrom-Json
    } catch {
        Write-Error "Fichier de backup invalide: $($_.Exception.Message)"
        return
    }
    
    # Afficher les infos de la version à restaurer
    Write-Host ""
    Write-Host "📦 RESTAURATION DE VERSION" -ForegroundColor Cyan
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Version    : $($backupData.metadata.version)" -ForegroundColor White
    Write-Host "  Dernière MAJ: $($backupData.metadata.last_updated)" -ForegroundColor Gray
    Write-Host "  Nombre d'OS : $($backupData.os_database.PSObject.Properties.Count)" -ForegroundColor Gray
    Write-Host "  Source     : $BackupPath" -ForegroundColor DarkGray
    Write-Host ""
    
    # Demander confirmation si pas -Force
    if (-not $Force) {
        $currentPath = Get-EoLDatabasePath
        if (Test-Path $currentPath) {
            $currentData = Get-Content -Path $currentPath -Raw | ConvertFrom-Json
            Write-Warning "La base actuelle (v$($currentData.metadata.version)) sera remplacée !"
        }
        
        $response = Read-Host "Confirmer la restauration ? (O/N)"
        if ($response -ne "O" -and $response -ne "o") {
            Write-Host "❌ Restauration annulée" -ForegroundColor Yellow
            return
        }
    }
    
    # Sauvegarder la version actuelle avant restauration
    $currentPath = Get-EoLDatabasePath
    if (Test-Path $currentPath) {
        Write-Host "💾 Sauvegarde de la version actuelle..." -ForegroundColor Gray
        Backup-EoLDatabase -SourcePath $currentPath -Reason "Avant restauration vers v$($backupData.metadata.version)"
    }
    
    # Restaurer
    try {
        Copy-Item -Path $BackupPath -Destination $currentPath -Force
        Write-Host "✅ Version restaurée avec succès !" -ForegroundColor Green
        Write-Host ""
        Write-Host "📊 Base actuelle:" -ForegroundColor Cyan
        Write-Host "   Version : $($backupData.metadata.version)" -ForegroundColor White
        Write-Host "   OS      : $($backupData.os_database.PSObject.Properties.Count)" -ForegroundColor White
        
    } catch {
        Write-Error "Erreur lors de la restauration: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
Compare deux versions de la base de données.

.PARAMETER Version1Path
Chemin de la première version

.PARAMETER Version2Path
Chemin de la deuxième version (par défaut: version actuelle)

.EXAMPLE
Compare-EoLVersions -Version1Path ".eol-history/eol-database_v2.0_20250215.json"
#>
function Compare-EoLVersions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version1Path,
        
        [Parameter(Mandatory = $false)]
        [string]$Version2Path
    )
    
    if (-not $Version2Path) {
        $Version2Path = Get-EoLDatabasePath
    }
    
    if (-not (Test-Path $Version1Path)) {
        Write-Error "Version 1 introuvable: $Version1Path"
        return
    }
    
    if (-not (Test-Path $Version2Path)) {
        Write-Error "Version 2 introuvable: $Version2Path"
        return
    }
    
    # Charger les deux versions
    $v1 = Get-Content -Path $Version1Path -Raw | ConvertFrom-Json
    $v2 = Get-Content -Path $Version2Path -Raw | ConvertFrom-Json
    
    $v1OS = $v1.os_database.PSObject.Properties.Name
    $v2OS = $v2.os_database.PSObject.Properties.Name
    
    # Calculer les différences
    $added = $v2OS | Where-Object { $v1OS -notcontains $_ }
    $removed = $v1OS | Where-Object { $v2OS -notcontains $_ }
    $common = $v1OS | Where-Object { $v2OS -contains $_ }
    
    # OS modifiés
    $modified = @()
    foreach ($os in $common) {
        $v1Info = $v1.os_database.$os
        $v2Info = $v2.os_database.$os
        
        if ($v1Info.eol_date -ne $v2Info.eol_date -or 
            $v1Info.extended_support -ne $v2Info.extended_support) {
            $modified += $os
        }
    }
    
    # Affichage
    Write-Host ""
    Write-Host "🔍 COMPARAISON DE VERSIONS" -ForegroundColor Cyan
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  📌 Version 1: $($v1.metadata.version) ($($v1.metadata.last_updated)) - $($v1OS.Count) OS" -ForegroundColor White
    Write-Host "  📌 Version 2: $($v2.metadata.version) ($($v2.metadata.last_updated)) - $($v2OS.Count) OS" -ForegroundColor White
    Write-Host ""
    
    if ($added.Count -gt 0) {
        Write-Host "  ✅ OS ajoutés ($($added.Count)):" -ForegroundColor Green
        $added | ForEach-Object { Write-Host "     + $_" -ForegroundColor Green }
        Write-Host ""
    }
    
    if ($removed.Count -gt 0) {
        Write-Host "  ❌ OS supprimés ($($removed.Count)):" -ForegroundColor Red
        $removed | ForEach-Object { Write-Host "     - $_" -ForegroundColor Red }
        Write-Host ""
    }
    
    if ($modified.Count -gt 0) {
        Write-Host "  🔄 OS modifiés ($($modified.Count)):" -ForegroundColor Yellow
        foreach ($os in $modified) {
            Write-Host "     ~ $os" -ForegroundColor Yellow
            $v1Info = $v1.os_database.$os
            $v2Info = $v2.os_database.$os
            
            if ($v1Info.eol_date -ne $v2Info.eol_date) {
                Write-Host "       EoL: $($v1Info.eol_date) → $($v2Info.eol_date)" -ForegroundColor Gray
            }
            if ($v1Info.extended_support -ne $v2Info.extended_support) {
                Write-Host "       Ext: $($v1Info.extended_support) → $($v2Info.extended_support)" -ForegroundColor Gray
            }
        }
        Write-Host ""
    }
    
    if ($added.Count -eq 0 -and $removed.Count -eq 0 -and $modified.Count -eq 0) {
        Write-Host "  ✅ Aucune différence détectée" -ForegroundColor Green
        Write-Host ""
    }
    
    # Résumé
    return [PSCustomObject]@{
        Version1 = $v1.metadata.version
        Version2 = $v2.metadata.version
        Added = $added.Count
        Removed = $removed.Count
        Modified = $modified.Count
        Total_V1 = $v1OS.Count
        Total_V2 = $v2OS.Count
    }
}

#endregion
