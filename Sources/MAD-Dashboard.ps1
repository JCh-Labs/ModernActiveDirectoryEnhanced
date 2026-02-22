<###########################
         Dashboard
############################>
# Collecte des donnees de base du domaine AD (objets supprimes, DC, admins,
# comptes/ordinateurs dans les OUs par defaut, comptes bloques, UPN suffixes).
#
# Variables consommees : aucune du contexte (autonome, premier module execute)
#
# Variables produites (utilisees par tout le rapport) :
#   $ADObjectTable                  - objets supprimes recemment
#   $deletedobject                  - compteur d'objets supprimes (30 derniers jours)
#   $usercomputerdeleted            - compteur users/PC supprimes
#   $ADRecycleBin                   - statut de la corbeille AD ("Enabled"/"Disabled")
#   $ForestObj, $DomainControllerobj
#   $Forest, $InfrastructureMaster, $RIDMaster, $PDCEmulator
#   $DomainNamingMaster, $SchemaMaster
#   $DomainAdminTable, $EnterpriseAdminTable
#   $DefaultComputersOU, $DefaultComputersinDefaultOU, $DefaultComputersinDefaultOUTable
#   $DefaultUsersOU, $DefaultUsersinDefaultOUTable
#   $Unlockusers
#   $DomainTable

Write-SectionHeader "COLLECTE DES DONNEES ACTIVE DIRECTORY"
Write-Progress-Custom "Dashboard" "Recuperation des objets supprimes"

# ANOMALIE5 FIX : utilise $RecentObjectsDays (parametre configurable) au lieu
# de 30 hardcode — coherence entre le titre des graphiques et la fenetre reelle.
$dte = (Get-Date).AddDays(-$RecentObjectsDays)
$usercomputerdeleted = 0
$deletedobject = 0

#this function replace whenchanged object, because whenchanged dont return the real reason, if computer is logged value when changed is modified.
#Get deleted objets last admodnumber 

Get-ADObject -Filter {isDeleted -eq $true -and (ObjectClass -eq 'user' -or ObjectClass -eq 'computer' -or ObjectClass -eq 'group')} -IncludeDeletedObjects -Properties ObjectClass,whenChanged | ForEach-Object {
	
    if ($_.objectclass -ne "Group")
	{
		$usercomputerdeleted++
		$Name = ($_.Name).split([Environment]::NewLine)[0]
	} else {
        $Name = ($_.Name).split([Environment]::NewLine)[0]
}
	if ($_.whenChanged -ge $dte) 
    {
    $deletedobject++
    }

	$obj = [PSCustomObject]@{
		'Name'         = $Name
		'Object Type'  = $_.ObjectClass
		'When Changed' = $_.WhenChanged
	}
	
	$ADObjectTable.Add($obj)
}

$ADRecycleBinStatus = (Get-ADOptionalFeature -Filter 'name -like "Recycle Bin Feature"').EnabledScopes

if ($ADRecycleBinStatus.Count -lt 1)
{
	$ADRecycleBin = "Disabled"
}
else
{
	$ADRecycleBin = "Enabled"
}

#Company Information

$ForestObj = Get-ADForest
$DomainControllerobj = Get-ADDomain
$Forest = $DomainControllerobj.Forest
$InfrastructureMaster = ($DomainControllerobj.InfrastructureMaster).Split('.')[0]
$RIDMaster = ($DomainControllerobj.RIDMaster).Split('.')[0]
$PDCEmulator = ($DomainControllerobj.PDCEmulator).Split('.')[0]
$DomainNamingMaster = ($ForestObj.DomainNamingMaster).Split('.')[0]
$SchemaMaster = ($ForestObj.SchemaMaster).Split('.')[0]
$EnterpriseAdminTable = $DomainAdminTable = 0

#Get Domain Admins and Entreprise admins
([adsisearcher] "(&(objectCategory=group)(admincount=1)(iscriticalsystemobject=*))").FindAll().Properties | ForEach-Object {

 $sidstring = (New-Object System.Security.Principal.SecurityIdentifier($_["objectsid"][0], 0)).Value 
    
    #-512 pour Domain Admins
      if ($sidstring -like "*-512") {
        $admindomaine = $_.name
        Get-ADGroupMember -identity "$admindomaine" -Recursive | ForEach-Object {               
        $DomainAdminTable++
    }
      }
    #-519 pour Enterprise Admins
      if ($sidstring -like "*-519") {
        $adminEnter = $_.name
        Get-ADGroupMember -identity "$adminEnter" -Recursive | ForEach-Object {                      
        $EnterpriseAdminTable++
        }
      }
    }

#Get objects in default OU

$DefaultComputersOU = (Get-ADDomain).computerscontainer
$DefaultComputersinDefaultOU = 0

Write-Progress-Custom "Ordinateurs OU defaut" "Recuperation des postes dans le conteneur par defaut"

Get-ADComputer -Filter * -Properties OperatingSystem,created,PasswordLastSet -SearchBase "$DefaultComputersOU" | ForEach-Object {
	
	$obj = [PSCustomObject]@{
		'Name'              = $_.Name
		'Enabled'           = $_.Enabled
		'Operating System'  = $_.OperatingSystem
		'Created'           = $_.created
		'Password Last Set' = $_.PasswordLastSet
	}
	
	$DefaultComputersinDefaultOUTable.Add($obj)
    $DefaultComputersinDefaultOU++
}


$DefaultUsersOU = (Get-ADDomain).UsersContainer 
Get-ADUser -Filter 'enabled -eq $true' -SearchBase $DefaultUsersOU -Properties Name,UserPrincipalName,Enabled,LastLogon | ForEach-Object {
	
	$obj = [PSCustomObject]@{
		'Name'              = $_.Name
		'UserPrincipalName' = $_.UserPrincipalName
		'Enabled'           = $_.Enabled
		'Last Logon'        = (LastLogonConvert $_.lastlogon)
	}
	
	$DefaultUsersinDefaultOUTable.Add($obj)
}

#Get Last Locked Users

Write-Progress-Custom "Utilisateurs verrouilles" "Recherche des comptes bloques"

Search-ADAccount -LockedOut -UsersOnly | ForEach-Object {
    $lockoutTime = $null
    try {
        $adUser = Get-ADUser $_.SamAccountName -Properties lockoutTime, BadPwdCount -ErrorAction SilentlyContinue
        if ($adUser.lockoutTime -and $adUser.lockoutTime -gt 0) {
            $lockoutTime = [DateTime]::FromFileTime($adUser.lockoutTime)
        }
    } catch {}
    $obj = [PSCustomObject]@{
        'Name'             = $_.Name
        'SamAccountName'   = $_.SamAccountName
        'Last Logon Date'  = $_.LastLogonDate
        'Locked Out Since' = $lockoutTime
        'Bad Pwd Count'    = if ($adUser) { $adUser.BadPwdCount } else { '' }
    }
    $Unlockusers.Add($obj)
}

#Tenant Domain
$ForestObj | Select-Object -ExpandProperty upnsuffixes | ForEach-Object {
	
	$obj = [PSCustomObject]@{
		'UPN Suffixes' = $_
		'Valid'        = "True"
	}
	
	$DomainTable.Add($obj)
}


Write-Success "Dashboard collecte"
