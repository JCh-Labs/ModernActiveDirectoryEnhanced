<###########################

           Resume

############################>
# Calcul des totaux finaux et preparation du tableau de synthese global.
# Doit etre execute APRES tous les modules de collecte (Dashboard, Groups,
# Users, Computers, Printers).
#
# Variables consommees (produites par les modules precedents) :
#   $totalusers, $totalcomputers, $totalgroups
#   $DefaultSGs, $printersnbr
#
# Variables produites (utilisees par le HTML MultiPage et OnePage) :
#   $Allobjects      - liste de synthese tous objets AD
#   $totalcontacts   - nombre de contacts AD

$Allobjects  = $null
$contacts    = (Get-ADObject -Filter 'objectclass -eq "contact"').name
$totalcontacts = ($contacts).count
$Allobjects  = New-Object 'System.Collections.Generic.List[System.Object]'

# Correction B-01 : n'ajouter aux totaux QUE ce qui a ete exclu de la collecte.
# En mode ShowSensitiveObjects, admins/DC/DefaultSGs sont deja dans les tables -> pas d'ajout.
# En mode LimitedView actif (sans ShowSensitiveObjects), ils ont ete exclus -> on les reintegre dans les totaux.
if ($LimitedView -and -not $ShowSensitiveObjects.IsPresent) {
    $totalusers     = $totalusers     + (Get-ADUser     -LDAPFilter "(admincount=*)").count
    $totalcomputers = $totalcomputers + (Get-ADComputer -LDAPFilter "(userAccountControl:1.2.840.113556.1.4.803:=8192)" | Select-Object name).name.count
    $totalgroups    = $totalgroups    + ($DefaultSGs.count)
}
# En mode complet (-LimitedView:$false ou -ShowSensitiveObjects), les totaux sont deja exacts.

$Allobjects = @(
    [pscustomobject]@{Name='Groups';        Count=$totalgroups}
    [pscustomobject]@{Name='Users';         Count=$totalusers}
    [pscustomobject]@{Name='Computers';     Count=$totalcomputers}
    [pscustomobject]@{Name='Contacts';      Count=$totalcontacts}
    [pscustomobject]@{Name='Printer server';Count=$printersnbr}
)

Write-Success "Donnees de synthese calculees"
