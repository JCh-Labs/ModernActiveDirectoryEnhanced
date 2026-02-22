<###########################
     Domain Trusts
############################>
# Collecte et analyse des relations d'approbation AD.
#
# Variables consommees : aucune du contexte (autonome)
#
# Variables produites (utilisees par le HTML MultiPage et OnePage) :
#   $TrustsTable  - liste des trusts enrichis (direction, type, securite, etc.)
#   $TrustsStats  - hashtable de statistiques (Total, IntraForest, External, etc.)

Write-Host ""
Write-Host "  #=======================================================================" -ForegroundColor DarkCyan
Write-Host "  #  [DOMAIN TRUSTS]" -ForegroundColor Cyan
Write-Host "  #=======================================================================" -ForegroundColor DarkCyan
Write-Progress-Custom "Trusts" "Analyse des relations d'approbation"

# Initialize trust collections
$TrustsTable = New-Object 'System.Collections.Generic.List[Object]'
$TrustsStats = @{
    Total             = 0
    IntraForest       = 0
    External          = 0
    Bidirectional     = 0
    Inbound           = 0
    Outbound          = 0
    WithSIDFiltering  = 0
    WithSelectiveAuth = 0
}

try {
    # Get all trusts
    $AllTrusts = Get-ADTrust -Filter * -ErrorAction Stop
    
    if ($AllTrusts) {
        foreach ($trust in $AllTrusts) {
            $TrustsStats.Total++
            
            # Analyze trust properties
            $isIntraForest = $trust.IntraForest
            $direction     = $trust.Direction.ToString()
            $sidFiltering  = $trust.SIDFilteringQuarantined -or $trust.SIDFilteringForestAware
            $selectiveAuth = $trust.SelectiveAuthentication
            
            # Update statistics
            if ($isIntraForest) { $TrustsStats.IntraForest++ }
            else { $TrustsStats.External++ }
            
            switch ($direction) {
                'Bidirectional' { $TrustsStats.Bidirectional++ }
                'Inbound'       { $TrustsStats.Inbound++ }
                'Outbound'      { $TrustsStats.Outbound++ }
            }
            
            if ($sidFiltering)  { $TrustsStats.WithSIDFiltering++ }
            if ($selectiveAuth) { $TrustsStats.WithSelectiveAuth++ }
            
            # Determine trust type display
            $trustTypeDisplay = if ($isIntraForest) {
                if ($trust.IsTreeParent -or $trust.IsTreeRoot) { "Parent-Child" }
                else { "Intra-Forest" }
            } else {
                switch ($trust.TrustType) {
                    'Uplevel'   { 'Windows (AD)' }
                    'Downlevel' { 'Windows NT 4.0' }
                    'MIT'       { 'MIT Kerberos' }
                    'DCE'       { 'DCE' }
                    default     { $trust.TrustType }
                }
            }
            
            # Security status
            $securityStatus = if ($isIntraForest) {
                "Internal Trust"
            } elseif ($sidFiltering -and $selectiveAuth) {
                "Hardened"
            } elseif ($sidFiltering -or $selectiveAuth) {
                "Partially Secured"
            } else {
                "Review Needed"
            }
            
            # Direction display (text only, no emoji)
            $directionDisplay = switch ($direction) {
                'Bidirectional' { '<-> Bidirectional' }
                'Inbound'       { '<-- Inbound' }
                'Outbound'      { '--> Outbound' }
                default         { $direction }
            }
            
            # Create trust object
            $trustObj = [PSCustomObject]@{
                'Name'            = $trust.Name
                'Direction'       = $directionDisplay
                'Type'            = $trustTypeDisplay
                'Intra-Forest'    = if ($isIntraForest) { "Yes" } else { "No" }
                'SID Filtering'   = if ($sidFiltering)  { "Yes" } else { "No" }
                'Selective Auth'  = if ($selectiveAuth) { "Yes" } else { "No" }
                'Security Status' = $securityStatus
                'Target'          = $trust.Target
                'Created'         = if ($trust.Created) { $trust.Created.ToString("yyyy-MM-dd") } else { "N/A" }
            }
            
            $TrustsTable.Add($trustObj)
        }
        
        Write-Success "Relations d'approbation collectees : $($TrustsStats.Total) trust(s)"
        $_tTotal = $TrustsStats.Total
        $_tExt   = $TrustsStats.External
        $_tIntra = $TrustsStats.IntraForest
        Write-Host "  >> Total: $_tTotal | Externes: $_tExt | Intra-foret: $_tIntra" -ForegroundColor DarkGray
    } else {
        Write-Verbose "Aucune relation d'approbation detectee (foret mono-domaine)"
    }
    
} catch {
    Write-Host "Unable to retrieve trusts: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "This is normal for single-domain forests with no external trusts" -ForegroundColor Gray
}
