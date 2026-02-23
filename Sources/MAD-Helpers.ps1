<#
.SYNOPSIS
    MAD-Helpers.ps1 — Fonctions utilitaires et initialisation

.DESCRIPTION
    Contient :
    - Fonctions d'affichage console (Write-SectionHeader, Write-Info, Write-Counter, etc.)
    - Fonction LastLogonConvert
    - Verification et chargement des modules requis (ActiveDirectory, PSWriteHTML, GPMC)
    - Initialisation des collections de donnees ($Table, $UserTable, $ComputersTable, etc.)

    Fait partie du module ModernActiveDirectoryEnhanced.
    Dot-source automatiquement par ModernActiveDirectoryEnhanced.psm1.
#>

#region Console Display Functions
# ============================================================================
# Fonctions pour une interface console claire et professionnelle
# ============================================================================

function Write-SectionHeader {
    param([string]$Title)
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor White -NoNewline
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
}

function Write-Info {
    param([string]$Label, [string]$Value, [string]$Color = "White")
    $padding = 35 - $Label.Length
    if ($padding -lt 1) { $padding = 1 }
    Write-Host "  $Label" -ForegroundColor Gray -NoNewline
    Write-Host (" " * $padding) -NoNewline
    Write-Host ": " -ForegroundColor DarkGray -NoNewline
    Write-Host $Value -ForegroundColor $Color
}

function Write-Counter {
    param([string]$Label, [int]$Count, [string]$Color = "Cyan")
    Write-Host "    ▪ " -ForegroundColor DarkGray -NoNewline
    Write-Host $Label.PadRight(40) -ForegroundColor Gray -NoNewline
    Write-Host $Count.ToString().PadLeft(8) -ForegroundColor $Color
}

function Write-Progress-Custom {
    param([string]$Activity, [string]$Status)
    Write-Host "  ⏳ " -ForegroundColor Yellow -NoNewline
    Write-Host "$Activity" -ForegroundColor White -NoNewline
    Write-Host " - " -ForegroundColor DarkGray -NoNewline
    Write-Host "$Status" -ForegroundColor Gray
}

function Write-Success {
    param([string]$Message)
    Write-Host "  ✓ " -ForegroundColor Green -NoNewline
    Write-Host $Message -ForegroundColor White
}

function Write-Warning-Custom {
    param([string]$Message)
    Write-Host "  ⚠ " -ForegroundColor Yellow -NoNewline
    Write-Host $Message -ForegroundColor Yellow
}

function Write-Banner {
    $width = 75
    $line1 = "ACTIVE DIRECTORY OVERVIEW"
    $line2 = "Full Environment Analysis & Lifecycle Monitoring"
    
    $pad1L = " " * [math]::Floor(($width - $line1.Length) / 2)
    $pad1R = " " * [math]::Ceiling(($width - $line1.Length) / 2)
    $pad2L = " " * [math]::Floor(($width - $line2.Length) / 2)
    $pad2R = " " * [math]::Ceiling(($width - $line2.Length) / 2)

    Write-Host ""
    Write-Host "  ╔═══════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║                                                                           ║" -ForegroundColor Cyan
    Write-Host "  ║$pad1L" -ForegroundColor Cyan -NoNewline
    Write-Host $line1 -ForegroundColor White -NoNewline
    Write-Host "$pad1R║" -ForegroundColor Cyan
    Write-Host "  ║                                                                           ║" -ForegroundColor Cyan
    Write-Host "  ║$pad2L" -ForegroundColor Cyan -NoNewline
    Write-Host $line2 -ForegroundColor Gray -NoNewline
    Write-Host "$pad2R║" -ForegroundColor Cyan
    Write-Host "  ║                                                                           ║" -ForegroundColor Cyan
    Write-Host "  ╚═══════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    # Lire la version depuis le manifeste (source de verite unique)
    $_moduleVersion = try {
        $m = Get-Module -ListAvailable -Name "ModernActiveDirectoryEnhanced" | Sort-Object Version -Descending | Select-Object -First 1
        if ($m) { $m.Version.ToString() } else { "2.0.0" }
    } catch { "2.0.0" }
    Write-Host "  Version: " -ForegroundColor Gray -NoNewline
    Write-Host $_moduleVersion -ForegroundColor Cyan -NoNewline
    Write-Host " │ " -ForegroundColor DarkGray -NoNewline
    Write-Host "Date: " -ForegroundColor Gray -NoNewline
    Write-Host (Get-Date -Format "yyyy-MM-dd HH:mm:ss") -ForegroundColor White
    Write-Host ""
}
#endregion

#region get infos

function LastLogonConvert {
    param([Parameter(Mandatory=$false)][long]$ftDate = 0)
    
    if ($ftDate -eq 0 -or $ftDate -eq [long]::MaxValue) { 
        return "" 
    }
    
    try {
        $Date = [DateTime]::FromFileTime($ftDate)
        if ($Date.Year -lt 1900) { 
            return "" 
        }
        return $Date
    } catch {
        return ""
    }
} #End function LastLogonConvert

#region Module Initialization Functions
# ============================================================================
# IMPORTANT : ces verifications sont encapsulees dans des fonctions.
# Elles NE s'executent PAS au dot-sourcing — uniquement quand appelees
# explicitement par Get-MADReport (apres le bloc -PreCheck).
# Cela permet au -PreCheck de fonctionner sans RSAT installe.
# ============================================================================

function Initialize-ADModule {
<#
.SYNOPSIS
    Charge le module ActiveDirectory. Leve une exception claire si RSAT est absent.
.NOTES
    A appeler UNIQUEMENT apres le bloc -PreCheck dans le psm1.
#>
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        Write-Verbose "Module Active Directory charge avec succes"
    } catch {
        Write-Host "" 
        Write-Host "  ✗ Le module ActiveDirectory est requis mais introuvable." -ForegroundColor Red
        Write-Host ""
        Write-Host "  Pour installer RSAT sur Windows Server :" -ForegroundColor Yellow
        Write-Host "    Install-WindowsFeature RSAT-AD-PowerShell" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  Pour installer RSAT sur Windows 10/11 :" -ForegroundColor Yellow
        Write-Host "    Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  Details : $($_.Exception.Message)" -ForegroundColor DarkGray
        Write-Host ""
        throw "Operation aborted - AD module not available. Run: Install-WindowsFeature RSAT-AD-PowerShell"
    }
}

function Initialize-PSWriteHTMLModule {
<#
.SYNOPSIS
    Charge PSWriteHTML, l'installe automatiquement si absent.
.NOTES
    A appeler UNIQUEMENT apres le bloc -PreCheck dans le psm1.
#>
    if (!(Get-Module -ListAvailable -Name "PSWriteHTML")) {
        # B07 FIX : installation dans le scope utilisateur, avec confirmation et gestion d'erreur
        Write-Warning-Custom "Module PSWriteHTML absent."
        Write-Host "  Installation de PSWriteHTML (scope : CurrentUser)..." -ForegroundColor Yellow
        try {
            Install-Module -Name PSWriteHTML -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
            Write-Host "  [OK] PSWriteHTML installe avec succes." -ForegroundColor Green
            Import-Module PSWriteHTML -ErrorAction Stop
        } catch {
            Write-Host ""
            Write-Host "  [ERREUR] Impossible d'installer PSWriteHTML automatiquement." -ForegroundColor Red
            Write-Host "  Cause : $($_.Exception.Message)" -ForegroundColor Red
            Write-Host ""
            Write-Host "  Installation manuelle :" -ForegroundColor Yellow
            Write-Host "    Install-Module -Name PSWriteHTML -Scope CurrentUser -Force" -ForegroundColor Cyan
            Write-Host ""
            throw "Module PSWriteHTML requis. Installez-le manuellement puis relancez le rapport."
        }
    } else {
        Import-Module PSWriteHTML -ErrorAction Stop
    }
}

#endregion Module Initialization Functions

#Array of default Security Groups
$DefaultSGs = @()
try {
    $searcher = [adsisearcher]"(|(&(groupType:1.2.840.113556.1.4.803:=1))(&(objectCategory=group)(admincount=1)(iscriticalsystemobject=*)))"
    $searcher.PageSize = 1000
    $searcher.PropertiesToLoad.AddRange(@('name'))
    $results = $searcher.FindAll()
    $DefaultSGs = $results | ForEach-Object { $_.Properties.name }
    $results.Dispose()
    $searcher.Dispose()
    Write-Verbose "Groupes de securite par defaut recuperes : $($DefaultSGs.Count)"
} catch {
    Write-Warning-Custom "Impossible de recuperer les groupes de securite par defaut : $($_.Exception.Message)"
    $DefaultSGs = @()
}
#region PScutom
$Table = New-Object 'System.Collections.Generic.List[System.Object]'
$Groupsnomembers = New-Object 'System.Collections.Generic.List[System.Object]'
$OUTable = New-Object 'System.Collections.Generic.List[System.Object]'
$UserTable = New-Object 'System.Collections.Generic.List[System.Object]'
$Unlockusers = New-Object 'System.Collections.Generic.List[System.Object]'
$DomainTable = New-Object 'System.Collections.Generic.List[System.Object]'
$GPOTable = New-Object 'System.Collections.Generic.List[System.Object]'
$ADObjectTable = New-Object 'System.Collections.Generic.List[System.Object]'
$ComputersTable = New-Object 'System.Collections.Generic.List[System.Object]'
$DefaultComputersinDefaultOUTable = New-Object 'System.Collections.Generic.List[System.Object]'
$DefaultUsersinDefaultOUTable = New-Object 'System.Collections.Generic.List[System.Object]'
$TOPUserTable = New-Object 'System.Collections.Generic.List[System.Object]'
$TOPGroupsTable = New-Object 'System.Collections.Generic.List[System.Object]'
$TOPComputersTable = New-Object 'System.Collections.Generic.List[System.Object]'
$GraphComputerOS = New-Object 'System.Collections.Generic.List[System.Object]'
$barcreateobject = New-Object 'System.Collections.Generic.List[System.Object]'
$NewCreatedUsersTable = New-Object 'System.Collections.Generic.List[System.Object]'
# Initialisation partagee Users/Computers — dependance explicite
$Createdlastdays = $null
#endregion PScustom

#Check for GPMC module
$GPMOD = Get-Module -ListAvailable -Name "GroupPolicy"
if ($null -eq $GPMOD)
{	
	Write-Warning-Custom "Module GPMC absent - les donnees GPO ne seront pas collectees. Pour installer : Install-WindowsFeature GPMC"
    $nogpomod = $true
} else { 
    $nogpomod = $false
    Write-Verbose "GPMC module found - GPO data will be collected"
}

#endregion get infos