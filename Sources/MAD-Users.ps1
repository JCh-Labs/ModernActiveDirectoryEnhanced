<###########################

           USERS

############################>
# Collecte et analyse des comptes utilisateurs AD.
#
# Variables consommees (fournies par le contexte Get-MADReport) :
#   $LimitedView, $ShowSensitiveObjects
#   $MaxSearchObjects, $UserCreatedDays, $UserPasswordExpireDays, $UserInactiveDays
#
# Variables produites (utilisees par Dashboard, Resume, HTML MultiPage et OnePage) :
#   $UserTable                - liste complete des utilisateurs
#   $NewCreatedUsersTable     - utilisateurs crees recemment
#   $TOPUserTable             - tableau recapitulatif
#   $barcreateobject          - donnees pour graphique creation par date
#   $UserEnabled / $UserDisabled
#   $UserPasswordExpires / $UserPasswordNeverExpires
#   $ProtectedUsers / $NonProtectedUsers
#   $totalusers, $Userinactive, $lastcreatedusers, $neverlogedenabled
#   $ExpiringAccountsTable, $PasswordExpireSoonTable

Write-Host ""
Write-Host "  #=======================================================================" -ForegroundColor DarkCyan
Write-Host "  #  [UTILISATEURS]" -ForegroundColor Cyan
Write-Host "  #=======================================================================" -ForegroundColor DarkCyan
Write-Progress-Custom "Utilisateurs" "Analyse des comptes utilisateurs"

$UserEnabled = 0
$UserDisabled = 0
$UserPasswordExpires = 0
$UserPasswordNeverExpires = 0
$ProtectedUsers = 0
$NonProtectedUsers = 0
$totalusers = 0
$Userinactive = 0
# B05 FIX : seuil parametrable via $RecentObjectsDays (defaut 30, transmis par Get-MADReport)
$Createdlastdays = ((Get-Date).AddDays(-$RecentObjectsDays)).Date
$lastcreatedusers = 0
$neverlogedenabled = 0
$ExpiringAccountsTable = 0
$PasswordExpireSoonTable = 0
$SkipReadPSO = $false

#Get all users right away. Instead of doing several lookups, we will use this object to look up all the information needed.
$Alluserpropert = @(
'WhenCreated'
'DistinguishedName'
'ProtectedFromAccidentalDeletion'
'LastLogon'
'EmailAddress'
'LastLogonDate'
'PasswordExpired'
'PasswordLastSet'
'Description'
'PasswordNeverExpires'
'AccountExpirationDate'
'msDS-PSOApplied'
'admincount'
)

#Get newly created users
$When = ((Get-Date).AddDays(-$UserCreatedDays)).Date

#Get expired account and still enabled
$dateexpiresoone = (Get-Date).AddDays($UserPasswordExpireDays)
$expiredsoon = 0
$expired = (Get-Date)

#Get users that haven't logged on in X amount of days, var is set at start of script
$maxPasswordAge = (Get-ADDefaultDomainPasswordPolicy).MaxPasswordAge.Days

# Filtrage des utilisateurs selon LimitedView
if ($LimitedView -and -not $ShowSensitiveObjects.IsPresent) { 
    $filterusers = "(!(admincount=*))"
    Write-Progress-Custom "Utilisateurs" "Filtrage des comptes privileges (mode LimitedView)"
} else { 
    $filterusers = "(samaccountname=*)"
    Write-Progress-Custom "Utilisateurs" "Recuperation de TOUS les utilisateurs (mode complet)"
}

if ($ShowSensitiveObjects.IsPresent) {
    $filterusers = "(samaccountname=*)"
    Write-Progress-Custom "Utilisateurs" "Flag ShowSensitiveObjects actif - comptes admins et privilegies inclus"
}

Get-ADUser -LDAPFilter $filterusers -Properties $Alluserpropert -ResultSetSize $MaxSearchObjects | ForEach-Object {
 
    $totalusers++

    $lastlog = (LastLogonConvert $_.lastlogon)

    #New created users
    if ( $_.whenCreated -ge $When ) {

	$obj = [PSCustomObject]@{
		'Name'          = $_.Name
		'Enabled'       = $_.Enabled
		'Creation Date' = $_.whenCreated
	}
	
	$NewCreatedUsersTable.Add($obj)
}

    #Expired users and still enabled
    if ($_.AccountExpirationDate -lt $dateexpiresoone -and $null -ne $_.AccountExpirationDate -and $_.enabled -eq $true) {
    	
    if ($_.AccountExpirationDate -gt $expired) { $expiredsoon++ } 

    else {

    $ExpiringAccountsTable++
}
}

    #User Never loged and Enabled
    if (($null -eq $_.lastlogondate) -and ($_.Enabled -ne $false)) 
    {
     $neverlogedenabled++
    }

    #get days until password expired
	if ((($_.PasswordNeverExpires) -eq $False) -and (($_.Enabled) -ne $false))
	{
		
		#Get Password last set date
		$passwordSetDate = ($_.PasswordLastSet)
		
		if ($null -eq $passwordSetDate)
		{			
            if ($null -eq $_.lastlogondate) {
            $daystoexpire = -999 
            } else {
            $daystoexpire = -998
            }

		}
		
		else
		{
			
			#Check for Fine Grained Passwords
			
            if ($($_."msDS-PSOApplied") -and $SkipReadPSO -ne $true ) {

			$PasswordPol = (Get-ADUserResultantPasswordPolicy $_ -ErrorAction SilentlyContinue -ErrorVariable PSOeror).MaxPasswordAge.days

            if ($PSOeror) {
            Write-Warning-Custom "Impossible de lire une strategie PSO - verifiez les permissions"
            $PSOeror
            $SkipReadPSO = $true
            }

            $expireson = $passwordsetdate.AddDays($PasswordPol)
            $PasswordPol = $null

            } else {
		
			$expireson = $passwordsetdate.AddDays($maxPasswordAge)
            }

			$today = (Get-Date)
			
			#Gets the count on how many days until the password expires and stores it in the $daystoexpire var
			$daystoexpire = (New-TimeSpan -Start $today -End $Expireson).Days
		}
	}
	
	else
	{
		#Users not need change passwords
        $daystoexpire = 0

	}	


	if (($_.Enabled -eq $True) -and ($lastlog -lt ((Get-Date).AddDays(-$UserInactiveDays))) -and ($NULL -ne $_.LastLogon))
	{
        $userinactive++
	}

    #Get User created Last 30 days
    if ( $_.whenCreated -ge $createdlastdays ) 
    {

    $lastcreatedusers++

    $barcreated = ($_.Whencreated.ToString("yyyy/MM/dd"))

    $rec = $barcreateobject | Where-Object {$_.date -eq $barcreated } 

    if ($rec) {

            $rec.Nbr_users += 1
    } else {

       $obj = [PSCustomObject]@{		
		'Nbr_users' = 1
        'Nbr_PC'    = 0
		'Date'      = $barcreated
	}

$barcreateobject.Add($obj)

}

    }

	
	#Items for protected vs non protected users
	if ($_.ProtectedFromAccidentalDeletion -eq $False)
	{
		
		$NonProtectedUsers++
	}
	
	else
	{
		
		$ProtectedUsers++
	}
	
	#Items for the enabled vs disabled users pie chart
	if (($_.PasswordNeverExpires) -ne $false)
	{
		
		$UserPasswordNeverExpires++
	}
	
	else
	{
		
		$UserPasswordExpires++
	}
	
	#Items for password expiration pie chart
	if (($_.Enabled) -ne $false)
	{
		
		$UserEnabled++
	}
	
	else
	{
		
		$UserDisabled++
	}
	

	$obj = [PSCustomObject]@{
		'Name'                        = $_.Name
		'UserPrincipalName'           = $_.UserPrincipalName
		'Enabled'                     = $_.Enabled
		'Email Address'               = $_.EmailAddress
		'Description'                 = $_.description
		'Account Expiration'          = $_.AccountExpirationDate
		'Created'                     = $_.whencreated
		'Last Logon Date'             = $_.LastLogonDate
		'Password Last Set'           = $_.PasswordLastSet
		'Password Never Expired'      = $_.PasswordNeverExpires
		'Days Until password expired' = $daystoexpire
		'Protected from Deletion'     = $_.ProtectedFromAccidentalDeletion
		'Privileged'                  = if ($_.admincount -eq 1) { 'Yes' } else { 'No' }
		'OU'                          = (($_.DistinguishedName -split ",") | Where-Object {$_ -like "OU=*"} | ForEach-Object {$_ -replace "OU=",""}) -join ","
		'CN'                          = $_.DistinguishedName
	}
	
        $UserTable.Add($obj)
	
	if ($daystoexpire -lt $UserPasswordExpireDays -and $daystoexpire -ge 0)
	{
		
		$PasswordExpireSoonTable++
	}
}


#TOP User table
	$objULic = [PSCustomObject]@{
		'Total Users' = $totalusers
		"Users with Passwords Expiring in less than $UserPasswordExpireDays days" = $PasswordExpireSoonTable
		'Expiring Accounts' = $ExpiringAccountsTable
	}	
	$TOPUserTable.Add($objULic)

Write-Success "Utilisateurs collectes"
$_uTotal = $UserTable.Count
$_uEnabled = @($UserTable | Where-Object { $_.Enabled -eq $true }).Count
$_uDisabled = @($UserTable | Where-Object { $_.Enabled -eq $false }).Count
$_uPriv = @($UserTable | Where-Object { $_.Privileged -eq "Yes" }).Count
Write-Host "  >> Total: $_uTotal | Actifs: $_uEnabled | Desactives: $_uDisabled | Privilegies (admincount): $_uPriv" -ForegroundColor DarkGray
