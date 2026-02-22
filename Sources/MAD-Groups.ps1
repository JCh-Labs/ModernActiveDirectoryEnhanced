<###########################

           Groups

############################>
# Collecte et analyse des groupes Active Directory.
#
# Variables consommees (fournies par le contexte Get-MADReport) :
#   $LimitedView, $ShowSensitiveObjects, $MaxSearchGroups, $DefaultSGs
#
# Variables produites (utilisees par Dashboard, Resume, HTML MultiPage et OnePage) :
#   $table                  - groupes avec membres
#   $Groupsnomembers        - groupes sans membres
#   $TOPGroupsTable         - tableau recapitulatif
#   $SecurityCount          - nb groupes de securite
#   $DistroCount            - nb groupes de distribution
#   $CustomGroup            - nb groupes personnalises (avec membres)
#   $Groupswithmemebrship   - nb groupes avec membres
#   $Groupswithnomembership - nb groupes sans membres
#   $GroupsProtected        - nb groupes proteges contre la suppression
#   $GroupsNotProtected     - nb groupes non proteges
#   $totalgroups            - nb total de groupes

Write-Host ""
Write-Host "  #=======================================================================" -ForegroundColor DarkCyan
Write-Host "  #  [GROUPES]" -ForegroundColor Cyan
Write-Host "  #=======================================================================" -ForegroundColor DarkCyan
Write-Progress-Custom "Groupes" "Analyse des groupes AD"
#Get groups and sort in alphabetical order
#list only group with members, this can be interresed on big domain with a lot of groups, you can remove the where if you are in small company
#I'm excluded the Exchange groups -ResultSetSize $MaxSearchGroups
$SecurityCount = 0
$CustomGroup = 0
$DefaultGroup = 0
$Groupswithmemebrship = 0
$Groupswithnomembership = 0
$GroupsProtected = 0
$GroupsNotProtected = 0
$totalgroups = 0
$DistroCount = 0 

# Filter groups based on LimitedView setting
if ($LimitedView -and -not $ShowSensitiveObjects.IsPresent) {
    # Mode LimitedView : Exclure les groupes avec admincount et groupes systeme
    $Skipdefaultadmingroups = "(&(!(groupType:1.2.840.113556.1.4.803:=1))(!(&(objectCategory=group)(admincount=1)(iscriticalsystemobject=*))))"
    Write-Progress-Custom "Groupes" "Filtrage des groupes privilegies (mode LimitedView)"
} else {
    # Mode complet : Recuperer TOUS les groupes y compris admin
    $Skipdefaultadmingroups = "(objectCategory=group)"
    Write-Progress-Custom "Groupes" "Recuperation de TOUS les groupes (mode complet)"
}

# ── B02 FIX : charger tous les groupes du domaine en un seul appel LDAP ────────
# On construit un HashSet<string> des DNs de groupes pour permettre une
# recherche O(1) lors du traitement de chaque membre, sans aucun appel
# Get-ADObject supplementaire.
Write-Progress-Custom "Groupes" "Chargement du cache DN->type (batch unique)"
$groupDNCache = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)
Get-ADGroup -LDAPFilter "(objectCategory=group)" -ResultSetSize $null -Properties DistinguishedName |
    ForEach-Object { [void]$groupDNCache.Add($_.DistinguishedName) }
# ────────────────────────────────────────────────────────────────────────────────

Get-ADGroup -LDAPFilter $Skipdefaultadmingroups -ResultSetSize $MaxSearchGroups -Properties Member,ManagedBy,info,created,ProtectedFromAccidentalDeletion | 
    Where-Object { 
        # En mode LimitedView, exclure aussi les groupes par defaut par nom
        if ($LimitedView -and -not $ShowSensitiveObjects.IsPresent) {
            $DefaultSGs -notcontains $_.Name
        } else {
            $true  # Inclure tous les groupes
        }
    } | ForEach-Object {

$totalgroups++
$OwnerDN = $null

if  (!$_.member) { 

$Groupswithnomembership++

    # BUG12 FIX : incrementer les compteurs Security/Distribution meme pour les groupes sans membres
    if ($_.GroupCategory -eq "Security")     { $SecurityCount++ }
    elseif ($_.GroupCategory -eq "Distribution") { $DistroCount++ }

    if ($($_.ManagedBy)) {
    $OwnerDN = ($_.ManagedBy -split (",") | Where-Object {$_ -like "CN=*"}) -replace ("CN=","")
    }

	$obj = [PSCustomObject]@{
		
		'Name' = $_.name
		'Type' = $_.GroupCategory
		'Managed By' = $OwnerDN
        'Created' = ($_.created.ToString("yyyy/MM/dd"))
		'Default AD Group' = ($DefaultSGs -contains $_.name)
        'Protected from Deletion' = $_.ProtectedFromAccidentalDeletion
	}
	
	$Groupsnomembers.Add($obj)

 }  
 
 else {

	$Groupswithmemebrship++
	$Type = New-Object 'System.Collections.Generic.List[System.Object]'

	if ($_.GroupCategory -eq "Security")
	{
		
		$SecurityCount++
        $Type = "Security Group"

	} elseif ($_.GroupCategory -eq "Distribution") {

        $DistroCount++
        $Type = "Distribution Group"
    }    
	
	if ($_.ProtectedFromAccidentalDeletion -eq $True)
	{
		
		$GroupsProtected++
	}
	
	else
	{
		
		$GroupsNotProtected++
	}
	
		$CustomGroup++
        # Distinguer utilisateurs et groupes membres
        # B02 FIX : lookup O(1) dans le cache — zero appel reseau supplementaire
        $memberList = @()
        foreach ($memberDN in $_.member) {
            $memberName = ($memberDN -split ',')[0] -replace 'CN=',''
            if ($groupDNCache.Contains($memberDN)) {
                $memberList += "[G] $memberName"
            } else {
                $memberList += $memberName
            }
        }
        $users = $memberList -join ", "
        $OwnerDN = ($_.ManagedBy -split (",") | Where-Object {$_ -like "CN=*"}) -replace ("CN=","")

	
	$obj = [PSCustomObject]@{
		
		'Name' = $_.name
		'Type' = $Type
		'Members' = $users
		'Managed By' = $OwnerDN
        'Created' = ($_.created.ToString("yyyy/MM/dd"))
        'Remark' = $_.info
		'Protected from Deletion' = $_.ProtectedFromAccidentalDeletion
	}
	
	$Table.Add($obj)
}

}


#TOP groups table
$obj1 = [PSCustomObject]@{
	
	'Total Groups' = $totalgroups
	'Groups with members' = $Groupswithmemebrship
	'Security Groups' = $SecurityCount
	'Distribution Groups' = $DistroCount
}

$TOPGroupsTable.Add($obj1)

Write-Success "Groupes collectes"
Write-Host "  >> Total: $totalgroups | Securite: $SecurityCount | Distribution: $DistroCount | Vides: $Groupswithnomembership" -ForegroundColor DarkGray

# ============================================================
# MEMBRES RECURSIFS DES GROUPES
# ============================================================
$GroupMembersDetailTable = New-Object 'System.Collections.Generic.List[System.Object]'

function Get-GroupMembersRecursive {
    param(
        [string]$GroupName,
        [string]$TopGroupName,
        [System.Collections.Generic.HashSet[string]]$Visited = $null
    )
    if ($null -eq $Visited) { $Visited = [System.Collections.Generic.HashSet[string]]::new() }
    if (-not $Visited.Add($GroupName)) { return }
    try {
        $members = Get-ADGroupMember -Identity $GroupName -ErrorAction Stop
        foreach ($m in $members) {
            if ($m.objectClass -eq 'group') {
                Get-GroupMembersRecursive -GroupName $m.SamAccountName -TopGroupName $TopGroupName -Visited $Visited
            } elseif ($m.objectClass -eq 'user') {
                $already = $GroupMembersDetailTable | Where-Object {
                    $_.SamAccountName -eq $m.SamAccountName -and $_.'Source Group' -eq $TopGroupName
                }
                if (-not $already) {
                    try {
                        $u = Get-ADUser -Identity $m.SamAccountName -Properties `
                            UserPrincipalName,Enabled,EmailAddress,Description,
                            AccountExpirationDate,whencreated,LastLogonDate,
                            PasswordLastSet,PasswordNeverExpires,
                            ProtectedFromAccidentalDeletion,admincount,
                            DistinguishedName,'msDS-UserPasswordExpiryTimeComputed' `
                            -ErrorAction Stop
                        $daystoexpire = 0
                        try {
                            $expiry = [datetime]::FromFileTime($u.'msDS-UserPasswordExpiryTimeComputed')
                            if ($expiry -gt (Get-Date) -and $expiry.Year -lt 9999) {
                                $daystoexpire = ($expiry - (Get-Date)).Days
                            }
                        } catch { }
                        $obj = [PSCustomObject]@{
                            'Source Group'                = $TopGroupName
                            'Name'                        = $u.Name
                            'SamAccountName'              = $u.SamAccountName
                            'UserPrincipalName'           = $u.UserPrincipalName
                            'Enabled'                     = $u.Enabled
                            'Email Address'               = $u.EmailAddress
                            'Description'                 = $u.description
                            'Account Expiration'          = $u.AccountExpirationDate
                            'Created'                     = $u.whencreated
                            'Last Logon Date'             = $u.LastLogonDate
                            'Password Last Set'           = $u.PasswordLastSet
                            'Password Never Expired'      = $u.PasswordNeverExpires
                            'Days Until password expired' = $daystoexpire
                            'Protected from Deletion'     = $u.ProtectedFromAccidentalDeletion
                            'Privileged'                  = if ($u.admincount -eq 1) { 'Yes' } else { 'No' }
                            'OU'                          = (($u.DistinguishedName -split ',') | Where-Object {$_ -like 'OU=*'} | ForEach-Object {$_ -replace 'OU=',''}) -join ','
                            'CN'                          = $u.DistinguishedName
                        }
                        $GroupMembersDetailTable.Add($obj)
                    } catch { }
                }
            }
        }
    } catch { }
}

foreach ($grp in ($Table | Select-Object -ExpandProperty Name)) {
    Get-GroupMembersRecursive -GroupName $grp -TopGroupName $grp
}
