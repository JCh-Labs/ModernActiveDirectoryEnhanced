<###########################
     Computers
############################>
# Collecte et analyse du parc informatique AD.
#
# Variables consommees (fournies par le contexte Get-MADReport) :
#   $MaxSearchObjects   - limite de recherche AD
#   $createdlastdays    - date seuil (calculee depuis $RecentObjectsDays, defaut 30j, initialisee dans MAD-Users)
#   $barcreateobject    - liste partagee users/PC pour le graphe timeline (initialisee dans MAD-Helpers)
#
# Variables produites (utilisees par EoL, Resume, HTML MultiPage et OnePage) :
#   $ComputersTable         - liste complete des ordinateurs normalises
#   $ClientList             - postes clients uniquement
#   $ServerList             - serveurs uniquement
#   $UnknownOSTable         - OS non identifies
#   $GraphComputerOS        - agregats OS pour graphes
#   $ClientOSStats          - stats clients par OS_Full
#   $ServerOSStats          - stats serveurs par OS_Full
#   $ClientObsolete / $ClientSupported
#   $ServerObsolete / $ServerSupported
#   $TOPComputersTable      - tableau recapitulatif
#   $totalcomputers, $lastcreatedpc
#   $ComputersProtected / $ComputersNotProtected
#   $ComputerEnabled / $ComputerDisabled
#   $endofsupportwin, $allwin1011, $ComputerNotSupported

Write-Host ""
Write-Host "  #=======================================================================" -ForegroundColor DarkCyan
Write-Host "  #  [ORDINATEURS]" -ForegroundColor Cyan
Write-Host "  #=======================================================================" -ForegroundColor DarkCyan
Write-Progress-Custom "Ordinateurs" "Analyse du parc informatique"

function Convert-WindowsBuildToRelease {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$BuildNumber,
        [Parameter()][ValidateSet('Win10','Win11')][string]$Branch = 'Win10'
    )
    $map10 = @{
        '10240'='1507'; '10586'='1511'; '14393'='1607'; '15063'='1703'; '16299'='1709'
        '17134'='1803'; '17763'='1809'; '18362'='1903'; '18363'='1909'
        '19041'='2004'; '19042'='20H2'; '19043'='21H1'; '19044'='21H2'; '19045'='22H2'
    }
    $map11 = @{
        '22000'='21H2'; '22621'='22H2'; '22631'='23H2'; '26100'='24H2'
    }
    if ($Branch -eq 'Win11') { return $map11[$BuildNumber] }
    else { return $map10[$BuildNumber] }
}

# OSFamilyMap est défini dans ModernActiveDirectoryEnhanced.psm1 (source unique)

# =============================================================================
# Extract-OSVersion : extraction générique de version OS
# Tente toutes les combinaisons possibles entre OperatingSystem et
# OperatingSystemVersion, peu importe comment l'AD a été rempli.
#
# Retourne la version normalisée (ex: "22.04", "14", "12") ou $null
# =============================================================================
function Extract-OSVersion {
    param(
        [string]$Raw,       # OperatingSystem
        [string]$Ver,       # OperatingSystemVersion
        [string]$Pattern    # regex de capture, ex: '\d+\.\d+' ou '\d+'
    )

    $sources = @(
        $Raw,                                    # "Ubuntu 22.04 LTS"
        $Ver,                                    # "22.04" ou "22.04.1"
        "$Raw $Ver",                             # concat
        ($Ver -replace '[^0-9\.]','')            # version nettoyée des suffixes texte
    ) | Where-Object { $_ }

    foreach ($s in $sources) {
        if ($s -match $Pattern) {
            return $matches[0]
        }
    }
    return $null
}

function Normalize-OperatingSystem {
    [CmdletBinding()]
    param(
        [string]$OperatingSystem,
        [string]$OperatingSystemVersion
    )

    $raw = ''
    if ($null -ne $OperatingSystem) { $raw = $OperatingSystem.Trim() }
    $ver = ''
    if ($null -ne $OperatingSystemVersion) { $ver = $OperatingSystemVersion.Trim() }

    if ([string]::IsNullOrWhiteSpace($raw)) {
        return [pscustomobject]@{ Vendor='Unknown'; Family='Other'; Product='Unknown'; Release=$null; Build=$null }
    }

    # Nettoyages simples
    $raw = $raw -replace '�','' -replace '\s+',' '

    # Microsoft Windows (Client & Server)
    if ($raw -match '^Windows\s+(Server\s+)?') {
        $isServer = $raw -match '^Windows\s+Server'
        $family   = if ($isServer) { 'Server' } else { 'Client' }

        # Parse build "10.0 (19045)"
        $build = $null
        if ($ver -match '^\s*\d+\.\d+\s*\((\d+)\)') { $build = $matches[1] }

        # Produit
        if ($isServer) {
        
            # 1) Editions Server IoT
            if ($raw -match 'Windows Server\s+IoT\s+(2025|20\d{2}|2019|2022)') {
                $product = "Windows Server IoT $($matches[1])"
        
            # 2) Editions Server classiques
            } elseif ($raw -match 'Windows Server\s+(2008 R2|2012 R2|2025|2022|2019|2016|2012|2008|20\d{2})') {
                $product = "Windows Server $($matches[1])"
        
            } else {
                $product = 'Windows Server'
            }
        
        } else {
            # 3) Editions Client IoT
            if ($raw -match 'Windows\s+(10|11)\s+IoT\s+Enterprise') {
                $product = "Windows $($matches[1]) IoT Enterprise"
        
            # 4) Clients classiques
            } elseif ($raw -match 'Windows 11')       { $product = 'Windows 11' }
            elseif ($raw -match 'Windows 10')         { $product = 'Windows 10' }
            elseif ($raw -match 'Windows 8\.1')       { $product = 'Windows 8.1' }
            elseif ($raw -match 'Windows 8(?!\.1)')   { $product = 'Windows 8' }
            elseif ($raw -match 'Windows 7')          { $product = 'Windows 7' }
        
            # 5) Anciens Windows XP
            elseif ($raw -match 'Windows XP( Embedded)?') {
                $product = ('Windows XP' + ($(if ($matches[1]) { ' Embedded' } else { '' })))
        
            # 6) Embedded generique
            } elseif ($raw -match 'Windows Embedded')  { $product = 'Windows Embedded' }
        
            else { $product = 'Windows (Client)' }
        }

        # Release marketing pour Win10/11 si build connu
        $release = $null
        if ($build) {
            if ($product -eq 'Windows 11') { $release = Convert-WindowsBuildToRelease -BuildNumber $build -Branch Win11 }
            elseif ($product -eq 'Windows 10') { $release = Convert-WindowsBuildToRelease -BuildNumber $build -Branch Win10 }
        }

        # Family depuis OSFamilyMap — fallback sur la détection isServer si absent (cas Windows IoT, etc.)
        $family = if ($OSFamilyMap.ContainsKey($product)) { $OSFamilyMap[$product] } elseif ($isServer) { 'Server' } else { 'Client' }
        return [pscustomobject]@{ Vendor='Microsoft'; Family=$family; Product=$product; Release=$release; Build=$build }
    }

    # Apple
    if ($raw -match '^(Mac\s*OS\s*X|macOS)') {
        # Mapping : pour macOS >= 11, clé DB = "macOS 14 Sonoma"
        #           pour macOS 10.x, clé DB = "macOS 10.15 Catalina" (cycle complet)
        $macOSNames = @{
            '10.15'='Catalina'; '10.14'='Mojave'; '10.13'='High Sierra'
            '10.12'='Sierra';   '10.11'='El Capitan'
            11='Big Sur'; 12='Monterey'; 13='Ventura'; 14='Sonoma'; 15='Sequoia'
        }
        $macRelease = $null
        $allText = "$raw $ver"

        # Cas 1 : nom de version présent ("Sonoma", "Ventura", "Catalina"...)
        if ($allText -match '(Sequoia|Sonoma|Ventura|Monterey|Big\s*Sur|Catalina|Mojave|High\s*Sierra|Sierra|El\s*Capitan)') {
            $name    = $matches[1] -replace '\s+',' '
            $cycleKey = ($macOSNames.GetEnumerator() | Where-Object { $_.Value -eq $name } | Select-Object -First 1).Key
            if ($cycleKey) { $macRelease = "$cycleKey $name" }
        }

        # Cas 2 : numéro >= 11 (ex: "14.5", "macOS 13")
        if (-not $macRelease) {
            $majorStr = Extract-OSVersion -Raw $raw -Ver $ver -Pattern '(?<!\d)(1[1-9]|\d{2,})(?:\.\d+)?(?!\d)'
            if ($majorStr) {
                $major = [int]($majorStr -replace '\..*','')
                $name  = $macOSNames[$major]
                if ($name) { $macRelease = "$major $name" }
                else       { $macRelease = "$major" }
            }
        }

        # Cas 3 : macOS 10.x — garder le cycle complet "10.15" pour matcher la DB
        if (-not $macRelease) {
            $cycleStr = Extract-OSVersion -Raw $raw -Ver $ver -Pattern '10\.\d+'
            if ($cycleStr) {
                $cycle = ($cycleStr -split '\.')[0..1] -join '.'   # "10.15.7" → "10.15"
                $name  = $macOSNames[$cycle]
                $macRelease = if ($name) { "$cycle $name" } else { $cycle }
            }
        }

        $family = if ($OSFamilyMap.ContainsKey('macOS')) { $OSFamilyMap['macOS'] } else { 'Unknown' }
        return [pscustomobject]@{ Vendor='Apple'; Family=$family; Product='macOS'; Release=$macRelease; Build=$null }
    }

    # Linux — extraction générique depuis les deux champs AD
    if ($raw -match '(Ubuntu|Debian|CentOS|Red\s*Hat|RHEL|SUSE|SLES|Fedora|Linux)') {
        $prod = switch -Regex ($matches[1]) {
            'Red\s*Hat|RHEL' { 'RHEL' }
            default           { $matches[1] }
        }
        $family = if ($OSFamilyMap.ContainsKey($prod)) { $OSFamilyMap[$prod] } else { 'Unknown' }

        # Extraction de version : essaie X.Y d'abord, puis X seul
        # On exclut les versions kernel (ex: "5.15.0-91") en ignorant les valeurs < 6 en majeure
        $linuxRelease = $null

        # Pour RHEL/CentOS/Debian/Fedora, on extrait d'abord la version OS depuis le nom
        # (le noyau RHEL 8/9 = 4.x/5.x passerait le filtre $major -ge 6 a tort)
        if ($prod -in @('RHEL','CentOS','Debian','Fedora')) {
            # Chercher le numéro de version OS dans le champ OperatingSystem (ex: "Red Hat Enterprise Linux 9.2")
            if ($raw -match '(?:RHEL|Red\s*Hat[^\d]*|CentOS[^\d]*|Debian[^\d]*|Fedora[^\d]*)(\d{1,2})(?:\.\d+)?') {
                $linuxRelease = $matches[1]
            } elseif ($ver -match '^(\d{1,2})(?:\.\d+)?$') {
                # OperatingSystemVersion contient directement la version (ex: "9" ou "9.2")
                $linuxRelease = $matches[1]
            }
        }

        if (-not $linuxRelease) {
            $verXY = Extract-OSVersion -Raw $raw -Ver $ver -Pattern '\d+\.\d+'
            if ($verXY) {
                $major = [int]($verXY -split '\.')[0]
                # Ignorer les versions kernel Linux (majeure < 6, ex: "5.15.0-91")
                if ($major -ge 6) {
                    if ($prod -in @('Ubuntu','SUSE','SLES')) {
                        $linuxRelease = ($verXY -split '\.')[0..1] -join '.'
                    } else {
                        $linuxRelease = "$major"
                    }
                }
            }
            # Fallback : version majeure seule (ex: OSVersion = "22" ou "12")
            if (-not $linuxRelease) {
                $verX = Extract-OSVersion -Raw $raw -Ver $ver -Pattern '(?<!\d)\d{2}(?!\d)'
                if ($verX -and [int]$verX -ge 6) { $linuxRelease = $verX }
            }
        }

        return [pscustomobject]@{ Vendor='Linux'; Family=$family; Product=$prod; Release=$linuxRelease; Build=$null }
    }

    # Hyperviseurs — si absent de OSFamilyMap → Unknown
    if ($raw -match '(ESXi|VMware|Hyper-V|XenServer|Proxmox)') {
        $prod   = $matches[1]
        $family = if ($OSFamilyMap.ContainsKey($prod)) { $OSFamilyMap[$prod] } else { 'Unknown' }
        return [pscustomobject]@{ Vendor='Other'; Family=$family; Product=$prod; Release=$null; Build=$null }
    }

    # ChromeOS / Android — si absent de OSFamilyMap → Unknown
    if ($raw -match '(ChromeOS|Chrome OS|Android)') {
        $prod   = $matches[1] -replace ' ',''
        $family = if ($OSFamilyMap.ContainsKey($prod)) { $OSFamilyMap[$prod] } else { 'Unknown' }
        return [pscustomobject]@{ Vendor='Google'; Family=$family; Product=$prod; Release=$null; Build=$null }
    }

    # FreeBSD / Unix — si absent de OSFamilyMap → Unknown
    if ($raw -match '(FreeBSD|Unix)') {
        $prod   = $matches[1]
        $family = if ($OSFamilyMap.ContainsKey($prod)) { $OSFamilyMap[$prod] } else { 'Unknown' }
        return [pscustomobject]@{ Vendor='Other'; Family=$family; Product=$prod; Release=$null; Build=$null }
    }

    # Tout le reste → Unknown (filet de sécurité)
    return [pscustomobject]@{ Vendor='Unknown'; Family='Unknown'; Product=$raw; Release=$null; Build=$null }
}

# --- Collecte & normalisation ---
$filtercomputer = @(
    'Name','OperatingSystem','OperatingSystemVersion','ProtectedFromAccidentalDeletion',
    'lastlogondate','Created','PasswordLastSet','DistinguishedName','ipv4address',
    'userAccountControl','Enabled'
)

$ComputersProtected = 0; $ComputersNotProtected = 0
$ComputerEnabled = 0;    $ComputerDisabled    = 0
$totalcomputers = 0;     $lastcreatedpc      = 0
$endofsupportwin = 0;    $allwin1011         = 0
$ComputerNotSupported = 0
$DCCount = 0

# Collections
$ComputersTable = New-Object 'System.Collections.Generic.List[Object]'
$UnknownOSTable = New-Object 'System.Collections.Generic.List[Object]'
$ClientList     = New-Object 'System.Collections.Generic.List[Object]'
$ServerList     = New-Object 'System.Collections.Generic.List[Object]'
$DiversList     = New-Object 'System.Collections.Generic.List[Object]'

# En mode ShowSensitiveObjects, on inclut les DC (userAccountControl:=8192)
# En mode standard, on les exclut du tableau ordinateurs
$_computerLDAPFilter = if ($ShowSensitiveObjects.IsPresent) {
    "(objectCategory=computer)"
} else {
    "(!(userAccountControl:1.2.840.113556.1.4.803:=8192))"
}
Write-Progress-Custom "Ordinateurs" $(if ($ShowSensitiveObjects.IsPresent) { "DC inclus (mode ShowSensitiveObjects)" } else { "DC exclus (mode standard)" })

Get-ADComputer -LDAPFilter $_computerLDAPFilter -Properties $filtercomputer -ResultSetSize $MaxSearchObjects |
ForEach-Object {
    $totalcomputers++

    # Detecter si c'est un DC (userAccountControl bit 8192)
    $_isDC = ($_.userAccountControl -band 8192) -eq 8192

    if ($_isDC) { $DCCount++ }
    if ($_.ProtectedFromAccidentalDeletion) { $ComputersProtected++ } else { $ComputersNotProtected++ }
    if ($_.Enabled) { $ComputerEnabled++ } else { $ComputerDisabled++ }

    # Chronologie creations ($RecentObjectsDays jours)
    if ($_.Created -ge $createdlastdays) {
        $lastcreatedpc++
        $barcreated = ($_.created.ToString("yyyy/MM/dd"))
        $rec = $barcreateobject | Where-Object { $_.Date -eq $barcreated }
        if ($rec) { $rec.'Nbr_PC' += 1 }
        else {
            $obj = [pscustomobject]@{ 'Nbr_users' = 0; 'Nbr_PC' = 1; 'Date' = $barcreated }
            $barcreateobject.Add($obj)
        }
    }

    # Normalisation OS
    $norm = Normalize-OperatingSystem -OperatingSystem $_.OperatingSystem -OperatingSystemVersion $_.OperatingSystemVersion

    # Heuristique obsolescence clients Win10/11
    # BUG15 FIX : seuils séparés par OS — Win10 obsolète si build <= 19045 (22H2 = dernière),
    # Win11 part du build 22000 ; les builds Win10 (<22000) ne peuvent pas être Win11.
    if ($norm.Vendor -eq 'Microsoft' -and $norm.Family -eq 'Client' -and $norm.Product -match '^Windows (10|11)$') {
        $allwin1011++
        if ($norm.Build -as [int]) {
            $buildInt = [int]$norm.Build
            if ($norm.Product -eq 'Windows 10') {
                # Win10 : fin de support global octobre 2025 — toutes les versions sont en EoL
                # On marque comme obsolète tout build inférieur au dernier (22H2 = 19045)
                if ($buildInt -lt 19045) { $endofsupportwin++ }
            } elseif ($norm.Product -eq 'Windows 11') {
                # POINT11 FIX : seuil mis a jour — 24H2 (build 26100) est la version
                # courante de Win11 (oct 2024). Les builds anterieurs (21H2=22000,
                # 22H2=22621, 23H2=22631) sont en fin de support.
                # Ancien seuil 22621 ne couvrait ni 23H2 ni 24H2.
                if ($buildInt -lt 26100) { $endofsupportwin++ }
            }
        }
    }

    $obj = [pscustomobject]@{
        'Name'                     = $_.Name
        'Enabled'                  = $_.Enabled
        'Operating System'         = $_.OperatingSystem
        'Operating System Version' = $_.OperatingSystemVersion
        'OS_Product'               = $norm.Product
        'OS_Release'               = $norm.Release
        'OS_Build'                 = $norm.Build
        'OS_Full'                  = ''
        'EoL_Status'               = ''
        'Family'                   = $norm.Family
        'Vendor'                   = $norm.Vendor
        'IPv4Address'              = $_.IPv4Address
        'Created Date'             = $_.Created
        'Password Last Set'        = $_.PasswordLastSet
        'Last Logon Date'          = $_.LastLogonDate
        'Protect from Deletion'    = $_.ProtectedFromAccidentalDeletion
        'OU'                       = (($_.DistinguishedName -split ",") | Where-Object {$_ -like "OU=*"} | ForEach-Object {$_ -replace "OU=",""}) -join ","
        'CN'                       = $_.DistinguishedName
        'Role'                  = if ($_isDC) { 'Domain Controller' } else { 'Workstation/Server' }
        'IsDC'                  = $_isDC
    }
    $ComputersTable.Add($obj)

    switch ($norm.Family) {
        'Client'  { $ClientList.Add($obj) }
        'Server'  { $ServerList.Add($obj) }
        'Divers'  { $DiversList.Add($obj) }
        'Unknown' { $UnknownOSTable.Add([pscustomobject]@{
            Name        = $_.Name
            RawOS       = if ($_.OperatingSystem) { $_.OperatingSystem } else { '(vide)' }
            OSVersion   = if ($_.OperatingSystemVersion) { $_.OperatingSystemVersion } else { '' }
            Enabled     = $_.Enabled
            LastLogon   = $_.LastLogonDate
            OU          = $obj.OU
        }) }
        default   { $UnknownOSTable.Add([pscustomobject]@{
            Name        = $_.Name
            RawOS       = if ($_.OperatingSystem) { $_.OperatingSystem } else { '(vide)' }
            OSVersion   = if ($_.OperatingSystemVersion) { $_.OperatingSystemVersion } else { '' }
            Enabled     = $_.Enabled
            LastLogon   = $_.LastLogonDate
            OU          = $obj.OU
        }) }
    }
}

# Affichage timeline : s'il n'y a qu'un seul point on en ajoute un deuxieme
if ($barcreateobject.Count -eq 1) {
    $obj = [pscustomobject]@{ 'Nbr_users' = 0; 'Nbr_PC' = 0; 'Date' = (Get-Date).AddDays(+1) }
    $barcreateobject.Add($obj)
}

# Agregats propres
$GraphComputerOS = New-Object 'System.Collections.Generic.List[Object]'
$ComputersTable |
    Group-Object OS_Product |
    ForEach-Object { $GraphComputerOS.Add([pscustomobject]@{ Name = $_.Name; Count = $_.Count }) }

# Creation de OS_Full pour TOUS les ordinateurs
$ComputersTable | ForEach-Object {
    $full = ''
    if ($_.OS_Release) {
        # Cas normal : OS_Release rempli par Normalize-OperatingSystem
        # Couvre Windows (ex: "22H2"), macOS (ex: "14 Sonoma"), Linux (ex: "9" pour RHEL, "22.04" pour Ubuntu)
        $full = "$($_.OS_Product) $($_.OS_Release)"
    } else {
        # OS non reconnu ou sans version extractible
        $full = $_.OS_Product
    }
    $_ | Add-Member -NotePropertyName 'OS_Full' -NotePropertyValue $full.Trim() -Force
}

# Stats par OS_Full
$ClientOSStats  = $ClientList  | Group-Object OS_Full | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Count = $_.Count } }
$ServerOSStats  = $ServerList  | Group-Object OS_Full | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Count = $_.Count } }
$DiversOSStats  = $DiversList  | Group-Object OS_Full | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Count = $_.Count } }
$UnknownOSStats = $UnknownOSTable | Group-Object RawOS | ForEach-Object { [pscustomobject]@{ Name = if ($_.Name) { $_.Name } else { '(vide)' }; Count = $_.Count } }

$ClientObsolete  = [int](@($ClientList | Where-Object { $_.Vendor -eq 'Microsoft' -and $_.OS_Product -match '^Windows (10|11)$' -and ($_.OS_Build -as [int]) -le 19042 }).Count)
$ClientSupported = $ClientList.Count - $ClientObsolete
$ServerObsolete  = [int](@($ServerList | Where-Object { $_.'Operating System' -match '2000|2003|2008|2012' }).Count)
$ServerSupported = $ServerList.Count - $ServerObsolete

$OSClass = @{}
$OSClass.Add("Total Computers", $totalcomputers)
$OSClass.Add("Clients",          $ClientList.Count)
$OSClass.Add("Servers",          $ServerList.Count)
$OSClass.Add("Divers",           $DiversList.Count)
$OSClass.Add("Domain Controllers", $DCCount)
$OSClass.Add("Unknown OS",       $UnknownOSTable.Count)
# B08 FIX : .Add() sur la List[Object] initialisee dans MAD-Helpers (evite l'ecrasement par un PSCustomObject)
$TOPComputersTable.Add([pscustomobject]$OSClass)

Write-Success "Ordinateurs collectes"
$_cTotal  = $totalcomputers
$_cClient = $ClientList.Count
$_cServer = $ServerList.Count
$_cDC = $DCCount
Write-Host "  >> Total: $_cTotal | Clients: $_cClient | Serveurs: $_cServer | DC: $_cDC" -ForegroundColor DarkGray
