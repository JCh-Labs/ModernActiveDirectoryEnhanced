# Module PreCheck - Version ASCII
# Toutes les fonctions de verification pour Get-ADModernReport -PreCheck

$script:PreCheckSampleSize = 100
$script:MinDiskSpaceMB = 100
$script:EoLDatabaseMaxAgeDays = 90

function Test-RequiredModules {
    $requiredModules = @(
        @{ Name = 'ActiveDirectory'; MinVersion = $null; Critical = $true },
        @{ Name = 'PSWriteHTML'; MinVersion = [version]'0.0.180'; Critical = $true },
        @{ Name = 'PSWriteExcel'; MinVersion = [version]'0.1.15'; Critical = $false }
    )
    
    $results = @()
    $allOk = $true
    
    foreach ($module in $requiredModules) {
        $installed = Get-Module -ListAvailable -Name $module.Name | Sort-Object Version -Descending | Select-Object -First 1
        
        if ($installed) {
            $versionOk = if ($module.MinVersion) { $installed.Version -ge $module.MinVersion } else { $true }
            $status = if ($versionOk) { "OK" } else { "VERSION_OLD" }
            $message = if ($versionOk) { "Installe (v$($installed.Version))" } else { "Version $($installed.Version) < $($module.MinVersion) requise" }
            if (-not $versionOk -and $module.Critical) { $allOk = $false }
        } else {
            $status = "MISSING"
            $message = "Module non trouve"
            if ($module.Critical) { $allOk = $false }
        }
        
        $results += [PSCustomObject]@{
            Status = $status
            ModuleName = $module.Name
            Required = if ($module.MinVersion) { $module.MinVersion.ToString() } else { "N/A" }
            Installed = if ($installed) { $installed.Version.ToString() } else { "Non installe" }
            Critical = $module.Critical
            Message = $message
        }
    }
    
    return [PSCustomObject]@{ AllOk = $allOk; Modules = $results }
}

function Test-ADPermissions {
    $results = @{ Users = $false; Computers = $false; Groups = $false; OUs = $false; Domain = $false }
    $errorMessages = @()
    
    try { $null = Get-ADUser -Filter * -ResultSetSize 1 -ErrorAction Stop; $results.Users = $true } catch { $errorMessages += "Lecture Users: $($_.Exception.Message)" }
    try { $null = Get-ADComputer -Filter * -ResultSetSize 1 -ErrorAction Stop; $results.Computers = $true } catch { $errorMessages += "Lecture Computers: $($_.Exception.Message)" }
    try { $null = Get-ADGroup -Filter * -ResultSetSize 1 -ErrorAction Stop; $results.Groups = $true } catch { $errorMessages += "Lecture Groups: $($_.Exception.Message)" }
    try { $null = Get-ADOrganizationalUnit -Filter * -ResultSetSize 1 -ErrorAction Stop; $results.OUs = $true } catch { $errorMessages += "Lecture OUs: $($_.Exception.Message)" }
    try { $null = Get-ADDomain -ErrorAction Stop; $results.Domain = $true } catch { $errorMessages += "Lecture Domain: $($_.Exception.Message)" }
    
    $hasPermission = $results.Users -and $results.Computers -and $results.Groups -and $results.Domain
    $message = if ($hasPermission) { "Permissions OK" } else { "Permissions insuffisantes : $($errorMessages -join ' | ')" }
    
    return [PSCustomObject]@{ HasPermission = $hasPermission; Message = $message; Details = $results; Errors = $errorMessages }
}

function Get-ADObjectCounts {
    # P03 FIX : utiliser Measure-Object au lieu de @(...).Count
    # Evite de charger tous les objets en memoire uniquement pour les compter
    try {
        $counts = @{
            Users     = (Get-ADUser     -Filter * -ResultSetSize $null -ResultPageSize 1000 | Measure-Object).Count
            Computers = (Get-ADComputer -Filter * -ResultSetSize $null -ResultPageSize 1000 | Measure-Object).Count
            Groups    = (Get-ADGroup    -Filter * -ResultSetSize $null -ResultPageSize 1000 | Measure-Object).Count
            OUs       = (Get-ADOrganizationalUnit -Filter * -ResultSetSize $null -ResultPageSize 1000 | Measure-Object).Count
        }
        $counts.TotalObjects = $counts.Users + $counts.Computers + $counts.Groups + $counts.OUs
        return [PSCustomObject]$counts
    } catch {
        Write-Error "Erreur comptage AD: $($_.Exception.Message)"
        return $null
    }
}

function Get-OUDepthAnalysis {
    try {
        $allOUs = Get-ADOrganizationalUnit -Filter * -Properties DistinguishedName
        $maxDepth = 0
        $depthDistribution = @{}
        
        foreach ($ou in $allOUs) {
            $depth = ([regex]::Matches($ou.DistinguishedName, "OU=")).Count
            if ($depth -gt $maxDepth) { $maxDepth = $depth }
            if ($depthDistribution.ContainsKey($depth)) { $depthDistribution[$depth]++ } else { $depthDistribution[$depth] = 1 }
        }
        
        $recommendedScope = switch ($maxDepth) {
            {$_ -le 2} { "OneLevel" }
            {$_ -le 4} { "Subtree" }
            default    { "Subtree" }
        }
        
        return [PSCustomObject]@{
            MaxDepth = $maxDepth
            TotalOUs = $allOUs.Count
            RecommendedSearchScope = $recommendedScope
            DepthDistribution = $depthDistribution
            Message = "Profondeur maximale: $maxDepth niveaux"
        }
    } catch {
        Write-Error "Erreur analyse OU: $($_.Exception.Message)"
        return $null
    }
}

function Get-EstimatedExecutionTime {
    param(
        [int]$UserCount,
        [int]$ComputerCount,
        [int]$GroupCount,
        [int]$SampleSize = 100
    )
    
    $timings = @{ Users = 0; Computers = 0; Groups = 0 }
    
    # Listes exactes de proprietes utilisees dans le rapport principal
    # (identiques a $Alluserpropert / $filtercomputer / MAD-Groups.ps1)
    # P02 FIX : -Properties * charge tous les attributs AD y compris binaires
    # (thumbnailPhoto, msExchMailboxGuid...) — 5 a 10x plus lent et fausse l'estimation
    $userProps     = @('WhenCreated','DistinguishedName','ProtectedFromAccidentalDeletion',
                       'LastLogon','EmailAddress','LastLogonDate','PasswordExpired',
                       'PasswordLastSet','Description','PasswordNeverExpires',
                       'AccountExpirationDate','msDS-PSOApplied','admincount')
    $computerProps = @('OperatingSystem','OperatingSystemVersion','ProtectedFromAccidentalDeletion',
                       'lastlogondate','Created','PasswordLastSet','DistinguishedName','ipv4address')
    $groupProps    = @('Member','ManagedBy','info','created','ProtectedFromAccidentalDeletion')

    if ($UserCount -gt 0) {
        $userSample = [Math]::Min($SampleSize, $UserCount)
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $null = Get-ADUser -Filter * -ResultSetSize $userSample -Properties $userProps
        $stopwatch.Stop()
        $timings.Users = ($stopwatch.Elapsed.TotalSeconds / $userSample) * $UserCount
    }
    
    if ($ComputerCount -gt 0) {
        $computerSample = [Math]::Min($SampleSize, $ComputerCount)
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $null = Get-ADComputer -Filter * -ResultSetSize $computerSample -Properties $computerProps
        $stopwatch.Stop()
        $timings.Computers = ($stopwatch.Elapsed.TotalSeconds / $computerSample) * $ComputerCount
    }
    
    if ($GroupCount -gt 0) {
        $groupSample = [Math]::Min($SampleSize, $GroupCount)
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $null = Get-ADGroup -Filter * -ResultSetSize $groupSample -Properties $groupProps
        $stopwatch.Stop()
        $timings.Groups = ($stopwatch.Elapsed.TotalSeconds / $groupSample) * $GroupCount
    }
    
    $baseTime = $timings.Users + $timings.Computers + $timings.Groups
    $overhead = ($baseTime * 0.20) + 10
    $totalSeconds = $baseTime + $overhead
    $totalMinutes = $totalSeconds / 60
    
    return [PSCustomObject]@{
        EstimatedSeconds = [math]::Round($totalSeconds, 0)
        EstimatedMinutes = [math]::Round($totalMinutes, 1)
        Details = @{
            UsersTime = [math]::Round($timings.Users, 2)
            ComputersTime = [math]::Round($timings.Computers, 2)
            GroupsTime = [math]::Round($timings.Groups, 2)
            BaseTime = [math]::Round($baseTime, 2)
            Overhead = [math]::Round($overhead, 2)
        }
        SampleSize = $SampleSize
    }
}

function Test-DiskSpace {
    param([string]$SavePath, [int]$EstimatedSizeMB = 50)
    
    try {
        if (-not (Test-Path $SavePath)) {
            $SavePath = Split-Path $SavePath -Parent
            if (-not $SavePath) { $SavePath = $env:TEMP }
        }
        
        $drive = (Get-Item $SavePath).PSDrive
        
        if ($drive) {
            $availableGB = [math]::Round($drive.Free / 1GB, 2)
            $availableMB = [math]::Round($drive.Free / 1MB, 0)
            $hasSpace = $availableMB -gt ($EstimatedSizeMB + $script:MinDiskSpaceMB)
            $message = if ($hasSpace) { "Espace disponible: $availableGB GB" } else { "Espace insuffisant: $availableGB GB disponible, $EstimatedSizeMB MB requis" }
            
            return [PSCustomObject]@{
                HasSpace = $hasSpace
                AvailableGB = $availableGB
                AvailableMB = $availableMB
                RequiredMB = $EstimatedSizeMB
                Drive = $drive.Name
                Message = $message
            }
        } else {
            return [PSCustomObject]@{ HasSpace = $true; Message = "Impossible de verifier l'espace disque" }
        }
    } catch {
        return [PSCustomObject]@{ HasSpace = $true; Message = "Verification espace disque ignoree" }
    }
}

# Test-OSInEoLDatabase est définie dans EoL-Functions.ps1 (source canonique unique).
# Elle est dot-sourcée par ModernActiveDirectoryEnhanced.psm1 avant ce fichier.
# Pas de redéfinition ici pour éviter tout conflit de scope.
# PreCheck l'appelle directement : Test-OSInEoLDatabase -DaysBeforeWarning $x

function Test-EoLDatabaseStatus {
    try {
        $database = Get-EoLDatabase
        
        if (-not $database) {
            return [PSCustomObject]@{ 
                Status = "ERROR"
                Message = "Base de donnees EoL introuvable"
                Exists = $false
                Version = "N/A"
                LastUpdate = "N/A"
                LastAPIUpdate = "N/A"
                AgeDays = -1
                OSCount = 0
                NeedsUpdate = $false
            }
        }
        
        $hasMetadata = $null -ne $database.metadata
        $hasOSDatabase = $null -ne $database.os_database
        
        # Compter les OS de manière sûre
        $osCount = 0
        if ($hasOSDatabase) {
            try {
                $osCount = @($database.os_database.PSObject.Properties).Count
            } catch {
                $osCount = 0
            }
        }
        
        # Parser la date de manière sûre
        $lastUpdateDate = $null
        $ageDays = -1
        if ($hasMetadata -and $database.metadata.last_updated) {
            try {
                $lastUpdateDate = [DateTime]::Parse($database.metadata.last_updated)
                $ageDays = ((Get-Date) - $lastUpdateDate).Days
            } catch {
                $ageDays = -1
            }
        }
        
        # Déterminer le statut
        if (-not $hasMetadata -or -not $hasOSDatabase) {
            $status = "ERROR"
        } elseif ($osCount -eq 0) {
            $status = "ERROR"
        } elseif ($ageDays -gt $script:EoLDatabaseMaxAgeDays) {
            $status = "WARNING"
        } else {
            $status = "OK"
        }
        
        # Message clair
        $message = switch ($status) {
            "OK" { "Base EoL OK ($osCount OS, mise a jour il y a $ageDays jours)" }
            "WARNING" { "Base EoL ancienne ($ageDays jours), mise a jour recommandee" }
            "ERROR" { "Base EoL invalide ou vide" }
        }
        
        # Récupérer les valeurs de manière sûre
        $version = if ($hasMetadata -and $database.metadata.version) { [string]$database.metadata.version } else { "N/A" }
        $lastUpdate = if ($hasMetadata -and $database.metadata.last_updated) { [string]$database.metadata.last_updated } else { "N/A" }
        $lastAPIUpdate = if ($hasMetadata -and $database.metadata.last_api_update) { [string]$database.metadata.last_api_update } else { "N/A" }
        
        return [PSCustomObject]@{
            Status = [string]$status
            Message = [string]$message
            Exists = [bool]$true
            Version = [string]$version
            LastUpdate = [string]$lastUpdate
            LastAPIUpdate = [string]$lastAPIUpdate
            AgeDays = [int]$ageDays
            OSCount = [int]$osCount
            NeedsUpdate = [bool]($ageDays -gt $script:EoLDatabaseMaxAgeDays)
        }
    } catch {
        return [PSCustomObject]@{
            Status = "ERROR"
            Message = "Erreur lors de la verification: $($_.Exception.Message)"
            Exists = $false
            Version = "N/A"
            LastUpdate = "N/A"
            LastAPIUpdate = "N/A"
            AgeDays = -1
            OSCount = 0
            NeedsUpdate = $false
        }
    }
}

function Test-RSATFeatures {
<#
.SYNOPSIS
    Verifie la presence des fonctionnalites RSAT requises par le module MADE.

.DESCRIPTION
    Controle l'installation des RSAT (Remote Server Administration Tools) necessaires :
      - RSAT-AD-Tools      : outils Active Directory (Get-ADUser, Get-ADComputer, etc.)
      - RSAT-GPMC          : console de gestion des GPO (Get-GPO, etc.)
      - RSAT-DNS-Server    : optionnel, utile sur certains environnements

    Distingue trois contextes :
      - Windows Server     : verifie via Get-WindowsFeature (roles/features)
      - Windows 10/11      : verifie via Get-WindowsCapability (RSAT a la demande)
      - Autre / non-admin  : fallback sur la detection des cmdlets AD disponibles

    IMPORTANT : la detection RSAT n'est possible qu'avec des droits administrateur local.
    Sans ces droits, la fonction bascule sur le fallback cmdlet et indique clairement
    que la verification complete n'a pas pu etre effectuee.
#>
    [CmdletBinding()]
    param()

    $results   = @()
    $allOk     = $true
    $isAdmin   = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
                     [Security.Principal.WindowsBuiltInRole]::Administrator)
    $osInfo    = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
    $isServer  = $osInfo -and $osInfo.ProductType -ne 1   # ProductType 1 = Workstation

    # Definition des features a verifier selon le contexte
    # Critical = $true : bloquant pour le rapport
    $featureDefs = @(
        @{
            Name           = 'RSAT-AD-Tools'
            CapabilityName = 'Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0'
            FriendlyName   = 'RSAT : Outils Active Directory'
            CmdletProbe    = 'Get-ADUser'
            Critical       = $true
            InstallServer  = 'Install-WindowsFeature RSAT-AD-Tools'
            InstallClient  = 'Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0'
            InstallAlt     = 'Parametres > Applications > Fonctionnalites facultatives > Ajouter > RSAT : services de domaine Active Directory et LDAP'
        },
        @{
            Name           = 'GPMC'
            CapabilityName = 'Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0'
            FriendlyName   = 'RSAT : Console de gestion des GPO (GPMC)'
            CmdletProbe    = 'Get-GPO'
            Critical       = $false
            InstallServer  = 'Install-WindowsFeature GPMC'
            InstallClient  = 'Add-WindowsCapability -Online -Name Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0'
            InstallAlt     = 'Parametres > Applications > Fonctionnalites facultatives > Ajouter > RSAT : Gestion des stratégies de groupe'
        }
    )

    foreach ($feat in $featureDefs) {

        $status      = 'UNKNOWN'
        $installed   = $false
        $message     = ''
        $installCmd  = ''

        if ($isAdmin) {

            if ($isServer) {
                # ── Windows Server : Get-WindowsFeature ──────────────────────
                try {
                    $wf = Get-WindowsFeature -Name $feat.Name -ErrorAction Stop
                    if ($wf.InstallState -eq 'Installed') {
                        $installed = $true
                        $status    = 'OK'
                        $message   = "Installe (Windows Feature)"
                    } else {
                        $status    = 'MISSING'
                        $message   = "Non installe (etat: $($wf.InstallState))"
                        $installCmd = $feat.InstallServer
                        if ($feat.Critical) { $allOk = $false }
                    }
                } catch {
                    # Get-WindowsFeature non disponible malgre IsServer — fallback cmdlet
                    $status  = 'UNKNOWN'
                    $message = "Verification impossible via Get-WindowsFeature : $($_.Exception.Message)"
                }

            } else {
                # ── Windows 10/11 : Get-WindowsCapability ────────────────────
                try {
                    $cap = Get-WindowsCapability -Online -Name $feat.CapabilityName -ErrorAction Stop
                    if ($cap.State -eq 'Installed') {
                        $installed = $true
                        $status    = 'OK'
                        $message   = "Installe (Windows Capability)"
                    } else {
                        $status     = 'MISSING'
                        $message    = "Non installe (etat: $($cap.State))"
                        $installCmd = $feat.InstallClient
                        if ($feat.Critical) { $allOk = $false }
                    }
                } catch {
                    $status  = 'UNKNOWN'
                    $message = "Verification impossible via Get-WindowsCapability : $($_.Exception.Message)"
                }
            }

        }

        # ── Fallback : detection par la presence du cmdlet ───────────────────
        # Utilise systematiquement si non-admin, ou si la detection RSAT a echoue
        if (-not $isAdmin -or $status -eq 'UNKNOWN') {
            $cmdAvailable = [bool](Get-Command -Name $feat.CmdletProbe -ErrorAction SilentlyContinue)
            if ($cmdAvailable) {
                $installed = $true
                $status    = 'OK'
                $message   = if (-not $isAdmin) {
                    "Cmdlet '$($feat.CmdletProbe)' disponible (verification RSAT incomplete — droits admin requis)"
                } else {
                    "Cmdlet '$($feat.CmdletProbe)' disponible"
                }
            } else {
                $status  = 'MISSING'
                $message = "Cmdlet '$($feat.CmdletProbe)' introuvable — RSAT probablement absent"
                $installCmd = if ($isServer) { $feat.InstallServer } else { $feat.InstallClient }
                if ($feat.Critical) { $allOk = $false }
            }
        }

        $results += [PSCustomObject]@{
            FeatureName  = $feat.Name
            FriendlyName = $feat.FriendlyName
            Status       = $status
            Installed    = $installed
            Critical     = $feat.Critical
            Message      = $message
            InstallCmd   = $installCmd
            InstallAlt   = $feat.InstallAlt
            IsServer     = $isServer
            IsAdmin      = $isAdmin
        }
    }

    return [PSCustomObject]@{
        AllOk    = $allOk
        IsAdmin  = $isAdmin
        IsServer = $isServer
        Features = $results
    }
}

function Test-PowerShellVersion {
    $version = $PSVersionTable.PSVersion
    $isCompatible = ($version.Major -gt 5) -or ($version.Major -eq 5 -and $version.Minor -ge 1)
    $message = if ($isCompatible) { "PowerShell $version OK" } else { "PowerShell $version non supporte (requis >= 5.1)" }
    
    return [PSCustomObject]@{ IsCompatible = $isCompatible; Version = $version.ToString(); Message = $message }
}

function Get-PreCheckRecommendations {
    param($ObjectCounts, $OUDepth, $OSCheck, $EoLStatus)

    $recommendations = @()

    # ── Seuils calcules depuis les objets detectes (meme logique que l'affichage)
    if ($ObjectCounts) {
        $rawObj    = $ObjectCounts.Users + $ObjectCounts.Computers
        $ceilObj   = [math]::Max(100, [math]::Ceiling($rawObj   / 100) * 100)
        $ceilGrp   = [math]::Max(100, [math]::Ceiling($ObjectCounts.Groups / 100) * 100)

        # Signaler si les ordinateurs depassent la valeur par defaut du parametre
        $defaultLimit = 300
        if ($ObjectCounts.Computers -gt $defaultLimit) {
            $ignored = $ObjectCounts.Computers - $defaultLimit
            $recommendations += [PSCustomObject]@{
                Type     = "OPTIMIZATION"
                Priority = "High"
                Message  = "$ignored ordinateur(s) ignores avec les seuils par defaut ($defaultLimit)"
                Action   = "Utiliser -MaxSearchObjects $ceilObj -MaxSearchGroups $ceilGrp"
            }
        }
        if ($ObjectCounts.Groups -gt $defaultLimit) {
            $ignoredG = $ObjectCounts.Groups - $defaultLimit
            $recommendations += [PSCustomObject]@{
                Type     = "OPTIMIZATION"
                Priority = "High"
                Message  = "$ignoredG groupe(s) ignores avec les seuils par defaut ($defaultLimit)"
                Action   = "Utiliser -MaxSearchGroups $ceilGrp"
            }
        }
    }

    # ── Scope OU
    if ($OUDepth) {
        $recommendations += [PSCustomObject]@{
            Type     = "OPTIMIZATION"
            Priority = "Medium"
            Message  = "Profondeur OU: $($OUDepth.MaxDepth) niveaux"
            Action   = "Utiliser -OUSearchScope '$($OUDepth.RecommendedSearchScope)'"
        }
    }

    # ── Base EoL
    if ($EoLStatus.NeedsUpdate) {
        $recommendations += [PSCustomObject]@{
            Type     = "WARNING"
            Priority = "High"
            Message  = "Base EoL ancienne ($($EoLStatus.AgeDays) jours)"
            Action   = "Executer: Update-ADEoLDatabase avant le rapport"
        }
    }

    # ── OS manquants
    if ($OSCheck.MissingOS.Count -gt 0) {
        $totalMissingComputers = ($OSCheck.MissingOS | Measure-Object -Property Count -Sum).Sum
        $recommendations += [PSCustomObject]@{
            Type     = "WARNING"
            Priority = "High"
            Message  = "$($OSCheck.MissingOS.Count) OS manquants affectant $totalMissingComputers machines"
            Action   = "Executer: Update-EoL pour ajouter automatiquement les OS manquants"
        }
    }

    return $recommendations
}

function Invoke-ADReportPreCheck {
    param([string]$SavePath = $env:TEMP, [switch]$ShowDetails)

    $overallStatus = $true
    $warnings      = @()
    $errors        = @()
    $timeEstimate  = $null
    $recommendations = @()
    $script:eolMissing = $false   # base EoL absente (etat initial attendu)

    # Fonctions d'affichage locales (style identique au rapport)
    function _PCStatus {
        param([string]$Symbol, [string]$Label, [string]$Value, [string]$Color)
        Write-Host "  $Symbol " -ForegroundColor $Color -NoNewline
        Write-Host $Label.PadRight(28) -ForegroundColor Gray -NoNewline
        Write-Host ": " -ForegroundColor DarkGray -NoNewline
        Write-Host $Value -ForegroundColor $Color
    }
    function _PCDetail {
        param([string]$Text, [string]$Color = "DarkGray")
        Write-Host "      ▪ $Text" -ForegroundColor $Color
    }

    Write-Host ""
    Write-Host "  #=======================================================================" -ForegroundColor DarkCyan
    Write-Host "  #  PRE-CHECK : Active Directory Report" -ForegroundColor Cyan
    Write-Host "  #=======================================================================" -ForegroundColor DarkCyan
    Write-Host "  Verification de l'environnement avant generation du rapport..." -ForegroundColor Gray
    Write-Host ""

    # ── 1. ENVIRONNEMENT ────────────────────────────────────────────────────────
    Write-Host "  💻 ENVIRONNEMENT" -ForegroundColor White
    Write-Host "  ─────────────────────────────────────────────────────────────" -ForegroundColor DarkGray

    $psCheck = Test-PowerShellVersion
    if ($psCheck.IsCompatible) {
        _PCStatus "✓" "PowerShell" $psCheck.Version "Green"
    } else {
        $overallStatus = $false; $errors += $psCheck.Message
        _PCStatus "✗" "PowerShell" "$($psCheck.Version)  ← requis >= 5.1" "Red"
    }

    $moduleCheck = Test-RequiredModules
    foreach ($module in $moduleCheck.Modules) {
        switch ($module.Status) {
            "OK"          { _PCStatus "✓" $module.ModuleName "v$($module.Installed)" "Green" }
            "VERSION_OLD" { $warnings += $module.Message; _PCStatus "⚠" $module.ModuleName "v$($module.Installed)  ← mise a jour recommandee" "Yellow" }
            "MISSING"     {
                if ($module.Critical) { $overallStatus = $false; $errors += $module.Message }
                _PCStatus "✗" $module.ModuleName "Non installe" "Red"
            }
        }
    }

    # ── RSAT Features ──────────────────────────────────────────────────────────
    $rsatCheck = Test-RSATFeatures
    if (-not $rsatCheck.IsAdmin) {
        _PCStatus "⚠" "RSAT (verification)" "Droits admin requis pour controle complet — fallback cmdlet" "Yellow"
        $warnings += "Verification RSAT incomplete : relancer en tant qu'administrateur local pour un controle exhaustif"
    }
    foreach ($feat in $rsatCheck.Features) {
        switch ($feat.Status) {
            "OK" {
                _PCStatus "✓" $feat.FriendlyName $feat.Message "Green"
            }
            "MISSING" {
                if ($feat.Critical) {
                    $overallStatus = $false
                    $errors += "$($feat.FriendlyName) absent — rapport impossible"
                    _PCStatus "✗" $feat.FriendlyName "Non installe  [CRITIQUE]" "Red"
                } else {
                    $warnings += "$($feat.FriendlyName) absent — section GPO désactivée"
                    _PCStatus "⚠" $feat.FriendlyName "Non installe  (GPO désactivé)" "Yellow"
                }
                if ($feat.InstallCmd) {
                    _PCDetail "Commande d'installation : $($feat.InstallCmd)" "DarkYellow"
                }
                if ($feat.InstallAlt -and $ShowDetails) {
                    _PCDetail "Alternative IHM : $($feat.InstallAlt)" "DarkGray"
                }
            }
            "UNKNOWN" {
                $warnings += "Statut RSAT inconnu pour '$($feat.FriendlyName)'"
                _PCStatus "?" $feat.FriendlyName "Statut inconnu" "DarkGray"
            }
        }
    }

    Write-Host ""

    # ── 2. PERMISSIONS & DISQUE ────────────────────────────────────────────────
    Write-Host "  🔑 PERMISSIONS & RESSOURCES" -ForegroundColor White
    Write-Host "  ─────────────────────────────────────────────────────────────" -ForegroundColor DarkGray

    $permCheck = Test-ADPermissions
    if ($permCheck.HasPermission) {
        _PCStatus "✓" "Lecture Active Directory" "OK" "Green"
    } else {
        $overallStatus = $false; $errors += $permCheck.Message
        _PCStatus "✗" "Lecture Active Directory" "ERREUR" "Red"
        if ($ShowDetails) { foreach ($e in $permCheck.Errors) { _PCDetail $e "Red" } }
    }

    $diskCheck = Test-DiskSpace -SavePath $SavePath
    if ($diskCheck.HasSpace) {
        _PCStatus "✓" "Espace disque" $diskCheck.Message "Green"
    } else {
        $warnings += $diskCheck.Message
        _PCStatus "⚠" "Espace disque" $diskCheck.Message "Yellow"
    }

    # ── ARRET IMMEDIAT si erreurs critiques (env ou permissions) ───────────────
    if ($errors.Count -gt 0) {
        Write-Host ""
        Write-Host "  #=======================================================================" -ForegroundColor DarkCyan
        Write-Host ""
        Write-Host "  ✗ ARRET — conditions requises non satisfaites" -ForegroundColor Red
        foreach ($e in $errors) { Write-Host "      ▪ $e" -ForegroundColor Red }
        Write-Host ""
        Write-Host "  Corrigez les erreurs ci-dessus avant de relancer le PreCheck." -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  #=======================================================================" -ForegroundColor DarkCyan
        Write-Host ""
        return [PSCustomObject]@{
            OverallStatus        = $false
            CanProceed           = $false
            Warnings             = $warnings
            Errors               = $errors
            PowerShell           = $psCheck
            Modules              = $moduleCheck
            Permissions          = $permCheck
            DiskSpace            = $diskCheck
            ObjectCounts         = $null
            OUDepth              = $null
            TimeEstimate         = $null
            EoLStatus            = $null
            OSCheck              = $null
            Recommendations      = @()
            ComputedSearchParams = ""
            ComputedScopeParam   = ""
            Timestamp            = Get-Date
        }
    }

    Write-Host ""

    # ── 3. INVENTAIRE AD ───────────────────────────────────────────────────────
    Write-Host "  📋 INVENTAIRE ACTIVE DIRECTORY" -ForegroundColor White
    Write-Host "  ─────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "  ⏳ Analyse en cours..." -ForegroundColor Gray

    $objectCounts = Get-ADObjectCounts

    if ($objectCounts) {
        Write-Host "  `r" -NoNewline
        Write-Host "    ▪ " -ForegroundColor DarkGray -NoNewline
        Write-Host "Utilisateurs".PadRight(30) -ForegroundColor Gray -NoNewline
        Write-Host $objectCounts.Users.ToString('N0').PadLeft(8) -ForegroundColor White
        Write-Host "    ▪ " -ForegroundColor DarkGray -NoNewline
        Write-Host "Ordinateurs".PadRight(30) -ForegroundColor Gray -NoNewline
        Write-Host $objectCounts.Computers.ToString('N0').PadLeft(8) -ForegroundColor White
        Write-Host "    ▪ " -ForegroundColor DarkGray -NoNewline
        Write-Host "Groupes".PadRight(30) -ForegroundColor Gray -NoNewline
        Write-Host $objectCounts.Groups.ToString('N0').PadLeft(8) -ForegroundColor White
        Write-Host "    ▪ " -ForegroundColor DarkGray -NoNewline
        Write-Host "Unites d'organisation".PadRight(30) -ForegroundColor Gray -NoNewline
        Write-Host $objectCounts.OUs.ToString('N0').PadLeft(8) -ForegroundColor White
        Write-Host "    ▪ " -ForegroundColor DarkGray -NoNewline
        Write-Host "TOTAL".PadRight(30) -ForegroundColor Gray -NoNewline
        Write-Host $objectCounts.TotalObjects.ToString('N0').PadLeft(8) -ForegroundColor Cyan
    } else {
        Write-Host "  ✗ Erreur lors du comptage AD" -ForegroundColor Red
        $overallStatus = $false
    }

    Write-Host ""

    # ── 4. STRUCTURE OU ────────────────────────────────────────────────────────
    Write-Host "  🏗  STRUCTURE ORGANISATIONNELLE" -ForegroundColor White
    Write-Host "  ─────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "  ⏳ Analyse en cours..." -ForegroundColor Gray

    $ouDepth = Get-OUDepthAnalysis
    Write-Host "  `r" -NoNewline

    if ($ouDepth) {
        _PCStatus "  " "Profondeur max" "$($ouDepth.MaxDepth) niveaux" "White"
        _PCStatus "  " "Scope recommande" $ouDepth.RecommendedSearchScope "Cyan"
    }

    Write-Host ""

    # ── 5. TEMPS D'EXECUTION ──────────────────────────────────────────────────
    Write-Host "  ⏱  TEMPS D'EXECUTION ESTIME" -ForegroundColor White
    Write-Host "  ─────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "  ⏳ Echantillonnage en cours..." -ForegroundColor Gray

    if ($objectCounts) {
        $timeEstimate = Get-EstimatedExecutionTime -UserCount $objectCounts.Users -ComputerCount $objectCounts.Computers -GroupCount $objectCounts.Groups -SampleSize $script:PreCheckSampleSize
        Write-Host "  `r" -NoNewline

        $durStr = if ($timeEstimate.EstimatedMinutes -lt 1) {
            "~$($timeEstimate.EstimatedSeconds) secondes"
        } elseif ($timeEstimate.EstimatedMinutes -lt 60) {
            "~$($timeEstimate.EstimatedMinutes) minutes"
        } else {
            "~$([math]::Round($timeEstimate.EstimatedMinutes/60,1)) heures"
        }
        _PCStatus "  " "Duree estimee" $durStr "Cyan"

        if ($ShowDetails) {
            _PCDetail "Users: $($timeEstimate.Details.UsersTime)s  |  Computers: $($timeEstimate.Details.ComputersTime)s  |  Groups: $($timeEstimate.Details.GroupsTime)s"
            _PCDetail "Echantillon: $($timeEstimate.SampleSize) objets"
        }
    }

    Write-Host ""

    # ── 6. BASE EoL ─────────────────────────────────────────────────────────────
    Write-Host "  🗄  BASE DE DONNEES End-of-Life" -ForegroundColor White
    Write-Host "  ─────────────────────────────────────────────────────────────" -ForegroundColor DarkGray

    $eolStatus = Test-EoLDatabaseStatus
    switch ($eolStatus.Status) {
        "OK"      { _PCStatus "✓" "Etat base EoL" "$($eolStatus.Message)" "Green" }
        "WARNING" { $warnings += $eolStatus.Message; _PCStatus "⚠" "Etat base EoL" "$($eolStatus.Message)" "Yellow" }
        "ERROR"   {
            # Base EoL absente = etat initial normal, pas une erreur bloquante
            $script:eolMissing = $true
            $warnings += $eolStatus.Message
            _PCStatus "⚠" "Etat base EoL" "Base absente  → executer Update-ADEoLDatabase" "Yellow"
        }
    }

    if ($eolStatus.Exists) {
        _PCDetail "Version: $($eolStatus.Version)   Derniere MAJ: $($eolStatus.LastUpdate)   OS: $($eolStatus.OSCount)"
    }

    Write-Host ""

    # ── Si la base EoL est absente : court-circuiter toutes les sections suivantes ──
    # Inutile d'analyser les OS, les seuils ou de générer des recommandations AD
    # quand l'action unique requise est de créer la base. On affiche directement
    # la synthèse avec la commande à exécuter et on retourne.
    if ($script:eolMissing) {
        Write-Host "  #=======================================================================" -ForegroundColor DarkCyan
        Write-Host ""
        Write-Host "  ⚠  BASE EoL ABSENTE — Initialisation requise avant toute autre action" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  ─────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
        Write-Host "  📌 ACTION UNIQUE REQUISE" -ForegroundColor Cyan
        Write-Host "  ─────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  ❶  Creer et initialiser la base End-of-Life (connexion internet requise) :" -ForegroundColor White
        Write-Host ""
        Write-Host "       Update-ADEoLDatabase" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  ❷  Relancer le PreCheck pour valider l'environnement complet :" -ForegroundColor White
        Write-Host ""
        Write-Host "       Get-MADReport -PreCheck" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  #=======================================================================" -ForegroundColor DarkCyan
        Write-Host ""

        return [PSCustomObject]@{
            OverallStatus        = "PENDING"
            CanProceed           = $false
            Warnings             = @("Base de donnees EoL introuvable")
            Errors               = @()
            PowerShell           = $psCheck
            Modules              = $moduleCheck
            RSAT                 = $rsatCheck
            Permissions          = $permCheck
            DiskSpace            = $diskCheck
            ObjectCounts         = $objectCounts
            OUDepth              = $ouDepth
            TimeEstimate         = $timeEstimate
            EoLStatus            = $eolStatus
            OSCheck              = $null
            Recommendations      = @()
            ComputedSearchParams = ""
            ComputedScopeParam   = ""
            Timestamp            = Get-Date
        }
    }

    # ── 7. SYSTEMES D'EXPLOITATION ─────────────────────────────────────────────
    Write-Host "  🖥  SYSTEMES D'EXPLOITATION" -ForegroundColor White
    Write-Host "  ─────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "  ⏳ Analyse de la couverture EoL..." -ForegroundColor Gray

    $eolWarningDays = if ($null -ne (Get-Variable -Name DaysBeforeEoL -Scope Global -ErrorAction SilentlyContinue)) { $global:DaysBeforeEoL } else { 90 }
    $osCheck = Test-OSInEoLDatabase -DaysBeforeWarning $eolWarningDays
    Write-Host "  `r" -NoNewline

    if ($osCheck.Status -eq "OK") {
        _PCStatus "✓" "Couverture EoL" "$($osCheck.CoveragePercent)%  ($($osCheck.TotalOSDetected) OS detectes)" "Green"
    } elseif ($osCheck.Status -eq "WARNING") {
        $warnings += $osCheck.Message
        _PCStatus "⚠" "Couverture EoL" "$($osCheck.CoveragePercent)%  —  $($osCheck.MissingOS.Count) OS absent(s) de la base" "Yellow"
        Write-Host ""
        Write-Host "    OS non references dans eol-database.json :" -ForegroundColor Yellow
        foreach ($missing in $osCheck.MissingOS | Sort-Object Count -Descending | Select-Object -First 10) {
            Write-Host "      ▪ " -ForegroundColor DarkGray -NoNewline
            Write-Host "$($missing.OS)".PadRight(42) -ForegroundColor Gray -NoNewline
            Write-Host "$($missing.Count) machine(s)" -ForegroundColor DarkYellow
        }
        if ($osCheck.MissingOS.Count -gt 10) {
            Write-Host "      ▪ ... et $($osCheck.MissingOS.Count - 10) autres" -ForegroundColor DarkGray
        }
        try {
            $missingOSFile = Join-Path $env:TEMP "ModernAD-MissingOS.json"
            $osCheck.MissingOS | ConvertTo-Json -Depth 5 | Set-Content -Path $missingOSFile -Encoding UTF8 -ErrorAction Stop
            Write-Host ""
            Write-Host "  ✓ Liste sauvegardee pour Update-ADEoLDatabase" -ForegroundColor DarkGreen -NoNewline
            Write-Host "  ($missingOSFile)" -ForegroundColor DarkGray
        } catch {
            Write-Host "  ⚠ Impossible de sauvegarder la liste" -ForegroundColor Yellow
        }
    } else {
        $errors += $osCheck.Message
        _PCStatus "✗" "Couverture EoL" $osCheck.Message "Red"
    }

    Write-Host ""

    # ── 8. CALCUL DES SEUILS — 100% base sur les objets detectes ──────────────
    # Aucune valeur en dur. On arrondit chaque comptage a la centaine superieure.
    # $defaultSearchLimit = valeur par defaut du parametre dans le module (pour
    # signaler visuellement ce qui serait ignore sans ajustement).
    $defaultSearchLimit = 300
    $maxObjVal   = 0
    $maxGrpVal   = 0
    $maxObjParam = ""
    $maxGrpParam = ""
    $scopeParam  = ""

    if ($objectCounts) {
        $rawObj    = $objectCounts.Users + $objectCounts.Computers
        $maxObjVal = [math]::Max(100, [math]::Ceiling($rawObj / 100) * 100)
        $maxGrpVal = [math]::Max(100, [math]::Ceiling($objectCounts.Groups / 100) * 100)
        $maxObjParam = "-MaxSearchObjects $maxObjVal"
        $maxGrpParam = "-MaxSearchGroups $maxGrpVal"
    }

    if ($ouDepth -and $ouDepth.RecommendedSearchScope -ne $null) {
        $scope = ($ouDepth.RecommendedSearchScope -split ' ')[0]
        if ($scope -in @("Subtree","OneLevel")) { $scopeParam = "-OUSearchScope $scope" }
    }

    $searchParams = "$maxObjParam $maxGrpParam".Trim()

    # ── 8b. VERIFICATION DES SEUILS ─────────────────────────────────────────────
    Write-Host "  🔍 VERIFICATION DES SEUILS DE RECHERCHE" -ForegroundColor White
    Write-Host "  ─────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""

    if ($objectCounts) {
        # Utilisateurs
        $symU = if ($objectCounts.Users -le $defaultSearchLimit) { "✓" } else { "⚠" }
        $colU = if ($objectCounts.Users -le $defaultSearchLimit) { "Green" } else { "Yellow" }
        Write-Host "  $symU " -ForegroundColor $colU -NoNewline
        Write-Host "Utilisateurs".PadRight(16) -ForegroundColor Gray -NoNewline
        Write-Host "detectes : $("$($objectCounts.Users)".PadLeft(6))" -ForegroundColor Gray -NoNewline
        Write-Host "   → $maxObjParam" -ForegroundColor Cyan

        # Ordinateurs
        $symC = if ($objectCounts.Computers -le $defaultSearchLimit) { "✓" } else { "⚠" }
        $colC = if ($objectCounts.Computers -le $defaultSearchLimit) { "Green" } else { "Yellow" }
        Write-Host "  $symC " -ForegroundColor $colC -NoNewline
        Write-Host "Ordinateurs".PadRight(16) -ForegroundColor Gray -NoNewline
        Write-Host "detectes : $("$($objectCounts.Computers)".PadLeft(6))" -ForegroundColor Gray -NoNewline
        Write-Host "   → $maxObjParam" -ForegroundColor Cyan
        if ($objectCounts.Computers -gt $defaultSearchLimit) {
            $ignored = $objectCounts.Computers - $defaultSearchLimit
            Write-Host "      ▪ " -ForegroundColor DarkGray -NoNewline
            Write-Host "$ignored ordinateur(s) ignores avec la valeur par defaut ($defaultSearchLimit)" -ForegroundColor DarkYellow
        }

        # Groupes
        $symG = if ($objectCounts.Groups -le $defaultSearchLimit) { "✓" } else { "⚠" }
        $colG = if ($objectCounts.Groups -le $defaultSearchLimit) { "Green" } else { "Yellow" }
        Write-Host "  $symG " -ForegroundColor $colG -NoNewline
        Write-Host "Groupes".PadRight(16) -ForegroundColor Gray -NoNewline
        Write-Host "detectes : $("$($objectCounts.Groups)".PadLeft(6))" -ForegroundColor Gray -NoNewline
        Write-Host "   → $maxGrpParam" -ForegroundColor Cyan
    } else {
        Write-Host "  ⚠ Comptage AD non disponible — seuils non calculables" -ForegroundColor Yellow
    }

    if ($scopeParam -ne "") {
        Write-Host "  → " -ForegroundColor Cyan -NoNewline
        Write-Host "Scope OU detecte".PadRight(16) -ForegroundColor Gray -NoNewline
        Write-Host "                       → $scopeParam" -ForegroundColor Cyan
    }

    Write-Host ""

    # ── 9. RECOMMANDATIONS ──────────────────────────────────────────────────────
    if ($objectCounts -and $ouDepth -and $osCheck -and $eolStatus) {
        $recommendations = Get-PreCheckRecommendations -ObjectCounts $objectCounts -OUDepth $ouDepth -OSCheck $osCheck -EoLStatus $eolStatus
    }

    if ($recommendations.Count -gt 0) {
        Write-Host "  💡 RECOMMANDATIONS" -ForegroundColor White
        Write-Host "  ─────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
        foreach ($rec in $recommendations | Sort-Object { switch ($_.Priority) { "High" { 1 }; "Medium" { 2 }; "Low" { 3 } } }) {
            $sym   = switch ($rec.Type) { "WARNING" { "⚠" }; "PERFORMANCE" { "⚡" }; default { "→" } }
            $col   = switch ($rec.Priority) { "High" { "Yellow" }; "Medium" { "Cyan" }; default { "DarkCyan" } }
            Write-Host "  $sym " -ForegroundColor $col -NoNewline
            Write-Host $rec.Message -ForegroundColor White
            Write-Host "      " -NoNewline
            Write-Host $rec.Action -ForegroundColor DarkGray
        }
        Write-Host ""
    }

    # ── SYNTHESE & COMMANDES SUGGEREES ─────────────────────────────────────────
    Write-Host "  #=======================================================================" -ForegroundColor DarkCyan

    if ($errors.Count -gt 0) {
        Write-Host ""
        Write-Host "  ✗ ERREURS CRITIQUES — le rapport ne peut pas etre genere" -ForegroundColor Red
        foreach ($e in $errors) { Write-Host "      ▪ $e" -ForegroundColor Red }
        Write-Host ""

    } elseif ($osCheck -and $osCheck.MissingOS.Count -gt 0) {
        # ── Cas : OS manquants → mettre à jour la base avant de lancer
        Write-Host ""
        Write-Host "  ⚠ $($warnings.Count) avertissement(s) — OS manquants dans la base EoL" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  ─────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
        Write-Host "  📌 ACTION REQUISE — Mettre a jour la base avant le rapport" -ForegroundColor Cyan
        Write-Host "  ─────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  ❶  Synchroniser la base EoL (recupere les $($osCheck.MissingOS.Count) OS manquants) :" -ForegroundColor White
        Write-Host ""
        Write-Host "       Update-ADEoLDatabase" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  ❷  Puis generer le rapport :" -ForegroundColor White
        Write-Host ""
        Write-Host "       Get-MADReport $searchParams$(if ($scopeParam) { ' ' + $scopeParam }) -LimitedView:`$false -SavePath 'C:\Reports'" -ForegroundColor Cyan
        Write-Host ""

    } else {
        # ── Cas : tout est OK → commandes optimales
        Write-Host ""
        Write-Host "  ✓ Tous les controles sont passes — environnement pret" -ForegroundColor Green
        Write-Host ""

        # Commandes finales
        $cmdSensitive  = "Get-MADReport $searchParams$(if ($scopeParam) { ' ' + $scopeParam }) -LimitedView:`$false -ShowSensitiveObjects -SavePath 'C:\Reports'"
        $cmdStandard   = "Get-MADReport $searchParams$(if ($scopeParam) { ' ' + $scopeParam }) -LimitedView:`$false -SavePath 'C:\Reports'"
        $cmdSingleSens = "Get-MADReport $searchParams$(if ($scopeParam) { ' ' + $scopeParam }) -LimitedView:`$false -ShowSensitiveObjects -SinglePageReport -SavePath 'C:\Reports'"
        $cmdSingleStd  = "Get-MADReport $searchParams$(if ($scopeParam) { ' ' + $scopeParam }) -LimitedView:`$false -SinglePageReport -SavePath 'C:\Reports'"

        Write-Host "  ─────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
        Write-Host "  📌 COMMANDES RECOMMANDEES" -ForegroundColor Cyan
        Write-Host "  ─────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
        Write-Host ""

        # ── Rapport multi-pages ────────────────────────────────────────────────
        Write-Host "  ── Rapport multi-pages (recommande) ─────────────────────────" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  ❶  Recherche la plus complete — AVEC objets sensibles (DC, admins, GPO-DC) :" -ForegroundColor White
        Write-Host ""
        Write-Host "       $cmdSensitive" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  ❷  Recherche la plus complete — SANS objets sensibles :" -ForegroundColor White
        Write-Host ""
        Write-Host "       $cmdStandard" -ForegroundColor Cyan
        Write-Host ""

        # ── Page unique ────────────────────────────────────────────────────────
        Write-Host "  ── Rapport page unique (ideal pour partage) ──────────────────" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  ❸  Page unique — AVEC objets sensibles :" -ForegroundColor White
        Write-Host ""
        Write-Host "       $cmdSingleSens" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  ❹  Page unique — SANS objets sensibles :" -ForegroundColor White
        Write-Host ""
        Write-Host "       $cmdSingleStd" -ForegroundColor Cyan
        Write-Host ""
    }

    Write-Host "  #=======================================================================" -ForegroundColor DarkCyan
    Write-Host ""

    # ── ZONE DE PRECISION — recap des parametres calcules ──────────────────────
    Write-Host "  📐 PARAMETRES CALCULES (recap)" -ForegroundColor DarkGray
    Write-Host "  ─────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    if ($objectCounts) {
        Write-Host "    " -NoNewline
        Write-Host "Utilisateurs+Ordi".PadRight(22) -ForegroundColor DarkGray -NoNewline
        Write-Host "$($objectCounts.Users + $objectCounts.Computers) detectes   → $maxObjParam" -ForegroundColor Gray
        Write-Host "    " -NoNewline
        Write-Host "Groupes".PadRight(22) -ForegroundColor DarkGray -NoNewline
        Write-Host "$($objectCounts.Groups) detectes   → $maxGrpParam" -ForegroundColor Gray
    }
    if ($scopeParam -ne "") {
        Write-Host "    " -NoNewline
        Write-Host "Scope OU".PadRight(22) -ForegroundColor DarkGray -NoNewline
        Write-Host $scopeParam -ForegroundColor Gray
    }
    Write-Host ""

    return [PSCustomObject]@{
        OverallStatus        = $overallStatus
        CanProceed           = ($errors.Count -eq 0)
        Warnings             = $warnings
        Errors               = $errors
        PowerShell           = $psCheck
        Modules              = $moduleCheck
        RSAT                 = $rsatCheck
        Permissions          = $permCheck
        DiskSpace            = $diskCheck
        ObjectCounts         = $objectCounts
        OUDepth              = $ouDepth
        TimeEstimate         = $timeEstimate
        EoLStatus            = $eolStatus
        OSCheck              = $osCheck
        Recommendations      = $recommendations
        ComputedSearchParams = $searchParams
        ComputedScopeParam   = $scopeParam
        Timestamp            = Get-Date
    }
}

# POINT9 FIX : Export-ModuleMember n'a d'effet que dans un vrai contexte Import-Module.
# Ce fichier est dot-source (. .\PreCheck-Functions.ps1) dans le psm1 — l'appel
# etait sans effet et generait une confusion. Ligne supprimee.