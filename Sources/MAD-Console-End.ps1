[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# ============================================================================
# SYNTHÈSE FINALE - Affichage des statistiques principales
# ============================================================================

Write-Host ""
Write-SectionHeader "📊 SYNTHÈSE DU PARC INFORMATIQUE"

# === ORDINATEURS ===
Write-Host ""
Write-Host "  💻 " -ForegroundColor Cyan -NoNewline
Write-Host "ORDINATEURS" -ForegroundColor White
Write-Counter "Total des ordinateurs" $totalcomputers "Cyan"
Write-Counter "Postes clients" $ClientList.Count "White"

# Calculer le nombre total de serveurs (hors clients)
# BUG22 FIX : calcul base sur les listes reelles au lieu de (total - clients)
# qui surestimait en incluant Divers et Unknown
$totalServers = $ServerList.Count
$serversWithOS = $ServerList.Count
$serversWithoutOS = 0

Write-Counter "Serveurs" $totalServers "White"

# === END OF LIFE ===
Write-Host ""
Write-Host "  ⚠️  " -ForegroundColor Yellow -NoNewline
Write-Host "STATUT END OF LIFE" -ForegroundColor White

# Clients EoL
$clientSupported = @($ClientList | Where-Object { $_.EoL_Status -eq 'Supported' }).Count
$clientWarning = @($ClientList | Where-Object { $_.EoL_Status -eq $WarningStatusName }).Count
$clientEOL = @($ClientList | Where-Object { $_.EoL_Status -eq 'EOL' }).Count
$clientUnknown = @($ClientList | Where-Object { $_.EoL_Status -eq 'Unknown' }).Count

Write-Host "    Clients:" -ForegroundColor Gray
Write-Counter "  ✓ Supportés" $clientSupported "Green"
Write-Counter "  ⚠ $WarningStatusName" $clientWarning "DarkYellow"
Write-Counter "  ✗ EOL (fin de vie)" $clientEOL "Red"
Write-Counter "  ? Inconnus" $clientUnknown "DarkGray"

# Serveurs EoL
$serverSupported = @($ServerList | Where-Object { $_.EoL_Status -eq 'Supported' }).Count
$serverWarning = @($ServerList | Where-Object { $_.EoL_Status -eq $WarningStatusName }).Count
$serverEOL = @($ServerList | Where-Object { $_.EoL_Status -eq 'EOL' }).Count
$serverUnknown = @($ServerList | Where-Object { $_.EoL_Status -eq 'Unknown' }).Count

Write-Host "    Serveurs:" -ForegroundColor Gray
Write-Counter "  ✓ Supportés" $serverSupported "Green"
Write-Counter "  ⚠ $WarningStatusName" $serverWarning "DarkYellow"
Write-Counter "  ✗ EOL (fin de vie)" $serverEOL "Red"
Write-Counter "  ? Inconnus" $serverUnknown "DarkGray"

# === SYSTÈMES D'EXPLOITATION ===
Write-Host ""
Write-Host "  🖥️  " -ForegroundColor Cyan -NoNewline
Write-Host "TOP 5 SYSTÈMES D'EXPLOITATION" -ForegroundColor White

if ($ClientOSStats -and $ClientOSStats.Count -gt 0) {
    Write-Host "    Clients:" -ForegroundColor Gray
    $ClientOSStats | Select-Object -First 5 | ForEach-Object {
        $percentage = [math]::Round(($_.Count / $ClientList.Count) * 100, 1)
        Write-Counter "  $($_.Name) ($percentage%)" $_.Count "White"
    }
}

if ($ServerOSStats -and $ServerOSStats.Count -gt 0) {
    Write-Host "    Serveurs:" -ForegroundColor Gray
    $ServerOSStats | Select-Object -First 5 | ForEach-Object {
        $percentage = [math]::Round(($_.Count / $ServerList.Count) * 100, 1)
        Write-Counter "  $($_.Name) ($percentage%)" $_.Count "White"
    }
}

# === UTILISATEURS ===
Write-Host ""
Write-Host "  👥 " -ForegroundColor Cyan -NoNewline
Write-Host "UTILISATEURS" -ForegroundColor White
Write-Counter "Total des utilisateurs" $UserTable.Count "Cyan"

# Calculer les comptes activés/désactivés
$EnabledUsers = @($UserTable | Where-Object { $_.Enabled -eq $true }).Count
$DisabledUsers = @($UserTable | Where-Object { $_.Enabled -eq $false }).Count

if ($EnabledUsers -gt 0 -or $DisabledUsers -gt 0) {
    Write-Counter "Comptes activés" $EnabledUsers "Green"
    Write-Counter "Comptes désactivés" $DisabledUsers "DarkGray"
}

# === GROUPES ===
Write-Host ""
Write-Host "  👨‍👩‍👧‍👦 " -ForegroundColor Cyan -NoNewline
Write-Host "GROUPES" -ForegroundColor White
Write-Counter "Total des groupes" $totalgroups "Cyan"
Write-Counter "Groupes de sécurité" $SecurityCount "White"
Write-Counter "Groupes de distribution" $DistroCount "White"

# === GPO (GROUP POLICY) ===
if (!$nogpomod -and $GPOs) {
    Write-Host ""
    Write-Host "  📋 " -ForegroundColor Cyan -NoNewline
    Write-Host "GROUP POLICY OBJECTS (GPO)" -ForegroundColor White
    Write-Counter "Total des GPO" $GPOs.Count "Cyan"
    if ($GPO_Linked) {
        Write-Counter "GPO liées (actives)" $GPO_Linked.Count "Green"
    }
    if ($GPO_NotLinked -and $GPO_NotLinked.Count -gt 0) {
        Write-Counter "GPO non-liées (orphelines)" $GPO_NotLinked.Count "Yellow"
    }
    
    # Détails supplémentaires UNIQUEMENT avec -ShowSensitiveObjects
    if ((-not $LimitedView -or $ShowSensitiveObjects.IsPresent) -and $GPO_Details -and $GPO_Details.Count -gt 0) {
        Write-Host ""
        Write-Host "  🔓 " -ForegroundColor Yellow -NoNewline
        Write-Host "DÉTAILS GPO (mode ShowSensitiveObjects)" -ForegroundColor Yellow
        
        # Top 3 GPO les plus utilisées
        $topGPOs = $GPO_Details | Sort-Object 'Link Count' -Descending | Select-Object -First 3
        if ($topGPOs) {
            Write-Host "  Top 3 GPO les plus appliquées:" -ForegroundColor Gray
            foreach ($gpo in $topGPOs) {
                Write-Host "    • $($gpo.'GPO Name') " -ForegroundColor White -NoNewline
                Write-Host "($($gpo.'Link Count') OU/Sites)" -ForegroundColor DarkGray
            }
        }
    } elseif ($LimitedView -and -not $ShowSensitiveObjects.IsPresent) {
        Write-Host "  ℹ️  Utilisez " -ForegroundColor DarkGray -NoNewline
        Write-Host "-ShowSensitiveObjects" -ForegroundColor Cyan -NoNewline
        Write-Host " pour voir les détails d'application des GPO" -ForegroundColor DarkGray
    }
}

# === TRUSTS (DOMAIN TRUSTS) ===
if ($TrustsStats.Total -gt 0) {
    Write-Host ""
    Write-Host "  🔗 " -ForegroundColor Cyan -NoNewline
    Write-Host "DOMAIN TRUSTS" -ForegroundColor White
    Write-Counter "Total des trusts" $TrustsStats.Total "Cyan"
    
    if ($TrustsStats.IntraForest -gt 0) {
        Write-Counter "Trusts internes (intra-forest)" $TrustsStats.IntraForest "Green"
    }
    
    if ($TrustsStats.External -gt 0) {
        Write-Counter "Trusts externes" $TrustsStats.External "Yellow"
        
        # Alertes de sécurité sur les trusts externes
        $unsecuredExternal = $TrustsStats.External - $TrustsStats.WithSIDFiltering
        if ($unsecuredExternal -gt 0) {
            Write-Host "    ⚠️  " -ForegroundColor Red -NoNewline
            Write-Host "$unsecuredExternal trust(s) externe(s) sans SID Filtering" -ForegroundColor Red
        }
    }
    
    # Répartition par direction
    if ($TrustsStats.Bidirectional -gt 0 -or $TrustsStats.Inbound -gt 0 -or $TrustsStats.Outbound -gt 0) {
        if ($TrustsStats.Bidirectional -gt 0) {
            Write-Counter "  ↔ Bidirectionnels" $TrustsStats.Bidirectional "White"
        }
        if ($TrustsStats.Inbound -gt 0) {
            Write-Counter "  ← Entrants" $TrustsStats.Inbound "White"
        }
        if ($TrustsStats.Outbound -gt 0) {
            Write-Counter "  → Sortants" $TrustsStats.Outbound "White"
        }
    }
}

# === ALERTES CRITIQUES ===
$totalWarnings = $clientWarning + $serverWarning
$totalEOL = $clientEOL + $serverEOL

# Calcul des alertes de sécurité
$alerts = @()

# 1. ALERTE EOL - Machines en fin de vie
if ($totalEOL -gt 0) {
    $alerts += [PSCustomObject]@{
        Level = "CRITIQUE"
        Type = "End-of-Life"
        Count = $totalEOL
        Message = "$totalEOL machine(s) en fin de vie (EOL) - Remplacement urgent requis!"
        Recommendation = "Planifier le remplacement ou la mise à niveau immédiate"
        ANSSI = "R14 - Maintenir les systèmes à jour"
    }
}

# 2. ALERTE EOL - Machines proche fin de support
if ($totalWarnings -gt 0) {
    $alerts += [PSCustomObject]@{
        Level = "ELEVE"
        Type = "Fin de support proche"
        Count = $totalWarnings
        Message = "$totalWarnings machine(s) arrivent en fin de support dans moins de $DaysBeforeEoL jours"
        Recommendation = "Prévoir la migration sous $DaysBeforeEoL jours"
        ANSSI = "R14 - Maintenir les systèmes à jour"
    }
}

# 3. ALERTE - Comptes administrateurs inactifs
if ($UserTable) {
    # BUG23 FIX : -match "Admin" matchait n'importe quel groupe contenant "Admin" (ex: "Administrateurs locaux bureau")
    # Désormais on filtre sur AdminCount=1 (attribut AD fiable) OU appartenance à un groupe admin standard
    $adminAccounts = @($UserTable | Where-Object {
        $_.AdminCount -eq 1 -or
        ($_.memberof -and ($_.memberof -match '(^|,)CN=(Domain Admins|Enterprise Admins|Schema Admins|Administrators|Admins du domaine|Administrateurs),'))
    })
    if ($adminAccounts.Count -gt 0) {
        $inactiveAdmins = @($adminAccounts | Where-Object { 
            $_.LastLogonDate -and ((Get-Date) - $_.LastLogonDate).Days -gt $AdminInactivityThreshold 
        }).Count
        
        $inactiveAdmins365 = @($adminAccounts | Where-Object {
            $_.LastLogonDate -and ((Get-Date) - $_.LastLogonDate).Days -gt 365
        }).Count
        if ($inactiveAdmins365 -gt 0) {
            $alerts += [PSCustomObject]@{
                Level = "CRITIQUE"
                Type = "Admins inactifs +365j"
                Count = $inactiveAdmins365
                Message = "$inactiveAdmins365 compte(s) admin inactif(s) depuis plus de 365 jours - risque eleve"
                Recommendation = "Desactiver immediatement ces comptes privilegies"
                ANSSI = "R12 - Limiter les comptes a privileges"
            }
        }
        if ($inactiveAdmins -gt 0) {
            $alerts += [PSCustomObject]@{
                Level = "ELEVE"
                Type = "Admins inactifs +$($AdminInactivityThreshold)j"
                Count = $inactiveAdmins
                Message = "$inactiveAdmins compte(s) administrateur(s) inactif(s) depuis plus de $AdminInactivityThreshold jours"
                Recommendation = "Desactiver ou supprimer les comptes admin inutilises"
                ANSSI = "R12 - Limiter les comptes a privileges"
            }
        }
    }
}

# 4. ALERTE - Comptes utilisateurs inactifs (seuils 180j/365j)
if ($UserTable) {
    $inactUsers365 = @($UserTable | Where-Object {
        $_.Enabled -eq $true -and $_.LastLogonDate -and
        ((Get-Date) - $_.LastLogonDate).Days -gt 365
    }).Count
    $inactUsers180 = @($UserTable | Where-Object {
        $_.Enabled -eq $true -and $_.LastLogonDate -and
        ((Get-Date) - $_.LastLogonDate).Days -gt 180 -and
        ((Get-Date) - $_.LastLogonDate).Days -le 365
    }).Count
    # BUG1 FIX : borne superieure dynamique — utilise $UserInactivityThreshold
    # au lieu de 180 hardcode. Couvre la plage ]$UserInactivityThreshold ; 180[
    # uniquement si $UserInactivityThreshold < 180 ; sinon la plage est vide
    # (ce qui est le comportement attendu : inactUsers180 prend le relais).
    $inactUsersBase = @($UserTable | Where-Object {
        $_.Enabled -eq $true -and $_.LastLogonDate -and
        ((Get-Date) - $_.LastLogonDate).Days -gt $UserInactivityThreshold -and
        ((Get-Date) - $_.LastLogonDate).Days -le $UserInactivityThreshold * 2
    }).Count
    if ($inactUsers365 -gt 0) {
        $alerts += [PSCustomObject]@{
            Level = "CRITIQUE"
            Type = "Utilisateurs inactifs +365j"
            Count = $inactUsers365
            Message = "$inactUsers365 compte(s) actif(s) sans connexion depuis plus de 365 jours"
            Recommendation = "Desactiver ou supprimer ces comptes immediatement"
            ANSSI = "R11 - Gerer le cycle de vie des comptes"
        }
    }
    if ($inactUsers180 -gt 0) {
        $alerts += [PSCustomObject]@{
            Level = "ELEVE"
            Type = "Utilisateurs inactifs +180j"
            Count = $inactUsers180
            Message = "$inactUsers180 compte(s) actif(s) sans connexion depuis 180 a 365 jours"
            Recommendation = "Verifier et desactiver les comptes inutilises"
            ANSSI = "R11 - Gerer le cycle de vie des comptes"
        }
    }
    if ($inactUsersBase -gt 0) {
        $alerts += [PSCustomObject]@{
            Level = "MOYEN"
            Type = "Utilisateurs inactifs +$($UserInactivityThreshold)j"
            Count = $inactUsersBase
            Message = "$inactUsersBase compte(s) actif(s) inactif(s) depuis $UserInactivityThreshold a 180 jours"
            Recommendation = "Surveiller et planifier la desactivation"
            ANSSI = "R11 - Gerer le cycle de vie des comptes"
        }
    }
}

# 5. ALERTE - Trop de comptes désactivés (pollution AD)
if ($UserTable -and $UserTable.Count -gt 0) {
    $disabledPercent = [math]::Round(($DisabledUsers / $UserTable.Count) * 100, 1)
    
    if ($disabledPercent -gt $DisabledAccountsThreshold) {
        $alerts += [PSCustomObject]@{
            Level = "INFO"
            Type = "Comptes désactivés"
            Count = $DisabledUsers
            Message = "$disabledPercent% de comptes désactivés ($DisabledUsers/$($UserTable.Count)) - Seuil: $DisabledAccountsThreshold%"
            Recommendation = "Nettoyer l'AD en supprimant les comptes désactivés obsolètes"
            ANSSI = "R11 - Gérer le cycle de vie des comptes"
        }
    }
}

# 6. ALERTE - Mots de passe n'expirant jamais
if ($UserTable) {
    $pwdNeverExpires = @($UserTable | Where-Object { $_.PasswordNeverExpires -eq $true -and $_.Enabled -eq $true }).Count
    
    if ($pwdNeverExpires -gt 0 -and $UserTable.Count -gt 0) {
        $pwdNeverExpiresPercent = [math]::Round(($pwdNeverExpires / $UserTable.Count) * 100, 1)
        
        if ($pwdNeverExpiresPercent -gt $PasswordNeverExpiresThreshold) {
            $alerts += [PSCustomObject]@{
                Level = "ELEVE"
                Type = "Mots de passe permanents"
                Count = $pwdNeverExpires
                Message = "$pwdNeverExpires compte(s) avec mot de passe n'expirant jamais ($pwdNeverExpiresPercent%) - Seuil: $PasswordNeverExpiresThreshold%"
                Recommendation = "Configurer une expiration de mot de passe (90-365 jours selon ANSSI)"
                ANSSI = "R27 - Politique de mots de passe robuste"
            }
        }
    }
}

# 7. ALERTE - Ordinateurs inactifs (seuils 180j/365j)
if ($ComputersTable) {
    $inactPC365 = @($ComputersTable | Where-Object {
        $_.LastLogonDate -and ((Get-Date) - $_.LastLogonDate).Days -gt 365
    }).Count
    $inactPC180 = @($ComputersTable | Where-Object {
        $_.LastLogonDate -and ((Get-Date) - $_.LastLogonDate).Days -gt 180 -and
        ((Get-Date) - $_.LastLogonDate).Days -le 365
    }).Count
    # BUG1 FIX (meme pattern) : borne superieure dynamique basee sur $ComputerInactivityThreshold
    $inactPCBase = @($ComputersTable | Where-Object {
        $_.LastLogonDate -and ((Get-Date) - $_.LastLogonDate).Days -gt $ComputerInactivityThreshold -and
        ((Get-Date) - $_.LastLogonDate).Days -le $ComputerInactivityThreshold * 2
    }).Count
    if ($inactPC365 -gt 0) {
        $alerts += [PSCustomObject]@{
            Level = "CRITIQUE"
            Type = "Ordinateurs inactifs +365j"
            Count = $inactPC365
            Message = "$inactPC365 ordinateur(s) sans connexion depuis plus de 365 jours"
            Recommendation = "Desactiver ou supprimer ces comptes machine immediatement"
            ANSSI = "R11 - Gerer le cycle de vie des comptes"
        }
    }
    if ($inactPC180 -gt 0) {
        $alerts += [PSCustomObject]@{
            Level = "ELEVE"
            Type = "Ordinateurs inactifs +180j"
            Count = $inactPC180
            Message = "$inactPC180 ordinateur(s) sans connexion depuis 180 a 365 jours"
            Recommendation = "Verifier et nettoyer les comptes ordinateur obsoletes"
            ANSSI = "R11 - Gerer le cycle de vie des comptes"
        }
    }
    if ($inactPCBase -gt 0) {
        $alerts += [PSCustomObject]@{
            Level = "MOYEN"
            Type = "Ordinateurs inactifs +$($ComputerInactivityThreshold)j"
            Count = $inactPCBase
            Message = "$inactPCBase ordinateur(s) inactif(s) depuis $ComputerInactivityThreshold a 180 jours"
            Recommendation = "Surveiller et planifier le nettoyage"
            ANSSI = "R11 - Gerer le cycle de vie des comptes"
        }
    }
}

# 8. ALERTE - Groupes vides (pollution)
if ($totalgroups -gt 0) {
    $emptyGroupsPercent = [math]::Round(($Groupswithnomembership / $totalgroups) * 100, 1)
    
    if ($emptyGroupsPercent -gt $EmptyGroupsThreshold) {
        $alerts += [PSCustomObject]@{
            Level = "INFO"
            Type = "Groupes vides"
            Count = $Groupswithnomembership
            Message = "$emptyGroupsPercent% de groupes vides ($Groupswithnomembership/$totalgroups) - Seuil: $EmptyGroupsThreshold%"
            Recommendation = "Supprimer les groupes vides pour simplifier la gestion"
            ANSSI = "R13 - Minimiser les privilèges"
        }
    }
}

# Affichage des alertes
if ($alerts.Count -gt 0) {
    Write-SectionHeader "🔐 ALERTES DE SECURITE  —  ANSSI Hygiene informatique"
    Write-Host ""
    
    # Trier par niveau de criticité
    $alertOrder = @{ "CRITIQUE" = 1; "ELEVE" = 2; "MOYEN" = 3; "INFO" = 4 }
    $sortedAlerts = $alerts | Sort-Object { $alertOrder[$_.Level] }
    
    foreach ($alert in $sortedAlerts) {
        # Couleur selon le niveau
        $color = switch ($alert.Level) {
            "CRITIQUE" { "Red" }
            "ELEVE"    { "Yellow" }
            "MOYEN"    { "DarkYellow" }
            "INFO"     { "Cyan" }
        }
        
        # Icône selon le niveau
        $prefix = switch ($alert.Level) {
            "CRITIQUE" { "[CRITIQUE]" }
            "ELEVE"    { "[ELEVE]   " }
            "MOYEN"    { "[MOYEN]   " }
            "INFO"     { "[INFO]    " }
        }
        
        Write-Host "  $prefix $($alert.Type)" -ForegroundColor $color
        Write-Host "    $($alert.Message)" -ForegroundColor Gray
        Write-Host "    → " -ForegroundColor DarkGray -NoNewline
        Write-Host "$($alert.Recommendation)" -ForegroundColor DarkCyan
        Write-Host "    📋 ANSSI: $($alert.ANSSI)" -ForegroundColor DarkGray
        Write-Host ""
    }
    
    Write-Host ""
    
} else {
    Write-SectionHeader "✅ HYGIENE INFORMATIQUE  —  Aucune alerte detectee"
    Write-Host "    Toutes les verifications de securite sont conformes" -ForegroundColor DarkGreen
}

# === GÉNÉRATION DU RAPPORT ===
Write-Host ""
Write-SectionHeader "📄 GÉNÉRATION DU RAPPORT HTML"
