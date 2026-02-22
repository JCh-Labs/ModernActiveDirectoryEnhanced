# ============================================================================
# MODULE DE GESTION END-OF-LIFE (EoL)
# ============================================================================
# Gestion des données EoL via fichier JSON externe et API endoflife.date
# ============================================================================

#region Configuration
$script:EoLJsonFileName = "EoL-Database.json"
$script:EoLApiBaseUrl = "https://endoflife.date/api"
$script:EoLDatabaseCache = $null   # Cache en mémoire — évite les lectures disque répétées
#endregion

#region Fonctions utilitaires

<#
.SYNOPSIS
Obtient le chemin du fichier JSON EoL.

.DESCRIPTION
Recherche le fichier eol-database.json dans plusieurs emplacements par ordre de priorité.

.OUTPUTS
String - Chemin complet vers le fichier JSON
#>
function Get-EoLDatabasePath {
    [CmdletBinding()]
    param()
    
    # 1. À côté du script (priorité)
    $scriptPath = Join-Path $PSScriptRoot $script:EoLJsonFileName
    if (Test-Path $scriptPath) {
        return $scriptPath
    }
    
    # 2. Dans le répertoire courant
    $currentPath = Join-Path (Get-Location) $script:EoLJsonFileName
    if (Test-Path $currentPath) {
        return $currentPath
    }
    
    # 3. Créer à côté du script si n'existe pas
    Write-Warning "Fichier eol-database.json introuvable. Il sera créé lors du prochain Update-EoLFromAPI à: $scriptPath"
    return $scriptPath
}

<#
.SYNOPSIS
Charge la base de données EoL depuis le fichier JSON.

.DESCRIPTION
Lit et parse le fichier JSON contenant les données End-of-Life des systèmes d'exploitation.

.OUTPUTS
PSCustomObject - Objet contenant toute la base de données EoL
#>
function Get-EoLDatabase {
    [CmdletBinding()]
    param(
        [switch]$ForceReload  # Force la relecture disque (à utiliser après Update-EoLFromAPI)
    )
    
    # Retourner le cache si disponible et rechargement non forcé
    if ($script:EoLDatabaseCache -and -not $ForceReload) {
        Write-Verbose "Base de données EoL retournée depuis le cache mémoire"
        return $script:EoLDatabaseCache
    }
    
    try {
        $jsonPath = Get-EoLDatabasePath
        
        if (-not (Test-Path $jsonPath)) {
            Write-Warning "Fichier JSON EoL introuvable: $jsonPath"
            Write-Host "Créez le fichier ou utilisez: Update-EoLFromAPI" -ForegroundColor Yellow
            return $null
        }
        
        $jsonContent = Get-Content -Path $jsonPath -Raw -Encoding UTF8 -ErrorAction Stop
        $database = $jsonContent | ConvertFrom-Json -ErrorAction Stop
        
        # Mettre en cache pour les appels suivants
        $script:EoLDatabaseCache = $database
        
        Write-Verbose "Base de données EoL chargée depuis: $jsonPath"
        Write-Verbose "Dernière mise à jour: $($database.metadata.last_updated)"
        Write-Verbose "Nombre d'entrées: $($database.os_database.PSObject.Properties.Count)"
        
        return $database
        
    } catch {
        Write-Error "Erreur lors du chargement de la base EoL: $($_.Exception.Message)"
        return $null
    }
}

<#
.SYNOPSIS
Invalide le cache mémoire de la base EoL.

.DESCRIPTION
Force le prochain appel à Get-EoLDatabase à relire le fichier JSON depuis le disque.
À appeler après toute modification de la base (Update-EoLFromAPI, ajout manuel).
#>
function Clear-EoLDatabaseCache {
    [CmdletBinding()]
    param()
    $script:EoLDatabaseCache = $null
    Write-Verbose "Cache de la base EoL invalidé"
}

<#
.SYNOPSIS
Recherche les informations EoL pour un système d'exploitation donné.

.DESCRIPTION
Interroge la base de données JSON pour trouver les dates EoL d'un OS spécifique.

.PARAMETER OSName
Nom du système d'exploitation tel qu'il apparaît dans AD (ex: "Windows Server 2022")

.OUTPUTS
PSCustomObject - Informations EoL de l'OS ou $null si non trouvé
#>
function Get-OSEoLInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OSName
    )
    
    $database = Get-EoLDatabase
    if (-not $database) {
        return $null
    }
    
    $dbKeys = $database.os_database.PSObject.Properties.Name
    
    # 1. Recherche exacte — mais on ignore les entrees AD-style fantomes (api_cycle=unknown,
    #    eol_date=None) creees automatiquement lors de la detection AD sans donnees reelles.
    #    Ex: "Windows 11 22H2" → entree vide, la vraie donnee est dans "Windows 11-22h2-w".
    if ($dbKeys -contains $OSName) {
        $candidate = $database.os_database.$OSName
        $isPlaceholder = ($candidate.api_cycle -eq 'unknown' -and $null -eq $candidate.eol_date)
        if (-not $isPlaceholder) {
            return $candidate
        }
        # Entree fantome : on continue vers les vraies entrees
    }
    
    # 2. Normalisation du nom : "Windows 10 22H2" -> "windows 10-22h2"
    #    Remplace espace+version(xxHx ou 4 chiffres) par tiret+version en minuscules
    $normalized = $OSName -replace ' ([0-9]{2}[hH][0-9])', '-$1'
    $normalized = $normalized -replace ' ([0-9]{4})', '-$1'
    $normalized = $normalized.ToLower()
    
    # 3. Correspondance exacte normalisee
    foreach ($key in $dbKeys) {
        if ($key.ToLower() -eq $normalized) {
            return $database.os_database.$key
        }
    }
    
    # 3a. Variante suffixe -w (workstation) pour Windows 10/11 client
    #     endoflife.date distingue Home/Pro (-w) et Entreprise (-e).
    #     On utilise -w comme representant generique des versions AD detectees.
    $normalizedW = "$normalized-w"
    foreach ($key in $dbKeys) {
        if ($key.ToLower() -eq $normalizedW) {
            return $database.os_database.$key
        }
    }
    
    # 3b. Normalisation tiret/espace pour Windows Server legacy (ancienne base avec clés API brutes)
    # L'API endoflife.date retourne "2008-r2-sp1", "2012-r2", "2008-sp2" mais AD retourne
    # "Windows Server 2008 R2", "Windows Server 2012 R2", "Windows Server 2008".
    # Depuis FIX7a, les nouvelles bases stockent les clés au format AD — mais pour les bases
    # déjà existantes avec les anciens noms, on génère les variants directement depuis $OSName.ToLower()
    # (PAS depuis $normalized qui a déjà transformé les espaces et peut casser le matching).
    $osRawLow = $OSName.ToLower()
    $candidatesDash = @(
        ($osRawLow -replace '\s+r2\s*$', '-r2'),
        ($osRawLow -replace '\s+r2\s*$', '-r2-sp1'),
        ($osRawLow -replace '\s+r2\s*$', '-r2-sp2'),
        ($osRawLow -replace '\s+sp\d+\s*$', '')   # enlever suffixe SP si présent
    ) | Select-Object -Unique
    
    foreach ($candidate in $candidatesDash) {
        foreach ($key in $dbKeys) {
            if ($key.ToLower() -eq $candidate) {
                return $database.os_database.$key
            }
        }
    }
    
    # 4. Correspondance par prefixe normalise
    # Ancienne logique (*OSName* OR *key*) trop large : risque de faux positifs
    # Nouvelle logique : le NOM OS doit commencer par la clé (ou vice-versa), pas simplement la contenir
    foreach ($key in $dbKeys) {
        $keyLow = $key.ToLower()
        $osLow  = $OSName.ToLower()
        # La clé doit être un préfixe du nom OS demandé (ex: "ubuntu" dans "ubuntu 22")
        # ou le nom OS un préfixe de la clé — mais jamais une simple sous-chaîne au milieu
        if ($osLow.StartsWith($keyLow) -or $keyLow.StartsWith($osLow)) {
            return $database.os_database.$key
        }
    }
    
    Write-Verbose "OS non trouve dans la base: $OSName"
    return $null
}

<#
.SYNOPSIS
Calcule le statut EoL d'un système d'exploitation.

.DESCRIPTION
Détermine si un OS est supporté, en fin de support bientôt, ou en fin de vie.

.PARAMETER OSName
Nom du système d'exploitation

.PARAMETER DaysBeforeWarning
Nombre de jours avant la fin de support pour déclencher un avertissement (défaut: 90)

.OUTPUTS
String - "Supported", "J-XX", "EOL", ou "Unknown"
#>
function Get-OSEoLStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OSName,
        
        [Parameter(Mandatory = $false)]
        [int]$DaysBeforeWarning = 90
    )
    
    $osInfo = Get-OSEoLInfo -OSName $OSName
    if (-not $osInfo) {
        return "Unknown"
    }
    
    $today = Get-Date

    # Vérifier le support étendu d'abord (seulement si c'est une date réelle, pas False/N/A)
    $eolDateToCheck = $osInfo.eol_date
    if ($osInfo.extended_support -and
        $osInfo.extended_support -ne $false -and
        $osInfo.extended_support -ne 'False' -and
        $osInfo.extended_support -ne 'N/A') {
        $eolDateToCheck = $osInfo.extended_support
    }

    # Cas explicite : eol_date = False → pas de date annoncée, OS encore supporté
    if (-not $eolDateToCheck -or $eolDateToCheck -eq $false -or
        $eolDateToCheck -eq 'False' -or $eolDateToCheck -eq 'N/A') {
        return "Supported"
    }

    try {
        $eolDate = [DateTime]::Parse($eolDateToCheck)
        $daysUntilEoL = ($eolDate - $today).Days

        if ($daysUntilEoL -lt 0) {
            return "EOL"
        } elseif ($daysUntilEoL -le $DaysBeforeWarning) {
            # Retourner les jours RÉELS restants (pas le seuil du paramètre)
            # Ex: OS expire dans 15j avec $DaysBeforeWarning=90 -> "J-15" et non "J-90"
            return "J-$daysUntilEoL"
        } else {
            return "Supported"
        }

    } catch {
        Write-Warning "Date EoL invalide ou non parseable pour [$OSName] : $eolDateToCheck - statut retourné: Unknown"
        return "Unknown"
    }
}

#endregion

#region Fonctions de mise à jour API

<#
.SYNOPSIS
Appelle l'API endoflife.date pour un produit spécifique.

.DESCRIPTION
Interroge l'API publique endoflife.date pour obtenir les informations de cycle de vie.

.PARAMETER Product
Identifiant du produit dans l'API (ex: "windows", "windows-server", "ubuntu")

.OUTPUTS
Array - Liste des cycles de vie pour le produit
#>
function Invoke-EoLAPI {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Product
    )
    
    try {
        $url = "$script:EoLApiBaseUrl/$Product.json"
        Write-Verbose "Appel API: $url"
        
        $response = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop
        return $response
        
    } catch {
        Write-Warning "Echec de l'appel API pour '$Product' : $($_.Exception.Message)"
        return $null
    }
}

<#
.SYNOPSIS
Met à jour la base de données EoL depuis l'API endoflife.date.

.DESCRIPTION
Récupère les dernières informations EoL depuis l'API et met à jour le fichier JSON.

.PARAMETER Products
Liste des produits à mettre à jour (par défaut: windows, windows-server)

.PARAMETER Force
Force la mise à jour même si le fichier existe déjà

.EXAMPLE
Update-EoLFromAPI -Products @("windows", "windows-server")

.EXAMPLE
Update-EoLFromAPI -Force
#>
function Update-EoLFromAPI {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$Products = @("windows", "windows-server", "ubuntu", "macos", "debian", "rhel", "sles"),

        [Parameter(Mandatory = $false)]
        [switch]$Force,

        # Reçu depuis Update-ADEoLDatabase (défini au niveau module dans le psm1)
        # Evite toute dépendance au scope — plus besoin de chercher la variable
        [Parameter(Mandatory = $false)]
        [hashtable]$FamilyMap = $null
    )

    # Résolution $OSFamilyMap : paramètre prioritaire, sinon fallback minimal
    if ($FamilyMap -and $FamilyMap.Count -gt 0) {
        $script:OSFamilyMap = $FamilyMap
    } else {
        Write-Warning "OSFamilyMap non recu en parametre - utilisation du fallback minimal"
        $script:OSFamilyMap = @{
            'Windows'        = 'Client'
            'Windows Server' = 'Server'
            'macOS'          = 'Client'
            'Ubuntu'         = 'Server'
            'Debian'         = 'Server'
            'RHEL'           = 'Server'
            'SLES'           = 'Server'
        }
    }

    Write-Host ""
    Write-Host "  #=======================================================================" -ForegroundColor DarkCyan
    Write-Host "  #  MISE A JOUR BASE End-of-Life" -ForegroundColor Cyan
    Write-Host "  #=======================================================================" -ForegroundColor DarkCyan
    Write-Host "  Source : endoflife.date API" -ForegroundColor Gray
    Write-Host ""

    # Charger la base existante ou créer une nouvelle
    $jsonPath = Get-EoLDatabasePath
    $database = Get-EoLDatabase

    $isNewDatabase = (-not $database)
    if ($isNewDatabase) {
        Write-Host "  ⏳ Creation d'une nouvelle base de donnees..." -ForegroundColor Yellow
        # IMPORTANT : PSCustomObject obligatoire (pas @{} hashtable) pour que Add-Member
        # fonctionne correctement et que ConvertTo-Json sérialise toutes les entrées.
        # Avec une hashtable, Add-Member ne modifie pas PSObject.Properties
        # -> os_database resterait vide dans le JSON sauvegardé.
        $database = [PSCustomObject]@{
            metadata = [PSCustomObject]@{
                version         = "1.0"
                last_updated    = (Get-Date -Format "yyyy-MM-dd")
                last_api_update = $null
                source          = "endoflife.date API"
            }
            os_database = [PSCustomObject]@{}
        }
    }

    $updateCount = 0
    $errorCount  = 0

    # ── Recuperation API ────────────────────────────────────────────────────────
    Write-Host "  🌐 RECUPERATION API" -ForegroundColor White
    Write-Host "  ─────────────────────────────────────────────────────────────" -ForegroundColor DarkGray

    foreach ($product in $Products) {
        Write-Host "  ⏳ " -ForegroundColor Yellow -NoNewline
        Write-Host $product.PadRight(20) -ForegroundColor Gray -NoNewline

        $apiData = Invoke-EoLAPI -Product $product

        if ($apiData) {
            Write-Verbose "API retournee: $($apiData.Count) cycles"
            $count = 0

            $macOSNames = @{ '10.15'='Catalina'; '11'='Big Sur'; '12'='Monterey'; '13'='Ventura'; '14'='Sonoma'; '15'='Sequoia' }

            # ── Déduplication : plusieurs cycles API peuvent se normaliser vers le même osName
            # Exemple : '2003' et '2003-sp1' -> 'Windows Server 2003' avec des dates différentes
            # -> rotation infinie à chaque appel (A détecte changement de B, B détecte changement de A)
            # Solution : pour chaque osName en collision, ne garder que le cycle avec eol_date la plus tardive
            $cycleByName = @{}
            foreach ($c in $apiData) {
                $n = $c.cycle
                if ($product -eq 'windows-server') {
                    $n = $n -replace '-r2-sp\d+$',' R2' -replace '-r2$',' R2' -replace '-sp\d+$','' 
                    $n = "Windows Server $($n.Trim())"
                } elseif ($product -eq 'windows') {
                    $n = "Windows $n"
                } elseif ($product -eq 'macos') {
                    $mn = $macOSNames[$c.cycle]
                    $n  = if ($mn) { "macOS $($c.cycle) $mn" } else { "macOS $($c.cycle)" }
                } else { $n = "$product $n" }

                if ($cycleByName.ContainsKey($n)) {
                    # Garder le cycle avec la eol_date la plus tardive
                    $existing = $cycleByName[$n]
                    $existEol = if ($existing.eol -and $existing.eol -isnot [bool]) { [string]$existing.eol } else { '' }
                    $newEol   = if ($c.eol       -and $c.eol       -isnot [bool]) { [string]$c.eol       } else { '' }
                    if ($newEol -gt $existEol) { $cycleByName[$n] = $c }
                } else {
                    $cycleByName[$n] = $c
                }
            }
            # Remplacer apiData par la liste dédupliquée
            $apiData = $cycleByName.Values

            foreach ($cycle in $apiData) {
                if ($product -eq "windows") {
                    $osName = "Windows $($cycle.cycle)"
                } elseif ($product -eq "windows-server") {
                    # L'API endoflife.date retourne des cycles avec tirets et suffixes SP :
                    # ex: "2008-r2-sp1" → "2012-r2" → mais AD et Normalize-OperatingSystem
                    # produisent "Windows Server 2008 R2" / "Windows Server 2012 R2" (espaces, sans -sp1/sp2).
                    # On normalise ici pour que la clé en base corresponde exactement à OS_Full.
                    $serverCycle = $cycle.cycle
                    $serverCycle = $serverCycle -replace '-r2-sp\d+$', ' R2'   # 2008-r2-sp1 → "2008 R2"
                    $serverCycle = $serverCycle -replace '-r2$',       ' R2'   # 2012-r2     → "2012 R2"
                    $serverCycle = $serverCycle -replace '-sp\d+$',    ''      # 2008-sp2    → "2008"
                    $serverCycle = $serverCycle.Trim()
                    $osName = "Windows Server $serverCycle"
                } elseif ($product -eq "macos") {
                    $macName = $macOSNames[$cycle.cycle]
                    $osName  = if ($macName) { "macOS $($cycle.cycle) $macName" } else { "macOS $($cycle.cycle)" }
                } else {
                    $osName = "$product $($cycle.cycle)"
                }

                $productName = if ($product -eq "windows")        { "Windows" }
                              elseif ($product -eq "windows-server") { "Windows Server" }
                              elseif ($product -eq "macos")          { "macOS" }
                              else { (Get-Culture).TextInfo.ToTitleCase($product) }

                $mapKey = $script:OSFamilyMap.Keys | Where-Object { $_ -ieq $productName } | Select-Object -First 1
                $osType = if ($mapKey) { $script:OSFamilyMap[$mapKey].ToLower() }
                          elseif ($product -eq "windows-server") { "server" }
                          else { "client" }
                # Uniformisation : les distros Linux ont type="linux" dans les stubs PreCheck.
                # OSFamilyMap retourne "server" pour Ubuntu/Debian/RHEL/SLES -> normaliser ici
                # pour garantir la cohérence de la base JSON (même valeur partout pour un même OS).
                $linuxProducts = @("ubuntu","debian","rhel","sles","fedora","centos","alpine","rocky","almalinux")
                if ($linuxProducts -contains $product.ToLower()) { $osType = "linux" }

                # Normaliser les dates en ISO yyyy-MM-dd dès la construction de l'entrée
                # pour éviter que Invoke-RestMethod ne stocke des DateTime locale en DB
                $toIsoRaw = {
                    param($v)
                    if ($null -eq $v -or $v -eq $false -or $v -eq '' -or $v -eq 'False') { return $null }
                    if ($v -is [datetime]) { return $v.ToString('yyyy-MM-dd') }
                    return [string]$v
                }
                $osEntry = @{
                    product_name     = $productName
                    version          = $cycle.cycle
                    type             = $osType
                    eol_date         = (& $toIsoRaw $cycle.eol)
                    extended_support = (& $toIsoRaw $cycle.extendedSupport)
                    api_product      = $product
                    api_cycle        = $cycle.cycle
                }

                $isNew = $false; $hasChanged = $false

                # Chercher l'entrée existante — 3 stratégies par ordre de priorité :
                # 1. Nom exact normalisé (cas nominal)
                # 2. Ancien nom brut API (migration bases pré-FIX7a)
                # 3. Recherche par api_cycle (cas macOS 10.13/10.14 sans nom marketing en DB,
                #    ou tout autre cycle dont le nom affiché a changé entre deux versions)
                $existingKey = $null
                if ($database.os_database.PSObject.Properties.Name -contains $osName) {
                    $existingKey = $osName
                } else {
                    # Stratégie 2 : ancien nom brut API
                    $legacyName = "$(if ($product -eq 'windows-server') { 'Windows Server' } else { $product }) $($cycle.cycle)"
                    if ($legacyName -ne $osName -and
                        $database.os_database.PSObject.Properties.Name -contains $legacyName) {
                        $existingKey = $legacyName
                    }
                }
                # Stratégie 3 : recherche par api_product + api_cycle (filet de sécurité)
                if (-not $existingKey) {
                    foreach ($prop in $database.os_database.PSObject.Properties) {
                        if ($prop.Value.api_product -eq $product -and
                            $prop.Value.api_cycle   -eq $cycle.cycle) {
                            $existingKey = $prop.Name
                            break
                        }
                    }
                }

                if ($existingKey) {
                    $oldEntry = $database.os_database.$existingKey
                    # Normalisation ISO avant comparaison :
                    # Invoke-RestMethod peut parser certaines dates en DateTime selon la locale Windows.
                    # [string]DateTime = "10/13/2026 00:00:00" (locale) != "2026-10-13" (ISO DB)
                    # -> on force le format yyyy-MM-dd pour les deux côtés.
                    $toIso = {
                        param($v)
                        if ($null -eq $v -or $v -eq $false -or $v -eq '' -or $v -eq 'False') { return '' }
                        if ($v -is [datetime]) { return $v.ToString('yyyy-MM-dd') }
                        # String déjà en ISO ou autre format -> retourner tel quel
                        return [string]$v
                    }
                    $oldEol = & $toIso $oldEntry.eol_date
                    $newEol = & $toIso $osEntry.eol_date
                    $oldExt = & $toIso $oldEntry.extended_support
                    $newExt = & $toIso $osEntry.extended_support
                    if ($oldEol -ne $newEol -or $oldExt -ne $newExt) {
                        $hasChanged = $true
                    }
                    # Normaliser aussi les valeurs stockées pour éviter les rechargements futurs
                    $osEntry.eol_date         = $newEol
                    $osEntry.extended_support = if ($newExt -eq '') { $null } else { $newExt }
                    # Supprimer l'ancienne clé (qu'elle soit l'ancienne ou la même)
                    $database.os_database.PSObject.Properties.Remove($existingKey)
                } else { $isNew = $true }

                $database.os_database | Add-Member -MemberType NoteProperty -Name $osName -Value $osEntry -Force
                if ($isNew -or $hasChanged) { $count++ }
            }

            if ($count -gt 0) {
                Write-Host "✓  " -ForegroundColor Green -NoNewline
                Write-Host "$count modification(s)" -ForegroundColor Green
            } else {
                Write-Host "✓  " -ForegroundColor DarkGreen -NoNewline
                Write-Host "A jour" -ForegroundColor DarkGray
            }
            $updateCount += $count

        } else {
            Write-Host "✗  Echec API" -ForegroundColor Red
            $errorCount++
        }
    }

    # ── Couverture OS : PreCheck ou équivalent ─────────────────────────────────
    # Si aucun fichier PreCheck disponible, on lance Test-OSInEoLDatabase
    # (même logique que PreCheck, source canonique unique) pour détecter les OS
    # du domaine absents de la base, et générer le fichier ModernAD-MissingOS.json.
    # Cette étape se fait AVANT la sauvegarde pour que les OS soient intégrés.
    $database.metadata.last_updated = Get-Date -Format "yyyy-MM-dd"
    $missingOSFile = Join-Path $env:TEMP "ModernAD-MissingOS.json"

    # Analyse couverture OS : uniquement si base NOUVELLE (premier lancement)
    # ou si un fichier PreCheck est présent (laissé par Invoke-ADReportPreCheck)
    # → jamais lors d'un Update-ADEoLDatabase normal sur une base existante
    if ($isNewDatabase -and -not (Test-Path $missingOSFile)) {
        Write-Host ""
        Write-Host "  🖥  ANALYSE COUVERTURE OS (equivalent PreCheck)" -ForegroundColor White
        Write-Host "  ─────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
        Write-Host "  ⏳ Interrogation de l'annuaire Active Directory..." -ForegroundColor Gray

        # Alimenter le cache avec la base déjà construite en mémoire
        # pour éviter les warnings "fichier introuvable" dans Get-OSEoLInfo
        $script:EoLDatabaseCache = $database

        $osCheck = Test-OSInEoLDatabase -DaysBeforeWarning 90 -DatabaseOverride $database

        if ($osCheck.Status -eq "ERROR") {
            Write-Host "  ⚠ " -ForegroundColor Yellow -NoNewline
            Write-Host $osCheck.Message -ForegroundColor Yellow
        } elseif ($osCheck.MissingOS.Count -gt 0) {
            Write-Host "  ⚠ " -ForegroundColor Yellow -NoNewline
            Write-Host "$($osCheck.MissingOS.Count) OS detectes dans AD non references dans la base" -ForegroundColor Yellow
            # Sauvegarder pour la phase d'intégration ci-dessous
            try {
                $osCheck.MissingOS | ConvertTo-Json -Depth 5 |
                    Set-Content -Path $missingOSFile -Encoding UTF8 -ErrorAction Stop
            } catch {
                Write-Host "  ⚠ Impossible de sauvegarder la liste : $($_.Exception.Message)" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  ✓ " -ForegroundColor DarkGreen -NoNewline
            Write-Host "Tous les OS du domaine sont references dans la base" -ForegroundColor DarkGray
        }
    }

    # S'assurer que le cache pointe sur $database (enrichi par API, pas encore sur disque)
    $script:EoLDatabaseCache = $database

    if (Test-Path $missingOSFile) {
        Write-Host ""
        $fromPreCheck = $true   # le fichier existait avant notre analyse = vient d'un vrai PreCheck
        Write-Host "  🖥  INTEGRATION OS MANQUANTS" -ForegroundColor White
        Write-Host "  ─────────────────────────────────────────────────────────────" -ForegroundColor DarkGray

        try {
            $missingOSList = Get-Content $missingOSFile -Raw | ConvertFrom-Json
            Write-Host "  ⏳ " -ForegroundColor Yellow -NoNewline
            Write-Host "$($missingOSList.Count) OS a integrer..." -ForegroundColor Gray

            $addedCount = 0
            foreach ($item in $missingOSList) {
                $os = $item.OS
                if ($os -eq "unknown" -or -not $os) { continue }

                $exists = $false
                foreach ($prop in $database.os_database.PSObject.Properties) {
                    if ($prop.Name -eq $os) { $exists = $true; break }
                }

                if ($exists -eq $false) {
                    $existingInfo = Get-OSEoLInfo -OSName $os
                    if ($existingInfo -and $existingInfo.eol_date) {
                        $database.os_database | Add-Member -MemberType NoteProperty -Name $os -Value $existingInfo -Force
                        Write-Host "    ↪ " -ForegroundColor DarkCyan -NoNewline
                        Write-Host "$os".PadRight(44) -ForegroundColor Gray -NoNewline
                        Write-Host "alias resolu → eol_date $($existingInfo.eol_date)" -ForegroundColor DarkCyan
                        $addedCount++
                        continue
                    }
                }

                if (-not $exists) {
                    Write-Host "    ▪ " -ForegroundColor DarkGray -NoNewline
                    Write-Host $os.PadRight(44) -ForegroundColor Gray -NoNewline
                    Write-Host "$($item.Count) machine(s)" -ForegroundColor DarkYellow

                    $productName = "Unknown"; $osType = "client"; $version = "N/A"
                    if      ($os -like "*Windows Server*") { $productName = "Windows Server"; $osType = "server" }
                    elseif  ($os -like "*Windows*")        { $productName = "Windows";        $osType = "client" }
                    elseif  ($os -like "*Ubuntu*")         { $productName = "Ubuntu";         $osType = "linux"  }
                    elseif  ($os -like "*Debian*")         { $productName = "Debian";         $osType = "linux"  }
                    elseif  ($os -like "*Red Hat*" -or $os -like "*RHEL*") { $productName = "RHEL";  $osType = "linux" }
                    elseif  ($os -like "*SUSE*"   -or $os -like "*SLES*")  { $productName = "SLES";  $osType = "linux" }
                    elseif  ($os -like "*macOS*"  -or $os -like "*Mac OS*"){ $productName = "macOS"; $osType = "client" }

                    if ($os -match '(\d{4}(?:\.\d+)?|\d{2}\.\d{2}(?:\.\d+)?|\d+)') { $version = $matches[1] }

                    $osEntry = @{
                        product_name     = $productName
                        version          = $version
                        type             = $osType
                        eol_date         = $null
                        extended_support = $null
                        api_product      = "ad-detected"
                        api_cycle        = "unknown"
                    }
                    $database.os_database | Add-Member -MemberType NoteProperty -Name $os -Value $osEntry -Force
                    $addedCount++
                }
            }

            if ($addedCount -gt 0) {
                Write-Host "  ✓ " -ForegroundColor Green -NoNewline
                Write-Host "$addedCount OS ajoutes a la base" -ForegroundColor Green
                $updateCount += $addedCount
            } else {
                Write-Host "  ✓ " -ForegroundColor DarkGreen -NoNewline
                Write-Host "Tous les OS etaient deja references" -ForegroundColor DarkGray
            }

            Remove-Item $missingOSFile -Force -ErrorAction SilentlyContinue

        } catch {
            Write-Host "  ⚠ Impossible de lire la liste des OS manquants : $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

        # ── Sauvegarde ──────────────────────────────────────────────────────────────
    $database.metadata.last_api_update = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

    Write-Host ""
    Write-Host "  💾 SAUVEGARDE" -ForegroundColor White
    Write-Host "  ─────────────────────────────────────────────────────────────" -ForegroundColor DarkGray

    try {
        $database | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath -Encoding UTF8 -ErrorAction Stop
        Clear-EoLDatabaseCache
        $null = Get-EoLDatabase -ForceReload

        Write-Host "  ✓ " -ForegroundColor Green -NoNewline
        Write-Host "Base sauvegardee" -ForegroundColor Green -NoNewline
        Write-Host "  ($jsonPath)" -ForegroundColor DarkGray

        Write-Host ""
        Write-Host "  #=======================================================================" -ForegroundColor DarkCyan

        if ($updateCount -gt 0) {
            Write-Host ""
            Write-Host "  ✓ $updateCount modification(s) appliquee(s)" -ForegroundColor Green -NoNewline
            if ($errorCount -gt 0) { Write-Host "   ⚠ $errorCount erreur(s)" -ForegroundColor Yellow }
            else { Write-Host "" }
        } else {
            Write-Host ""
            Write-Host "  ✓ Base deja a jour — aucune modification necessaire" -ForegroundColor DarkGray
        }

        Write-Host ""
        Write-Host "  >> Pour generer le rapport avec les nouvelles donnees :" -ForegroundColor DarkGray
        Write-Host "     Get-MADReport -UnlimitedSearch -SavePath 'C:\Reports'" -ForegroundColor DarkCyan
        Write-Host ""

    } catch {
        Write-Error "Erreur lors de la sauvegarde : $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
Recherche et ajoute les OS manquants détectés dans AD.

.DESCRIPTION
Compare les OS trouvés dans AD avec la base JSON et propose d'ajouter les manquants via l'API.

.PARAMETER DetectedOSList
Liste des OS détectés dans AD

.PARAMETER Interactive
Mode interactif - demande confirmation avant chaque ajout

.EXAMPLE
Search-MissingOSInAPI -DetectedOSList $osListFromAD -Interactive
#>
function Search-MissingOSInAPI {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$DetectedOSList,
        
        [Parameter(Mandatory = $false)]
        [switch]$Interactive
    )
    
    Write-Host "🔍 Recherche des OS manquants dans la base EoL..." -ForegroundColor Cyan
    
    $database = Get-EoLDatabase
    if (-not $database) {
        Write-Error "Impossible de charger la base de données EoL"
        return
    }
    
    $missingOS = @()
    
    foreach ($os in $DetectedOSList) {
        if (-not $os) { continue }
        
        $osInfo = Get-OSEoLInfo -OSName $os
        if (-not $osInfo) {
            $missingOS += $os
        }
    }
    
    if ($missingOS.Count -eq 0) {
        Write-Host "✅ Tous les OS détectés sont présents dans la base" -ForegroundColor Green
        return
    }
    
    Write-Host "⚠️  $($missingOS.Count) OS manquant(s) détecté(s):" -ForegroundColor Yellow
    $missingOS | ForEach-Object { Write-Host "   - $_" -ForegroundColor Gray }
    
    if ($Interactive) {
        Write-Host ""
        Write-Host "Recherche dans l'API endoflife.date pour ces OS..." -ForegroundColor Cyan
        
        foreach ($os in $missingOS) {
            Write-Host ""
            Write-Host "OS: $os" -ForegroundColor White
            
            # Tentative de détection du produit
            $suggestedProduct = $null
            if ($os -like "*Windows Server*") {
                $suggestedProduct = "windows-server"
            } elseif ($os -like "*Windows*") {
                $suggestedProduct = "windows"
            } elseif ($os -like "*Ubuntu*") {
                $suggestedProduct = "ubuntu"
            }
            
            if ($suggestedProduct) {
                Write-Host "Produit suggéré: $suggestedProduct" -ForegroundColor Gray
                $response = Read-Host "Rechercher dans l'API pour ce produit? (O/N)"
                
                if ($response -eq "O" -or $response -eq "o") {
                    $apiData = Invoke-EoLAPI -Product $suggestedProduct
                    if ($apiData) {
                        Write-Host "Cycles disponibles:" -ForegroundColor Green
                        $apiData | Select-Object -First 5 | ForEach-Object {
                            Write-Host "  - $($_.cycle) (EoL: $($_.eol))" -ForegroundColor Gray
                        }
                    }
                }
            } else {
                Write-Host "Impossible de suggérer un produit API automatiquement" -ForegroundColor Yellow
                Write-Host "Consultez: https://endoflife.date/docs/api/" -ForegroundColor Gray
            }
        }
    } else {
        Write-Host ""
        Write-Host "💡 Pour rechercher ces OS dans l'API, utilisez:" -ForegroundColor Yellow
        Write-Host "   Search-MissingOSInAPI -DetectedOSList `$list -Interactive" -ForegroundColor Gray
    }
}

#endregion

#region Fonction d'export

<#
.SYNOPSIS
Exporte la base de données EoL actuelle.

.DESCRIPTION
Crée une copie de sauvegarde ou exporte la base dans un autre format.

.PARAMETER OutputPath
Chemin du fichier de sortie

.EXAMPLE
Export-EoLDatabase -OutputPath "C:\Backup\eol-backup.json"
#>
function Export-EoLDatabase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )
    
    $database = Get-EoLDatabase
    if (-not $database) {
        Write-Error "Impossible de charger la base de données"
        return
    }
    
    try {
        $database | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputPath -Encoding UTF8
        Write-Host "✅ Base exportée vers: $OutputPath" -ForegroundColor Green
    } catch {
        Write-Error "Erreur lors de l'export: $($_.Exception.Message)"
    }
}


<#
.SYNOPSIS
Analyse les OS présents dans AD et identifie ceux absents de la base EoL.

.DESCRIPTION
Interroge Active Directory, normalise les noms OS (avec Normalize-OperatingSystem si disponible,
sinon fallback interne), puis compare avec la base EoL.
Utilisée par PreCheck ET par Update-ADEoLDatabase (logique unique, source canonique).

.PARAMETER DaysBeforeWarning
Seuil en jours pour le statut d'avertissement (défaut: 90)

.PARAMETER DatabaseOverride
Optionnel : passer directement un objet $database en cours de construction
(évite les lectures disque et warnings quand la DB n'est pas encore sauvegardée)

.OUTPUTS
PSCustomObject { Status, Message, MissingOS, FoundOS, TotalOSDetected, CoveragePercent, Details }
#>
function Test-OSInEoLDatabase {
    param(
        [int]$DaysBeforeWarning = 90,
        [object]$DatabaseOverride = $null
    )
    try {
        if (-not (Get-Command -Name 'Get-ADComputer' -ErrorAction SilentlyContinue)) {
            return [PSCustomObject]@{
                Status          = "ERROR"
                Message         = "Module ActiveDirectory non disponible"
                MissingOS       = @()
                TotalOSDetected = 0
            }
        }

        $computers = Get-ADComputer -Filter * -Properties OperatingSystem,OperatingSystemVersion -ResultSetSize $null

        # Utiliser le DatabaseOverride si fourni (base en cours de construction, pas encore sur disque)
        # sinon charger depuis le cache/disque normalement
        if ($DatabaseOverride) {
            $script:EoLDatabaseCache = $DatabaseOverride
        }
        $database = Get-EoLDatabase
        if (-not $database) {
            return [PSCustomObject]@{
                Status          = "ERROR"
                Message         = "Base de donnees EoL non trouvee"
                MissingOS       = @()
                TotalOSDetected = 0
            }
        }

        $buildMap = @{
            '10240'='1507';'10586'='1511';'14393'='1607';'15063'='1703';'16299'='1709'
            '17134'='1803';'17763'='1809';'18362'='1903';'18363'='1909'
            '19041'='2004';'19042'='20H2';'19043'='21H1';'19044'='21H2';'19045'='22H2'
            '22000'='21H2';'22621'='22H2';'22631'='23H2';'26100'='24H2'
        }

        $computersWithFull = $computers | Where-Object { $_.OperatingSystem } | ForEach-Object {
            $rawOS  = $_.OperatingSystem.Trim()
            $rawVer = if ($_.OperatingSystemVersion) { $_.OperatingSystemVersion.Trim() } else { '' }
            $osFull = $null

            if (Get-Command -Name 'Normalize-OperatingSystem' -ErrorAction SilentlyContinue) {
                $norm   = Normalize-OperatingSystem -OperatingSystem $rawOS -OperatingSystemVersion $rawVer
                $osFull = if ($norm.Release) { "$($norm.Product) $($norm.Release)" } else { $norm.Product }
            } else {
                $build = $null
                if ($rawVer -match '^\s*\d+\.\d+\s*\((\d+)\)') { $build = $matches[1] }

                if ($rawOS -match '^Windows (10|11)') {
                    $winVer  = $matches[1]
                    $release = if ($build) { $buildMap[$build] } else { $null }
                    $osFull  = if ($release) { "Windows $winVer $release" } else { "Windows $winVer" }
                } elseif ($rawOS -match '^Windows Server\s+(2008 R2|2012 R2|2025|2022|2019|2016|2012|2008|2003)') {
                    $osFull = "Windows Server $($matches[1])"
                } elseif ($rawOS -match '^(Mac\s*OS\s*X|macOS)') {
                    $macNames = @{'10.15'='Catalina';'10.14'='Mojave';'10.13'='High Sierra'
                                  '11'='Big Sur';'12'='Monterey';'13'='Ventura';'14'='Sonoma';'15'='Sequoia'}
                    $allText = "$rawOS $rawVer"
                    if ($allText -match '(Sequoia|Sonoma|Ventura|Monterey|Big\s*Sur|Catalina|Mojave|High\s*Sierra)') {
                        $name  = $matches[1] -replace '\s+',' '
                        $cycle = ($macNames.GetEnumerator() | Where-Object { $_.Value -eq $name } | Select-Object -First 1).Key
                        $osFull = if ($cycle) { "macOS $cycle $name" } else { "macOS $name" }
                    } elseif ($allText -match '(?<!\d)(1[1-9]|\d{2,})(?:\.\d+)?(?!\d)') {
                        $major = [int]($matches[0] -replace '\..*','')
                        $name  = $macNames[$major]
                        $osFull = if ($name) { "macOS $major $name" } else { "macOS $major" }
                    } else { $osFull = "macOS" }
                } elseif ($rawOS -match '(Ubuntu|Debian|CentOS|Red\s*Hat|RHEL|SUSE|SLES|Fedora)') {
                    $prod = switch -Regex ($matches[1]) {
                        'Red\s*Hat|RHEL' { 'RHEL' }
                        default           { $matches[1] }
                    }
                    if      ($rawOS -match '(?:RHEL|Red\s*Hat[^\d]*|CentOS[^\d]*|Debian[^\d]*|Fedora[^\d]*)(\d{1,2})(?:\.\d+)?') { $osFull = "$prod $($matches[1])" }
                    elseif  ($rawOS -match '(Ubuntu|SUSE|SLES)\s+(\d{2}\.\d{2})')                                                 { $osFull = "$prod $($matches[2])" }
                    elseif  ($rawVer -match '^(\d{1,2})(?:\.\d+)?$')                                                              { $osFull = "$prod $($matches[1])" }
                    else    { $osFull = $prod }
                } else {
                    $osFull = $rawOS
                }
            }
            [PSCustomObject]@{ Computer = $_.Name; RawOS = $rawOS; OS_Full = $osFull.Trim() }
        }

        $osGroups   = $computersWithFull | Group-Object OS_Full
        $detectedOS = $osGroups | Select-Object -ExpandProperty Name | Sort-Object
        $missingOS  = @()
        $foundOS    = @()
        $osDetails  = @()

        foreach ($osGroup in $osGroups) {
            $os     = $osGroup.Name
            $count  = $osGroup.Count
            $osInfo = Get-OSEoLInfo -OSName $os
            if ($osInfo) {
                $foundOS   += $os
                $osDetails += [PSCustomObject]@{ OS=$os; Count=$count; Found=$true;
                    Status=(Get-OSEoLStatus -OSName $os -DaysBeforeWarning $DaysBeforeWarning)
                    EoLDate=$osInfo.eol_date }
            } else {
                $missingOS += [PSCustomObject]@{ OS = $os; Count = $count }
                $osDetails += [PSCustomObject]@{ OS=$os; Count=$count; Found=$false; Status="Unknown"; EoLDate="N/A" }
            }
        }

        $coveragePercent = if ($detectedOS.Count -gt 0) {
            [math]::Round(($foundOS.Count / $detectedOS.Count) * 100, 1)
        } else { 100 }

        return [PSCustomObject]@{
            Status          = if ($missingOS.Count -eq 0) { "OK" } else { "WARNING" }
            Message         = if ($missingOS.Count -eq 0) { "Tous les OS sont dans la base EoL" } else { "$($missingOS.Count) OS manquants dans la base EoL" }
            MissingOS       = $missingOS
            FoundOS         = $foundOS
            TotalOSDetected = $detectedOS.Count
            CoveragePercent = $coveragePercent
            Details         = $osDetails
        }
    } catch {
        return [PSCustomObject]@{ Status = "ERROR"; Message = $_.Exception.Message; MissingOS = @() }
    }
}

#region Fonctions de mapping AD -> EoL (déplacées depuis MAD-EoL.ps1 — B06 fix)

<#
.SYNOPSIS
Retourne les informations EoL d'un ordinateur AD en résolvant sa clé dans la base EoL.

.DESCRIPTION
Calcule la clé EoL à partir des propriétés OS_Product, OS_Release et Operating System
de l'objet computer enrichi par MAD-Computers.ps1, puis interroge la base via Get-EoLDatabase.
Remplace la version précédente qui dépendait des variables de contexte $EoL_Base/$EoL_Extended.

.PARAMETER Computer
Objet PSCustomObject issu de $ComputersTable (doit avoir : Vendor, Family, OS_Product, OS_Release, 'Operating System')

.PARAMETER DaysBeforeEoL
Seuil en jours pour le statut d'avertissement (transmis par $DaysBeforeEoL du psm1)

.OUTPUTS
PSCustomObject { Key, EoL, Days, Status, EoL_ExtendedType, EoL_ExtendedEnd } ou $null
#>
function Get-ComputerEoLInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [pscustomobject]$Computer,

        [Parameter(Mandatory=$false)]
        [int]$DaysBeforeEoL = 90
    )

    # --- Charger la base via le cache Get-EoLDatabase (zero relecture disque si déjà en mémoire) ---
    $db = Get-EoLDatabase
    if (-not $db) { return $null }

    # Construire les hashtables $EoL_Base et $EoL_Extended depuis la base
    $EoL_Base     = @{}
    $EoL_Extended = @{}
    foreach ($prop in $db.os_database.PSObject.Properties) {
        $entry = $prop.Value
        if ($entry.eol_date)         { $EoL_Base[$prop.Name]     = $entry.eol_date }
        if ($entry.extended_support -and $entry.extended_support -ne 'N/A') {
            $EoL_Extended[$prop.Name] = @{ Type = 'Extended'; End = $entry.extended_support }
        }
    }

    $prod    = $Computer.OS_Product
    $release = $Computer.OS_Release
    $raw     = $Computer.'Operating System'
    $osver   = $Computer.'Operating System Version'   # ex: "22.04" ou "22.04.1"

    $key             = $null
    $editionUndefined = $false

    if ($Computer.Vendor -eq 'Microsoft' -and $Computer.Family -eq 'Client') {
        if (($prod -eq 'Windows 10' -or $prod -eq 'Windows 11') -and $release) {
            $relLower = $release.ToLower()
            $prefix   = if ($prod -eq 'Windows 10') { 'Windows 10' } else { 'Windows 11' }

            if    ($raw -match 'LTSC')                              { $key = "$prefix-$relLower-e-lts" }
            elseif($raw -match 'IoT')                               { $key = "$prefix-$relLower-iot-lts" }
            elseif($raw -match 'Enterprise')                        { $key = "$prefix-$relLower-e" }
            elseif($raw -match 'Pro|Professional|Professionnel')    { $key = "$prefix-$relLower-w" }
            else {
                $editionUndefined = $true
                $keyW    = "$prefix-$relLower-w"
                $keyBase = "$prefix-$relLower"
                $key = if ($EoL_Base.ContainsKey($keyW)) { $keyW } else { $keyBase }
            }

            if ($key -and -not $EoL_Base.ContainsKey($key)) {
                $editionUndefined = $true
                $keyBase = "$prefix-$relLower"
                $key = if ($EoL_Base.ContainsKey($keyBase)) { $keyBase } else { $null }
            }
        }
        elseif ($prod -eq 'Windows XP')  { $key = 'Windows 5-sp3' }
        elseif ($prod -eq 'Windows 7')   { $key = 'Windows 7-sp1' }
        elseif ($prod -eq 'Windows 8')   { $key = 'Windows 8' }
        elseif ($prod -eq 'Windows 8.1') { $key = 'Windows 8.1' }
    }
    elseif ($Computer.Vendor -eq 'Microsoft' -and $Computer.Family -eq 'Server') {
        $cleanProd = if ($prod) { $prod.Trim() } else { '' }
        if     ($cleanProd -eq 'Windows Server 2025')       { $key = 'Windows Server 2025' }
        elseif ($cleanProd -eq 'Windows Server 2022')       { $key = 'Windows Server 2022' }
        elseif ($cleanProd -eq 'Windows Server 2019')       { $key = 'Windows Server 2019' }
        elseif ($cleanProd -eq 'Windows Server 2016')       { $key = 'Windows Server 2016' }
        elseif ($cleanProd -match 'Windows Server 2012') {
            # FIX7a : la base stocke maintenant "Windows Server 2012 R2" (espaces) et non "Windows Server 2012-r2"
            $key = if ($cleanProd -match 'R2') { 'Windows Server 2012 R2' } else { 'Windows Server 2012' }
        }
        elseif ($cleanProd -match 'Windows Server 2008') {
            # FIX7a : "Windows Server 2008 R2" et "Windows Server 2008" (sans suffixe -sp1/-sp2)
            $key = if ($cleanProd -match 'R2') { 'Windows Server 2008 R2' } else { 'Windows Server 2008' }
        }
        elseif ($cleanProd -match 'Windows Server 2003') { $key = 'Windows Server 2003' }
        else { $key = $null }
    }
    elseif ($Computer.Vendor -eq 'Apple' -and $prod -eq 'macOS') {
        # Release = "14 Sonoma" ou "10.15 Catalina" (extrait par Normalize-OperatingSystem)
        # Clé DB = "macOS 14 Sonoma" ou "macOS 10.15 Catalina"
        if ($release) {
            $key = "macOS $release"
        }
    }
    elseif ($Computer.Vendor -eq 'Linux') {
        if ($prod -match 'Ubuntu') {
            # Release = "22.04" (extrait par Normalize-OperatingSystem depuis toutes les sources AD)
            if ($release) { $key = "ubuntu $release" }
        } elseif ($prod -match 'Debian') {
            if ($release) {
                # Release peut être "12", "12.4" → on prend la majeure
                $major = ($release -split '\.')[0]
                $key = "debian $major"
            }
        } elseif ($prod -match '^RHEL$' -or $raw -match 'Red Hat|RHEL') {
            if ($release) {
                $major = ($release -split '\.')[0]
                $key = "rhel $major"
            }
        } elseif ($prod -match 'SUSE|SLES') {
            if ($release -match '(\d+\.\d+)') { $key = "sles $($matches[1])" }
            elseif ($release) { $key = "sles $release" }
        } elseif ($prod -match 'Fedora') {
            if ($release) { $key = "fedora $release" }
        } elseif ($prod -match 'CentOS') {
            if ($release) {
                $major = ($release -split '\.')[0]
                $key = "centos $major"
            }
        }
    }

    # Récupérer les dates EoL base et extended
    $baseDate = $null
    if ($key -and $EoL_Base.ContainsKey($key)) { $baseDate = Get-Date $EoL_Base[$key] }

    $extType = $null; $extEnd = $null
    if ($key -and $EoL_Extended.ContainsKey($key)) {
        $extType = $EoL_Extended[$key].Type
        $extEnd  = Get-Date $EoL_Extended[$key].End
    }

    if ($null -ne $baseDate) {
        # Le STATUT est calculé sur la date effective la plus tardive :
        # si un extended_support valide existe (ESU/ESM/LTSS), il repousse la date d'expiration réelle.
        # Cela garantit la cohérence avec Get-OSEoLStatus (utilisé dans PreCheck).
        # La propriété EoL conserve la eol_date standard (support de base) pour l'affichage du tableau.
        $effectiveDate = $baseDate
        if ($null -ne $extEnd) {
            $extEntryRaw = if ($key) { $db.os_database.$key.extended_support } else { $null }
            $isValidExtDate = $extEntryRaw -and
                              $extEntryRaw -ne $false -and
                              $extEntryRaw -ne 'False' -and
                              $extEntryRaw -ne 'N/A' -and
                              $extEntryRaw -ne ''
            if ($isValidExtDate -and $extEnd -gt $baseDate) {
                $effectiveDate = $extEnd
            }
        }

        $days   = [int]((New-TimeSpan -Start (Get-Date).Date -End $effectiveDate.Date).TotalDays)
        $status = if ($days -lt 0) { 'EOL' } elseif ($days -le $DaysBeforeEoL) { "J-$DaysBeforeEoL" } else { 'Supported' }
        if ($editionUndefined -and -not $extType) { $extType = 'NotDefined' }
        return [pscustomobject]@{
            Key              = $key
            EoL              = $baseDate
            Days             = $days
            Status           = $status
            EoL_ExtendedType = $extType
            EoL_ExtendedEnd  = $extEnd
        }
    }

    # Clé trouvée en DB mais sans date EoL (eol_date=False/null) = encore supporté, date non annoncée
    if ($key) {
        $keyExistsInDB = $db.os_database.PSObject.Properties.Name -contains $key
        if ($keyExistsInDB) {
            return [pscustomobject]@{
                Key              = $key
                EoL              = $null
                Days             = $null
                Status           = 'Supported'
                EoL_ExtendedType = 'NoDateAnnounced'
                EoL_ExtendedEnd  = $null
            }
        }
    }

    return $null
}

<#
.SYNOPSIS
Normalise un tableau de statuts EoL en un objet structuré avec compteurs garantis.

.DESCRIPTION
Prend un tableau { Status, Count } et retourne un PSCustomObject avec les 4 statuts
(Supported, J-XX, EOL, Unknown) toujours présents (0 si absent).
Déplacée depuis MAD-EoL.ps1 pour centraliser la logique EoL dans ce module.

.PARAMETER Stats
Tableau PSCustomObject issu de Group-Object EoL_Status

.PARAMETER WarningStatusName
Nom dynamique du statut d'avertissement (ex: "J-90") — doit correspondre à $WarningStatusName du contexte
#>
function ConvertTo-StatusCounts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [array]$Stats,

        [Parameter(Mandatory=$false)]
        [string]$WarningStatusName = 'J-90'
    )
    $h = @{}
    foreach ($s in $Stats) { $h[$s.Status] = $s.Count }
    return [pscustomobject]@{
        Supported = $(if ($h.ContainsKey('Supported'))          { [int]$h['Supported'] }          else { 0 })
        J90       = $(if ($h.ContainsKey($WarningStatusName))   { [int]$h[$WarningStatusName] }   else { 0 })
        EOL       = $(if ($h.ContainsKey('EOL'))                { [int]$h['EOL'] }                else { 0 })
        Unknown   = $(if ($h.ContainsKey('Unknown'))            { [int]$h['Unknown'] }            else { 0 })
    }
}

#endregion

# L'alias Update-EoL est défini dans le PSM1 (→ Update-ADEoLDatabase)
# Ne pas le redéfinir ici pour éviter un conflit de cible au chargement du module.

#endregion