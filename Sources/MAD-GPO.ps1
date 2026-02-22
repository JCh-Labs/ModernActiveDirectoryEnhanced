<###########################
     Group Policy
############################>
# Collecte et analyse des GPO (Group Policy Objects).
#
# Variables consommees (fournies par le contexte Get-MADReport) :
#   $nogpomod           - flag : si $true, le module GPMC est absent, on saute la collecte
#   $DomainControllerobj - objet Get-ADDomain (SubordinateReferences, DistinguishedName)
#
# Variables produites (utilisees par le HTML MultiPage et OnePage) :
#   $GPOs           - liste brute de tous les GPOs
#   $GPO_Linked     - GPOs liees a au moins un conteneur
#   $GPO_NotLinked  - GPOs orphelines (non liees)
#   $GPO_Details    - GPOs liees enrichies avec colonne 'Linked To' et 'Link Count'

if (!$nogpomod) {
    Write-Host ""
    Write-Host "  #=======================================================================" -ForegroundColor DarkCyan
    Write-Host "  #  [GROUP POLICY OBJECTS (GPO)]" -ForegroundColor Cyan
    Write-Host "  #=======================================================================" -ForegroundColor DarkCyan
    Write-Progress-Custom "GPO" "Analyse des strategies de groupe"

    # All GPOs
    $GPOs = Get-GPO -All | Select-Object DisplayName, GPOStatus, Id, ModificationTime, CreationTime, WmiFilter

    # Collect all containers (domain, OUs, sites) that can hold gPLink
    $adContainers = @()
    # BUG21 FIX : .Trim() lève une exception si Where-Object retourne $null (aucun SubordinateReference 'configuration')
    $configuration = ($DomainControllerobj.SubordinateReferences | Where-Object { $_ -like '*configuration*' } | Select-Object -First 1)
    if ($configuration) { $configuration = $configuration.Trim() }
    $adContainers += Get-ADObject -LDAPFilter "(|(objectClass=organizationalUnit)(objectClass=domainDNS))" -SearchBase $DomainControllerobj.DistinguishedName -Properties gpLink, distinguishedName, name
    $adContainers += Get-ADObject -LDAPFilter "(objectClass=site)" -SearchBase $configuration -Properties gpLink, distinguishedName, name

    # Extract linked GPO GUIDs from gPLink strings AND build mapping GPO -> OUs
    $linkedGuids = New-Object 'System.Collections.Generic.HashSet[string]'
    $gpoToOUMapping = @{}  # Dictionary: GPO GUID -> List of OU names
    
    foreach ($c in $adContainers) {
        $gp = $c.gpLink
        if ([string]::IsNullOrEmpty($gp)) { continue }
        
        foreach ($m in [regex]::Matches($gp, '\{([0-9a-fA-F-]{36})\}')) {
            $guid = $m.Groups[1].Value.ToLower()
            [void]$linkedGuids.Add($guid)
            
            # Build mapping GPO -> OU
            if (-not $gpoToOUMapping.ContainsKey($guid)) {
                $gpoToOUMapping[$guid] = New-Object 'System.Collections.Generic.List[string]'
            }
            
            # Use friendly name (OU name or Domain or Site)
            $containerName = if ($c.objectClass -eq 'domainDNS') {
                "Domain Root"
            } elseif ($c.objectClass -eq 'site') {
                "Site: $($c.name)"
            } else {
                $c.name
            }
            
            $gpoToOUMapping[$guid].Add($containerName)
        }
    }

    # Split GPOs into linked and not linked, and add LinkedTo info
    $GPO_Linked    = New-Object 'System.Collections.Generic.List[Object]'
    $GPO_NotLinked = New-Object 'System.Collections.Generic.List[Object]'
    $GPO_Details   = New-Object 'System.Collections.Generic.List[Object]'  # Enhanced table with LinkedTo

    foreach ($g in $GPOs) {
        $gid = $g.Id.Guid.ToString().ToLower()
        
        if ($linkedGuids.Contains($gid)) {
            $GPO_Linked.Add($g)
            
            # Create enhanced object with LinkedTo information
            $linkedToList = $gpoToOUMapping[$gid] -join ", "
            $linkedCount = $gpoToOUMapping[$gid].Count
            
            $enhancedGPO = [PSCustomObject]@{
                'GPO Name'   = $g.DisplayName
                'Status'     = $g.GPOStatus
                'Linked To'  = $linkedToList
                'Link Count' = $linkedCount
                'Modified'   = $g.ModificationTime
                'Created'    = $g.CreationTime
                'WMI Filter' = if ($g.WmiFilter) { $g.WmiFilter.Name } else { "None" }
            }
            $GPO_Details.Add($enhancedGPO)
            
        } else {
            $GPO_NotLinked.Add($g)
        }
    }

    # Make sure NotLinked is always an array (never integer), so .Count is reliable
    if (-not $GPO_NotLinked) { $GPO_NotLinked = @() }

    # ============================================================
    # GPO LIEES AUX DOMAIN CONTROLLERS (visibles avec -ShowSensitiveObjects)
    # ============================================================
    # Identifier les conteneurs qui correspondent a l'OU Domain Controllers
    $GPO_DCLinked = New-Object 'System.Collections.Generic.List[Object]'
    $dcOUKeywords = @("Domain Controllers", "DomainControllers", "DC", "Controllers")

    foreach ($gpoDetail in $GPO_Details) {
        $linkedTo = $gpoDetail.'Linked To'
        if ([string]::IsNullOrEmpty($linkedTo)) { continue }

        # Verifier si la GPO est liee a une OU dont le nom evoque les DC
        $isDCLinked = $false
        foreach ($kw in $dcOUKeywords) {
            if ($linkedTo -match [regex]::Escape($kw)) {
                $isDCLinked = $true
                break
            }
        }
        # Ajouter un flag sur l'objet existant
        $gpoDetail | Add-Member -NotePropertyName 'Linked To DC OU' -NotePropertyValue $isDCLinked -Force
        if ($isDCLinked) {
            $GPO_DCLinked.Add($gpoDetail)
        }
    }

    # Ajouter le flag sur les GPOs non enrichies (GPO_Details les a deja)
    if ($ShowSensitiveObjects.IsPresent) {
        Write-Progress-Custom "GPO" "Detection des GPO liees aux Domain Controllers"
    }

    Write-Success "GPO collectees : $($GPO_Linked.Count) liee(s), $($GPO_NotLinked.Count) orpheline(s), $($GPO_DCLinked.Count) liee(s) aux DC"
    $_gpoLinked = $GPO_Linked.Count
    $_gpoOrph   = $GPO_NotLinked.Count
    $_gpoTotal  = $GPOs.Count
    Write-Host "  >> Liees: $_gpoLinked | Orphelines: $_gpoOrph | Total: $_gpoTotal" -ForegroundColor DarkGray
}