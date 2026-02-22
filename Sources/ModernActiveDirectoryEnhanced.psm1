<#
.SYNOPSIS
    Modern Active Directory HTML Report with End-of-Life Tracking
    
    Generates comprehensive, interactive HTML reports for Active Directory analysis 
    including End-of-Life (EoL) tracking for operating systems.

.DESCRIPTION
    The Modern Active Directory Report module creates dynamic, multi-page HTML reports 
    that provide detailed insights into your Active Directory environment.
    
    KEY FEATURES:
    - Interactive HTML interface with dynamic filtering and sorting
    - Dashboard with visual statistics and trends
    - User analysis (inactive, locked, expiring passwords, new accounts)
    - Computer inventory with OS version tracking and EoL status
    - End-of-Life (EoL) tracking for Windows, Linux, and macOS systems
    - Group membership analysis
    - GPO reporting
    - Organizational Unit (OU) structure
    - Security analysis (privileged accounts, default passwords)
    
    EoL DATABASE:
    The module includes comprehensive End-of-Life tracking using an external JSON database 
    (eol-database.json) that can be updated independently. Supported systems include:
    - Windows 10/11 (all releases including LTSC)
    - Windows Server 2008 through 2025
    - Ubuntu LTS, Debian, RHEL, SLES
    - macOS (recent versions)
    
    REQUIREMENTS:
    - PowerShell 5.1 or later
    - Active Directory PowerShell module (RSAT-AD-PowerShell)
    - PSWriteHTML module (auto-installed if missing)
    - Domain Administrator or Read permissions on AD
    - EoL-Functions.ps1 and eol-database.json (for EoL tracking)

.PARAMETER CompanyLogo
    URL or UNC path to your company logo (displayed on the left side).
    Accepts: .PNG, .JPG, .GIF formats
    Default: GitHub project logo
    Example: "C:\Logos\MyCompany.png" or "https://example.com/logo.png"

.PARAMETER RightLogo
    URL or UNC path for a secondary logo (displayed on the right side).
    Useful for department logos, certifications, or partner logos.
    Default: GitHub project logo

.PARAMETER ReportTitle
    Custom title for the generated report.
    This title appears at the top of the HTML report.
    Default: "Active Directory Report"

.PARAMETER SavePath
    Directory path where the HTML report will be saved.
    The module creates multiple files (HTML, CSS, JS) in this location.
    Default: $env:TEMP (Windows temporary folder)
    Note: Ensure write permissions exist for the specified path.

.PARAMETER UserInactiveDays
    Number of days of inactivity after which a user account is flagged as inactive.
    Users who have not logged in for this many days are highlighted in the report.
    Default: 90 days
    Range: 1-365 days recommended

.PARAMETER UserCreatedDays
    Show users created within the last X days.
    Useful for auditing recent account creation.
    Default: 7 days

.PARAMETER UserPasswordExpireDays
    Show users whose passwords will expire within X days.
    Helps with proactive password management and user notification.
    Default: 7 days

.PARAMETER MaxSearchObjects
    Maximum number of AD objects (users/computers) to retrieve.
    Use lower values for quick testing on large environments.
    Default: 300
    Use -UnlimitedSearch to bypass this limit.

.PARAMETER MaxSearchGroups
    Maximum number of AD groups to retrieve.
    Default: 300
    Use -UnlimitedSearch to bypass this limit.

.PARAMETER OUSearchScope
    Depth of Organizational Unit (OU) scanning.
    - "OneLevel": Scan only direct child OUs (faster)
    - "Base": Scan only the base OU
    - "Subtree": Scan all nested OUs (comprehensive but slower)
    Default: "OneLevel"

.PARAMETER UnlimitedSearch
    Remove all search limits and retrieve ALL AD objects.
    Warning: Can be slow on large environments (10K+ objects).
    Internally sets MaxSearchObjects=300000 and MaxSearchGroups=100000.

.PARAMETER LimitedView
    Security filter that excludes privileged accounts from the report (enabled by default).
    
    When enabled (default):
    - EXCLUDES users with AdminCount=1 (Domain Admins, Enterprise Admins, etc.)
    - EXCLUDES privileged groups (Domain Admins, Schema Admins, etc.)
    - Shows only regular users and non-privileged groups
    
    Purpose:
    - Prevent exposure of administrative accounts in shared reports
    - Comply with security best practices
    - Reduce risk if the report falls into the wrong hands
    
    To include ALL accounts and sensitive objects:
    - Use -ShowSensitiveObjects (overrides LimitedView and unlocks DC, GPO-DC sections, and privileged groups)
    - Or set -LimitedView:$false (includes privileged users/groups without unlocking extra sections)
    
    Default: $true (secure by default)

.PARAMETER ShowSensitiveObjects
    Include ALL sensitive and privileged objects in the report and unlock additional sections.
    
    When enabled, the following objects — excluded by default — become visible:
    - Users with AdminCount=1 (Domain Admins, Enterprise Admins, etc.)
    - Privileged groups (Domain Admins, Schema Admins, Builtin groups, etc.)
    - Domain Controllers (normally excluded from the computer inventory)
    - GPO linked to the Domain Controllers OU (dedicated section unlocked)
    
    Also overrides LimitedView.
    
    Use this flag when performing a full security audit or Tier-0 review.
    Note: Use -LimitedView:$false if you only want to include privileged users/groups
    without unlocking the DC and GPO-DC sections.

.PARAMETER SinglePageReport
    Generate a single-page HTML report instead of a multi-page report.
    Recommended only for small environments (fewer than 5000 objects).
    Faster to load but less organized for large datasets.

.PARAMETER ShowEoLOverview
    Display the End-of-Life overview section in the report.
    Shows a summary of systems approaching or past their EoL dates.

.PARAMETER DaysBeforeEoL
    Number of days before End-of-Life to trigger a warning status.
    Systems within this threshold are shown as "J-XX" (e.g. J-90, J-60).
    Default: 90 days
    
    STATUS INDICATORS:
    - "Supported" (Green): More than X days remaining before EoL
    - "J-XX" (Orange): Warning - fewer than X days until EoL
    - "EOL" (Red): Past End-of-Life date
    - "Unknown" (Gray): OS not found in the EoL database

.PARAMETER AdminInactivityThreshold
    Number of days of inactivity after which an admin account triggers a security alert.
    ANSSI recommends flagging admin accounts inactive for more than 90 days.
    Default: 90 days

.PARAMETER UserInactivityThreshold
    Number of days of inactivity after which a standard user account triggers a security alert.
    ANSSI recommends flagging user accounts inactive for more than 180 days.
    Default: 180 days

.PARAMETER DisabledAccountsThreshold
    Percentage of disabled accounts above which a security alert is triggered.
    ANSSI recommends investigating if disabled accounts exceed 30% of total accounts.
    Default: 30

.PARAMETER EmptyGroupsThreshold
    Percentage of empty groups above which a security alert is triggered.
    A high number of empty groups may indicate poor group lifecycle management.
    Default: 20

.PARAMETER PasswordNeverExpiresThreshold
    Percentage of accounts with password set to never expire above which a security alert is triggered.
    ANSSI recommends keeping this below 5% of total accounts.
    Default: 5

.PARAMETER ComputerInactivityThreshold
    Number of days of inactivity after which a computer account triggers a security alert.
    ANSSI recommends flagging computer accounts inactive for more than 90 days.
    Default: 90 days

.PARAMETER PreCheck
    Run environment validation only, without generating the full report.
    Verifies AD connectivity, required modules, account permissions, and estimates execution time.
    Useful before running a full report on large or unknown environments.

.EXAMPLE
    Get-MADReport
    
    Basic usage - Creates a report with default settings (300 objects max).
    Output: Multi-page HTML report saved to $env:TEMP folder.

.EXAMPLE
    Get-MADReport -UnlimitedSearch -SavePath "C:\Reports"
    
    Full environment scan with unlimited objects.
    Report saved to C:\Reports folder.
    Recommended for comprehensive audits.

.EXAMPLE
    Get-MADReport -UnlimitedSearch -SavePath "C:\Reports" -ReportTitle "Q1 2026 Audit"
    
    Complete scan with custom report title.
    Useful for quarterly compliance reporting.

.EXAMPLE
    Get-MADReport -CompanyLogo "C:\Logos\Acme.png" -RightLogo "C:\Logos\ISO27001.png" -ReportTitle "ACME Corp - IT Infrastructure"
    
    Branded report with custom logos and title.
    Perfect for executive presentations.

.EXAMPLE
    Get-MADReport -UserInactiveDays 180 -UserPasswordExpireDays 14 -UserCreatedDays 30
    
    Custom thresholds for user analysis:
    - Flag users inactive for 180+ days
    - Show passwords expiring within 14 days
    - Show users created in last 30 days

.EXAMPLE
    Get-MADReport -MaxSearchObjects 50 -MaxSearchGroups 20 -SavePath "C:\Test"
    
    Quick test on large environment.
    Limits to 50 users/computers and 20 groups for fast generation.

.EXAMPLE
    Get-MADReport -UnlimitedSearch -ShowSensitiveObjects -OUSearchScope Subtree
    
    Comprehensive security audit:
    - Unlimited search
    - Include ALL sensitive objects: privileged accounts, DC, GPO-DC sections
    - Deep OU scanning

.EXAMPLE
    Get-MADReport -SinglePageReport -MaxSearchObjects 1000 -SavePath "C:\Reports\QuickView.html"
    
    Single-page report for small environment.
    All data in one HTML file (up to 1000 objects).

.EXAMPLE
    Get-MADReport -DaysBeforeEoL 120 -SavePath "C:\EoL_Reports"
    
    Focus on End-of-Life tracking with 120-day warning threshold.
    Highlights systems approaching EoL within 4 months.

.EXAMPLE
    Get-MADReport -UnlimitedSearch -ShowEoLOverview -SavePath "C:\Compliance"
    
    Full compliance report with EoL overview section.
    Includes detailed breakdown of OS versions and support status.

.NOTES
    File Name      : ModernActiveDirectoryEnhanced.psm1
    Author         : JCh Labs
    Prerequisite   : PowerShell 5.1+, AD Module, PSWriteHTML
    Version        : 2.0.0
    
    PROJECT INFORMATION:
    - Repository   : https://github.com/JCh-Labs/ModernActiveDirectoryEnhanced
    - License      : Use at your own risk
    - Last Updated : February 2026
    
    PERFORMANCE TIPS:
    - Use MaxSearchObjects/MaxSearchGroups for large environments (10K+ objects)
    - OneLevel OU search is faster than Subtree
    - Single-page reports load faster but are harder to navigate
    - Schedule reports during off-hours for minimal AD impact
    
    END-OF-LIFE DATABASE:
    - Database File: eol-database.json (must be in same folder as .psm1)
    - Functions File: EoL-Functions.ps1 (must be in same folder as .psm1)
    - Update: Database can be updated via Update-EoLFromAPI cmdlet
    - Coverage: 100+ OS versions (Windows, Linux, macOS)
    
    TROUBLESHOOTING:
    - If EoL data is missing: Ensure eol-database.json and EoL-Functions.ps1 
      are in the module folder
    - Slow performance: Reduce MaxSearchObjects or use OneLevel OU search
    - Module not found: Run 'Import-Module ModernActiveDirectory -Force'
    - PSWriteHTML missing: Module will auto-install in CurrentUser scope on first run (requires internet access to PSGallery)
    
    SECURITY NOTES:
    - Requires read access to Active Directory
    - No modifications are made to AD (read-only operations)
    - Generated reports may contain sensitive data - secure appropriately
    - Review report content before sharing outside IT department

.LINK
    https://github.com/JCh-Labs/ModernActiveDirectoryEnhanced

.LINK
    https://endoflife.date

.OUTPUTS
    HTML Files
    The module generates multiple files in the SavePath directory:
    - Main HTML report (multi-page or single-page)
    - CSS stylesheets
    - JavaScript files for interactivity
    - Embedded data for charts and tables
    
    Console Output
    Progress messages showing:
    - Module loading status
    - EoL database status
    - Data collection progress
    - Object counts and statistics
    - Report generation status
    - Final report location

#>
function Get-MADReport{






 [CmdletBinding()]
param (
    [bool]$LimitedView = $true,
    #Company logo that will be displayed on the left, can be URL or UNC
	[Parameter(ValueFromPipeline = $true, HelpMessage = "Enter URL or UNC path to Company Logo")]
	[String]$CompanyLogo = "https://raw.githubusercontent.com/JCh-Labs/ModernActiveDirectoryEnhanced/main/Pictures/MAD_Logo.png",

    #Logo that will be on the right side, UNC or URL
	[Parameter(ValueFromPipeline = $true, HelpMessage = "Enter URL or UNC path for Side Logo")]
	[String]$RightLogo = "https://raw.githubusercontent.com/JCh-Labs/ModernActiveDirectoryEnhanced/main/Pictures/MAD_RightLogo-1.png",
    
    #Title of generated report
    [Parameter(ValueFromPipeline = $true, HelpMessage = "Enter desired title for report")]
	[String]$ReportTitle = "Active Directory Report",

    #Location the report will be saved	
    [Parameter(ValueFromPipeline = $true, HelpMessage = "Enter desired directory path to save the report; Default: Windows Temp folder")]
	[String]$SavePath = $env:TEMP,

   	#Find users that have not logged in X Amount of days, this sets the days	
    [Parameter(ValueFromPipeline = $true, HelpMessage = "Users that have not logged on in more than [X] days. amount of days; Default: 90")]
	$UserInactiveDays = 90,

	#Get users who have been created in X amount of days and less	
    [Parameter(ValueFromPipeline = $true, HelpMessage = "Users that have been created within [X] amount of days; Default: 30")]
	$UserCreatedDays = 30,

	#Get users whos passwords expire in less than X amount of days
	[Parameter(ValueFromPipeline = $true, HelpMessage = "Users password expires within [X] amount of days; Default: 30")]
	$UserPasswordExpireDays = 30,

    #MAX Users/Computers to search (lower for quick tests on large environments)
    [Parameter(ValueFromPipeline = $true, HelpMessage = "Max users and computers to retrieve; Default: 1000")]
	$MaxSearchObjects = 1000,
    
    #MAX Groups to search (lower for quick tests on large environments)
    [Parameter(ValueFromPipeline = $true, HelpMessage = "Max groups to retrieve; Default: 1000")]
	$MaxSearchGroups = 1000,

    #OU Search scope: Onelevel (direct children only), Base, or Subtree (all nested OUs)
    [Parameter(ValueFromPipeline = $true, HelpMessage = "OU search scope - Onelevel (faster), Base, or Subtree (comprehensive); Default: Onelevel")]
	[ValidateSet("Onelevel","Base","Subtree")]$OUSearchScope = 'Onelevel',

    #Remove all search limits and retrieve ALL AD objects. Can be slow on large environments.
    [Parameter(ValueFromPipeline = $true, HelpMessage = "Remove search limits; internally sets MaxSearchObjects=300000 and MaxSearchGroups=100000")]
    [switch]$UnlimitedSearch,

    #Include ALL sensitive/privileged objects (admin accounts, privileged groups, Domain Controllers, GPO-DC).
    #Overrides LimitedView. Unlocks additional report sections.
    [Parameter(ValueFromPipeline = $true, HelpMessage = "Include privileged accounts, DC, and GPO-DC sections. Overrides LimitedView.")]
    [switch]$ShowSensitiveObjects,

    #Generate a single-page HTML report. Recommended only for small environments (<5000 objects).
    [Parameter(ValueFromPipeline = $true, HelpMessage = "Generate a single-page HTML report instead of multi-page; recommended for small environments only")]
    [switch]$SinglePageReport,
    [switch]$ShowEoLOverview,

    #Nombre de jours pour identifier les objets recemment crees (utilisateurs et ordinateurs)
    [Parameter(ValueFromPipeline = $true, HelpMessage = "Days window to flag recently created users and computers; Default: 30")]
    [int]$RecentObjectsDays = 30,

    #Number of days before End of Life to trigger J-XX warning status
    [Parameter(ValueFromPipeline = $true, HelpMessage = "Number of days before EoL to show warning status; Default: 90")]
    [int]$DaysBeforeEoL = 90,

    # === SEUILS D'ALERTE SÉCURITÉ (recommandations ANSSI) ===
    
    #Seuil alerte : Comptes administrateurs inactifs (jours)
    [Parameter(ValueFromPipeline = $true, HelpMessage = "Alert if admin accounts inactive for X days; ANSSI recommends 90; Default: 90")]
    [int]$AdminInactivityThreshold = 90,
    
    #Seuil alerte : Comptes utilisateurs inactifs (jours)  
    [Parameter(ValueFromPipeline = $true, HelpMessage = "Alert if user accounts inactive for X days; ANSSI recommends 180; Default: 180")]
    [int]$UserInactivityThreshold = 180,
    
    #Seuil alerte : Pourcentage de comptes désactivés
    [Parameter(ValueFromPipeline = $true, HelpMessage = "Alert if disabled accounts exceed X percent; ANSSI recommends 30; Default: 30")]
    [int]$DisabledAccountsThreshold = 30,
    
    #Seuil alerte : Groupes vides
    [Parameter(ValueFromPipeline = $true, HelpMessage = "Alert if empty groups exceed X percent; Default: 20")]
    [int]$EmptyGroupsThreshold = 20,
    
    #Seuil alerte : Mots de passe n'expirant jamais
    [Parameter(ValueFromPipeline = $true, HelpMessage = "Alert if password never expires accounts exceed X percent; ANSSI recommends 5; Default: 5")]
    [int]$PasswordNeverExpiresThreshold = 5,
    
    #Seuil alerte : Ordinateurs inactifs (jours)
    [Parameter(ValueFromPipeline = $true, HelpMessage = "Alert if computers inactive for X days; ANSSI recommends 90; Default: 90")]
    [int]$ComputerInactivityThreshold = 90,
    
    #Run PreCheck only to verify environment before generating full report
    [Parameter(ValueFromPipeline = $true, HelpMessage = "Run PreCheck only to verify AD environment, modules, permissions, and estimate execution time")]
    [switch]$PreCheck,

    #Ouvre le rapport dans le navigateur apres generation
    # ANOMALIE4 FIX : [switch]$x = $true est invalide en PS5.1 (defaut garanti $false
    # pour les switch). On utilise [bool] pour permettre un vrai defaut $true.
    [Parameter(ValueFromPipeline = $true, HelpMessage = "Open the HTML report in the default browser after generation")]
    [bool]$ShowReport = $true
)


# --- MAD-OSFamilyMap charge en premier — source de vérité unique pour la catégorisation des OS ---
$_mad_osfamilymap = Join-Path $PSScriptRoot "MAD-OSFamilyMap.ps1"
if (Test-Path $_mad_osfamilymap) { . $_mad_osfamilymap }
else { throw "MAD-OSFamilyMap.ps1 introuvable dans $PSScriptRoot" }

# --- MAD-Helpers charge ensuite pour rendre Write-Warning-Custom disponible ---
$_mad_helpers = Join-Path $PSScriptRoot "MAD-Helpers.ps1"
if (Test-Path $_mad_helpers) { . $_mad_helpers }
else { throw "MAD-Helpers.ps1 introuvable dans $PSScriptRoot" }

# === CHARGEMENT DU MODULE EOL ===
$EoLModulePath = Join-Path $PSScriptRoot "EoL-Functions.ps1"
$EoLDatabaseLoaded = $false

if (Test-Path $EoLModulePath) {
    try {
        . $EoLModulePath
        Write-Host "✓ Module EoL-Functions.ps1 chargé" -ForegroundColor Green
        $EoLDatabaseLoaded = $true
    } catch {
        Write-Warning-Custom "Erreur chargement EoL-Functions.ps1 : $($_.Exception.Message)"
        $EoLDatabaseLoaded = $false
    }
} else {
    Write-Verbose "Module EoL-Functions.ps1 non trouvé - mode statique"
    $EoLDatabaseLoaded = $false
}

# === CHARGEMENT DU MODULE VERSIONING EOL ===
$EoLVersioningPath = Join-Path $PSScriptRoot "EoL-Versioning.ps1"

if (Test-Path $EoLVersioningPath) {
    try {
        . $EoLVersioningPath
        Write-Verbose "✓ Module EoL-Versioning.ps1 chargé"
    } catch {
        Write-Warning-Custom "Erreur chargement EoL-Versioning.ps1 : $($_.Exception.Message)"
    }
} else {
    Write-Verbose "Module EoL-Versioning.ps1 non trouvé - fonctions de versioning indisponibles"
}

# === CHARGEMENT DU MODULE PRECHECK ===
$PreCheckModulePath = Join-Path $PSScriptRoot "PreCheck-Functions.ps1"
$PreCheckModuleLoaded = $false

if (Test-Path $PreCheckModulePath) {
    try {
        . $PreCheckModulePath
        Write-Verbose "✓ Module PreCheck-Functions.ps1 chargé"
        $PreCheckModuleLoaded = $true
    } catch {
        Write-Warning-Custom "Erreur chargement PreCheck-Functions.ps1 : $($_.Exception.Message)"
        $PreCheckModuleLoaded = $false
    }
} else {
    Write-Verbose "Module PreCheck-Functions.ps1 non trouvé"
    $PreCheckModuleLoaded = $false
}

# $WarningStatusName defini ici dans le psm1 — source de verite unique, plus de dependance a Console-Start
$WarningStatusName = "J-$DaysBeforeEoL"

#Console start — initialisation uniquement (LimitedView, UnlimitedSearch)
. "$PSScriptRoot\MAD-Console-Start.ps1"
#endregion ConsoleStart

# ============================================================================
# PRECHECK — bloc dans le psm1 pour que le return stoppe reellement l'execution
# ============================================================================
if ($PreCheck) {

    if (-not $PreCheckModuleLoaded) {
        Write-Error "Le module PreCheck-Functions.ps1 est requis mais n'a pas pu etre charge."
        Write-Host "Assurez-vous que PreCheck-Functions.ps1 est dans le meme repertoire que ce module." -ForegroundColor Yellow
        return
    }

    Write-Host ""
    Write-Host "[?] MODE PRE-CHECK ACTIVE" -ForegroundColor Cyan
    Write-Host "----------------------------------------------------" -ForegroundColor Cyan
    Write-Host "Verification de l'environnement avant generation du rapport..." -ForegroundColor Gray
    Write-Host ""

    # Executer le PreCheck — tout l'affichage se fait via Write-Host dans Invoke-ADReportPreCheck.
    # Le résultat est stocké dans $script:LastPreCheckResult pour un accès éventuel en script,
    # mais n'est PAS retourné au pipeline pour éviter le dump automatique en console interactive.
    # Pour récupérer l'objet : $script:LastPreCheckResult après l'appel.
    $script:LastPreCheckResult = Invoke-ADReportPreCheck -SavePath $SavePath -ShowDetails
    return
}




# ============================================================================
# DÉBUT DE L'EXÉCUTION
# ============================================================================
Write-Banner

Write-SectionHeader "📋 CONFIGURATION"
Write-Info "Domaine cible" $env:USERDNSDOMAIN
Write-Info "Utilisateur" $env:USERNAME
Write-Info "Chemin de sauvegarde" $SavePath
Write-Info "Titre du rapport" $ReportTitle
Write-Info "Seuil d'alerte EoL" "$DaysBeforeEoL jours (J-$DaysBeforeEoL)" "Yellow"
Write-Info "Fenetre objets recents" "$RecentObjectsDays jours" "White"
Write-Info "Recherche limitée" $(if ($UnlimitedSearch) { "Non (recherche complète)" } else { "Oui (max $MaxSearchObjects objets)" })
Write-Host ""
# --- Parametres actifs ---
Write-Host "  Parametres actifs :" -ForegroundColor DarkGray
if ($ShowSensitiveObjects.IsPresent) { Write-Host "    + ShowSensitiveObjects    : Oui - comptes/groupes privileges, DC et GPO-DC inclus" -ForegroundColor Cyan }
if ($UnlimitedSearch.IsPresent)        { Write-Host "    + UnlimitedSearch         : Oui - recherche sans limite" -ForegroundColor Cyan }
if ($SinglePageReport.IsPresent)       { Write-Host "    + SinglePageReport        : Oui - rapport en une seule page" -ForegroundColor Cyan }
if ($ShowEoLOverview.IsPresent)        { Write-Host "    + ShowEoLOverview         : Oui - apercu EoL affiche" -ForegroundColor Cyan }
if (-not $LimitedView -or $ShowSensitiveObjects.IsPresent) {
    Write-Host "    + LimitedView             : Non - tous les comptes inclus" -ForegroundColor Yellow
} else {
    Write-Host "    + LimitedView             : Oui (defaut) - comptes privileges exclus" -ForegroundColor DarkGray
}
Write-Host "    + MaxSearchObjects        : $MaxSearchObjects" -ForegroundColor DarkGray
Write-Host "    + MaxSearchGroups         : $MaxSearchGroups" -ForegroundColor DarkGray
$_ouDesc = switch ($OUSearchScope) {
    "Onelevel" { "Niveau direct uniquement (enfants directs)" }
    "Subtree"  { "Arborescence complete (tous les niveaux)" }
    "Base"     { "OU de base uniquement" }
    default    { $OUSearchScope }
}
Write-Host "    + OUSearchScope           : $OUSearchScope  ($_ouDesc)" -ForegroundColor DarkGray
Write-Host "    + Seuils inactivite       : Admin=$AdminInactivityThreshold j | User=$UserInactivityThreshold j | PC=$ComputerInactivityThreshold j" -ForegroundColor DarkGray
Write-Host "    + Seuils alertes          : DesactivesPct=$DisabledAccountsThreshold% | GroupesVides=$EmptyGroupsThreshold% | PwdNoExpire=$PasswordNeverExpiresThreshold%" -ForegroundColor DarkGray
Write-Host "    + Objets recents (fenetre) : $RecentObjectsDays jours (utilisateurs + ordinateurs)" -ForegroundColor DarkGray
Write-Host ""

#region Dashboard
. "$PSScriptRoot\MAD-Dashboard.ps1"
#endregion Dashboard


#region groups
. "$PSScriptRoot\MAD-Groups.ps1"
#endregion groups


#region OU
. "$PSScriptRoot\MAD-OU.ps1"
#endregion OU

#region Users
. "$PSScriptRoot\MAD-Users.ps1"
#endregion Users

#region GPO
. "$PSScriptRoot\MAD-GPO.ps1"
#endregion GPO

#region Trusts
. "$PSScriptRoot\MAD-Trusts.ps1"
#endregion Trusts


#region Printers
. "$PSScriptRoot\MAD-Printers.ps1"
#endregion Printers


#region Computers
. "$PSScriptRoot\MAD-Computers.ps1"
#endregion Computers


#region EoLCalendar
. "$PSScriptRoot\MAD-EoL.ps1"
#endregion EoLCalendar

#Start ConsoleEnd
. "$PSScriptRoot\MAD-Console-End.ps1"
#endregion ConsoleEnd

Write-Progress-Custom "Rapport HTML" "Création du fichier"

#region Resume
. "$PSScriptRoot\MAD-Resume.ps1"
#endregion Resume

<###########################

	   Sortie HTML

############################>

$OutputPath = $SavePath + '\ADModern.html'

. "$PSScriptRoot\MAD-HTML-MultiPage.ps1"
. "$PSScriptRoot\MAD-HTML-OnePage.ps1"

if ($SinglePageReport.IsPresent ) {
HTMLOnePage
} else {
HTMLMultiPage
}

# ============================================================================
# RAPPORT TERMINÉ
# ============================================================================
Write-Host ""
Write-Success "Rapport HTML généré avec succès!"
Write-Host ""
Write-Info "Fichier généré" $OutputPath "Green"
Write-Info "Taille du fichier" "$([math]::Round((Get-Item $OutputPath).Length / 1MB, 2)) MB" "Cyan"
Write-Info "Heure de fin" (Get-Date -Format "HH:mm:ss") "White"

Write-Host ""
Write-Host "  ╔═══════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "  ║                                                                           ║" -ForegroundColor Green
Write-Host "  ║" -ForegroundColor Green -NoNewline
Write-Host "                              RAPPORT TERMINE                              " -ForegroundColor White -NoNewline
Write-Host "║" -ForegroundColor Green
Write-Host "  ║                                                                           ║" -ForegroundColor Green
Write-Host "  ╚═══════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""

# B04 : ouverture du rapport geree par PSWriteHTML via ShowHTML=$true dans MAD-HTML-*.ps1
# (Start-Process supprime — evite la double ouverture)

}


#region Update EoL Database
function Update-ADEoLDatabase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string[]]$Products = @("windows", "windows-server", "ubuntu", "macos", "debian", "rhel", "sles"),
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    # TOUJOURS recharger EoL-Functions.ps1 pour prendre en compte les modifications
    $modulePath = $PSScriptRoot
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
    Update-EoLFromAPI -Products $Products -Force:$Force -FamilyMap $script:OSFamilyMap
}
Set-Alias -Name "Update-EoL" -Value "Update-ADEoLDatabase" -ErrorAction SilentlyContinue
#endregion Update EoL Database

Export-ModuleMember -Function Get-MADReport, Update-ADEoLDatabase -Alias Update-EoL
