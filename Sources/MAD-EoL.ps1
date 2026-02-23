#region EoLCalendar
<###########################
     EoL Calendar (End-of-Life)
     - EoL_Base    : fin de support standard/securite (sans extension)
     - EoL_Extended: info ESU/ESM/ELS/LTSS/LTS (si existe)
############################>
# B06 FIX : ce fichier ne contient plus aucune definition de fonction.
# Get-ComputerEoLInfo, Get-OSEoLInfo et ConvertTo-StatusCounts sont
# definies dans EoL-Functions.ps1 (source canonique unique),
# deja dot-source par ModernActiveDirectoryEnhanced.psm1 avant ce script.

# === CHARGEMENT BASE EOL (JSON ou Statique) ===
if ($EoLDatabaseLoaded) {
    Write-Verbose "Chargement base EoL depuis JSON..."
    # La base est chargee en cache par Get-EoLDatabase (appelee dans Get-ComputerEoLInfo)
    # Pas besoin de la charger ici : suppression du vestige $EoL_Base/$EoL_Extended global
    if (-not (Get-EoLDatabase)) {
        Write-Warning-Custom "Impossible de charger la base EoL JSON - mode degrade active"
    }
} else {
    Write-Verbose "Mode sans EoL Database"
}

# 4) Enrichissement des lignes + agregats
if ($null -ne $ComputersTable -and $ComputersTable.Count -gt 0) {
    foreach ($c in $ComputersTable) {
        # Passage explicite de $DaysBeforeEoL (parametre du psm1, sans hardcode)
        $info = Get-ComputerEoLInfo -Computer $c -DaysBeforeEoL $DaysBeforeEoL
        if ($info) {
            $c | Add-Member -NotePropertyName 'EoL_Key'            -NotePropertyValue $info.Key     -Force
            $c | Add-Member -NotePropertyName 'EoL_Date'           -NotePropertyValue $info.EoL     -Force
            $c | Add-Member -NotePropertyName 'EoL_DaysLeft'       -NotePropertyValue $info.Days    -Force
            $c | Add-Member -NotePropertyName 'EoL_Status'         -NotePropertyValue $info.Status  -Force
            $c | Add-Member -NotePropertyName 'EoL_ExtendedType'   -NotePropertyValue $info.EoL_ExtendedType -Force
            $c | Add-Member -NotePropertyName 'EoL_ExtendedEnd'    -NotePropertyValue $info.EoL_ExtendedEnd -Force
        } else {
            # OS non trouvé dans la base : initialiser tous les membres pour éviter des erreurs d'accès
            $c | Add-Member -NotePropertyName 'EoL_Key'          -NotePropertyValue $null      -Force
            $c | Add-Member -NotePropertyName 'EoL_Date'         -NotePropertyValue $null      -Force
            $c | Add-Member -NotePropertyName 'EoL_DaysLeft'     -NotePropertyValue $null      -Force
            $c | Add-Member -NotePropertyName 'EoL_Status'       -NotePropertyValue 'Unknown'  -Force
            $c | Add-Member -NotePropertyName 'EoL_ExtendedType' -NotePropertyValue $null      -Force
            $c | Add-Member -NotePropertyName 'EoL_ExtendedEnd'  -NotePropertyValue $null      -Force
        }
    }

    $EoL_Aggregate = $ComputersTable |
        Group-Object EoL_Status |
        ForEach-Object { [pscustomobject]@{ Name = $_.Name; Count = $_.Count } }

    Set-Variable -Name EoL_Aggregate -Value $EoL_Aggregate -Scope Script -Force
}

# --- Agregats Clients / Serveurs par statut EoL ---
$ClientEoLStats = @()
$ServerEoLStats = @()

if ($ClientList.Count -gt 0) {
    $ClientEoLStats = $ClientList |
        Group-Object EoL_Status |
        ForEach-Object { [pscustomobject]@{ Status = $_.Name; Count = $_.Count } }
}
if ($ServerList.Count -gt 0) {
    $ServerEoLStats = $ServerList |
        Group-Object EoL_Status |
        ForEach-Object { [pscustomobject]@{ Status = $_.Name; Count = $_.Count } }
}

# Passage explicite de $WarningStatusName (evite toute dependance implicite de contexte)
$ClientEoL = ConvertTo-StatusCounts -Stats $ClientEoLStats -WarningStatusName $WarningStatusName
$ServerEoL = ConvertTo-StatusCounts -Stats $ServerEoLStats -WarningStatusName $WarningStatusName

# Agregats Divers / Unknown par statut EoL
$DiversEoLStats  = @()
$UnknownEoLStats = @()

if ($DiversList.Count -gt 0) {
    $DiversEoLStats = $DiversList |
        Group-Object EoL_Status |
        ForEach-Object { [pscustomobject]@{ Status = $_.Name; Count = $_.Count } }
}
if ($UnknownOSTable.Count -gt 0) {
    $UnknownEoLStats = $UnknownOSTable |
        ForEach-Object { [pscustomobject]@{ Status = 'Unknown'; Count = 1 } }
}

# POINT12 FIX : le fallback doit utiliser la meme cle que ConvertTo-StatusCounts.
# Cette fonction retourne 'J90' (nom fixe), pas 'Warning'. Tout code appelant .J90
# sur un objet fallback obtenait $null avant ce correctif.
$_EoLFallback = { [PSCustomObject]@{ Supported=0; J90=0; EOL=0; Unknown=0 } }
$DiversEoL  = if ($DiversEoLStats.Count  -gt 0) { ConvertTo-StatusCounts -Stats $DiversEoLStats  -WarningStatusName $WarningStatusName } else { & $_EoLFallback }
$UnknownEoL = if ($UnknownEoLStats.Count -gt 0) { ConvertTo-StatusCounts -Stats $UnknownEoLStats -WarningStatusName $WarningStatusName } else { & $_EoLFallback }

# === Preparer les donnees detaillees pour les graphiques ===
$ClientOSDetails = @()
$ServerOSDetails = @()

# Clients : grouper par OS_Full puis ajouter les compteurs par statut
if ($ClientList.Count -gt 0) {
    $ClientOSDetails = @($ClientList |
        Group-Object OS_Full |
        ForEach-Object {
            $osName = $_.Name
            $group  = $_.Group
            $supported = [int](@($group | Where-Object { $_.EoL_Status -eq 'Supported' }).Count)
            $j90       = [int](@($group | Where-Object { $_.EoL_Status -eq $WarningStatusName }).Count)
            $eol       = [int](@($group | Where-Object { ($_.EoL_Status -eq 'EOL' -or $_.EoL_Status -eq 'EOL-ESU') }).Count)
            $unknown   = [int](@($group | Where-Object { $_.EoL_Status -eq 'Unknown' }).Count)
            [pscustomobject]@{
                OS                  = $osName
                Supported           = $supported
                $WarningStatusName  = $j90
                EOL                 = $eol
                Unknown             = $unknown
                Total               = $group.Count
            }
        } | Sort-Object -Property Total -Descending)
}

# Serveurs : grouper par OS_Full puis ajouter les compteurs par statut
if ($ServerList.Count -gt 0) {
    $ServerOSDetails = @($ServerList |
        Group-Object OS_Full |
        ForEach-Object {
            $osName = $_.Name
            $group  = $_.Group
            $supported = [int](@($group | Where-Object { $_.EoL_Status -eq 'Supported' }).Count)
            $j90       = [int](@($group | Where-Object { $_.EoL_Status -eq $WarningStatusName }).Count)
            $eol       = [int](@($group | Where-Object { ($_.EoL_Status -eq 'EOL' -or $_.EoL_Status -eq 'EOL-ESU') }).Count)
            $unknown   = [int](@($group | Where-Object { $_.EoL_Status -eq 'Unknown' }).Count)
            [pscustomobject]@{
                OS                  = $osName
                Supported           = $supported
                $WarningStatusName  = $j90
                EOL                 = $eol
                Unknown             = $unknown
                Total               = $group.Count
            }
        } | Sort-Object -Property Total -Descending)
}

# Divers : grouper par OS_Full
$DiversOSDetails = @()
if ($DiversList.Count -gt 0) {
    $DiversOSDetails = @($DiversList |
        Group-Object OS_Full |
        ForEach-Object {
            $osName = $_.Name
            $group  = $_.Group
            $supported = [int](@($group | Where-Object { $_.EoL_Status -eq 'Supported' }).Count)
            $j90       = [int](@($group | Where-Object { $_.EoL_Status -eq $WarningStatusName }).Count)
            $eol       = [int](@($group | Where-Object { ($_.EoL_Status -eq 'EOL' -or $_.EoL_Status -eq 'EOL-ESU') }).Count)
            $unknown   = [int](@($group | Where-Object { $_.EoL_Status -eq 'Unknown' }).Count)
            [pscustomobject]@{
                OS                  = $osName
                Supported           = $supported
                $WarningStatusName  = $j90
                EOL                 = $eol
                Unknown             = $unknown
                Total               = $group.Count
            }
        } | Sort-Object -Property Total -Descending)
}

# Unknown : tableau simple (pas de statut EoL, juste le nom brut et le nombre)
$UnknownOSDetails = @()
if ($UnknownOSTable.Count -gt 0) {
    $UnknownOSDetails = @($UnknownOSTable |
        Group-Object RawOS |
        ForEach-Object {
            [pscustomobject]@{
                OS    = if ($_.Name) { $_.Name } else { '(OS vide)' }
                Total = $_.Count
            }
        } | Sort-Object -Property Total -Descending)
}

Write-Verbose "Calendrier EoL calcule avec succes"
#endregion EoLCalendar