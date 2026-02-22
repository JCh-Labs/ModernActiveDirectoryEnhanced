<###########################

    Organizational Units

############################>
# Collecte et analyse des Unites d'Organisation (OU).
#
# Variables consommees (fournies par le contexte Get-MADReport) :
#   $OUSearchScope  - profondeur de scan (OneLevel, Base, Subtree)
#   $nogpomod       - flag pour desactiver la resolution des noms GPO (si module GPO absent)
#
# Variables produites (utilisees par le HTML MultiPage et OnePage) :
#   $OUTable        - liste des OUs avec GPOs liees, date de modif, protection
#   $OUwithLinked   - nb d'OUs avec GPO(s) liee(s)
#   $OUwithnoLink   - nb d'OUs sans GPO liee
#   $OUProtected    - nb d'OUs protegees contre la suppression
#   $OUNotProtected - nb d'OUs non protegees

Write-Host ""
Write-Host "  #=======================================================================" -ForegroundColor DarkCyan
Write-Host "  #  [UNITES D'ORGANISATION (OUs)]" -ForegroundColor Cyan
Write-Host "  #=======================================================================" -ForegroundColor DarkCyan
Write-Progress-Custom "OUs" "Analyse des unites d'organisation"

#Get all OUs'
$OUwithLinked = 0
$OUwithnoLink = 0
$OUProtected = 0
$OUNotProtected = 0

# BUG24 FIX : cache GPO pour eviter un appel Get-GPO par lien par OU (O(n) appels AD)
# Charge une seule fois tous les GPO dans un hashtable GUID → DisplayName
$GPOCache = @{}
if (!$nogpomod) {
    Get-GPO -All -ErrorAction SilentlyContinue | ForEach-Object {
        $GPOCache[$_.Id.ToString().ToUpper()] = $_.DisplayName
    }
}

#foreach ($OU in $OUs)
Get-ADOrganizationalUnit -Filter * -Properties ProtectedFromAccidentalDeletion,whenchanged -SearchScope $OUSearchScope | ForEach-Object {
	
	$LinkedGPOs = New-Object 'System.Collections.Generic.List[System.Object]'
	
	if (($_.linkedgrouppolicyobjects).length -lt 1)
	{
		
		$LinkedGPOs = "None"
		$OUwithnoLink++
	}
	
	else
	{
		
		$OUwithLinked++
		$GPOslinks = $_.linkedgrouppolicyobjects
		
		foreach ($GPOlink in $GPOslinks)
		{
			
			$Split1 = $GPOlink -split "{" | Select-Object -Last 1
			$Split2 = $Split1 -split "}" | Select-Object -First 1
            if (!$nogpomod) {
                # BUG24 FIX : lookup dans le cache au lieu d'un appel AD par GUID
                $gpoName = $GPOCache[$Split2.ToUpper()]
                $LinkedGPOs.Add($(if ($gpoName) { $gpoName } else { $Split2 }))
            }
		}
	}

	if ($_.ProtectedFromAccidentalDeletion -eq $True)
	{
		
		$OUProtected++
	}
	
	else
	{
		
		$OUNotProtected++
	}
	
	$LinkedGPOs = $LinkedGPOs -join ", "
	$obj = [PSCustomObject]@{
		
		'Name' = $_.Name
		'Linked GPOs' = $LinkedGPOs
		'Modified Date' = $_.WhenChanged
		'Protected from Deletion' = $_.ProtectedFromAccidentalDeletion
	}
	
	$OUTable.Add($obj)
}

Write-Success "Unites d'organisation collectees"
$_ouTotal = $OUTable.Count
Write-Host "  >> Total: $_ouTotal | Avec GPO: $OUwithLinked | Sans GPO: $OUwithnoLink" -ForegroundColor DarkGray