<###########################

           Printers

############################>
# Collecte des imprimantes publiees dans l'AD.
#
# Variables consommees : aucune du contexte (autonome)
#
# Variables produites (utilisees par le HTML MultiPage et OnePage) :
#   $printers    - liste des imprimantes (ou string "No printers Found")
#   $printersnbr - nombre d'imprimantes trouvees

Write-Host ""
Write-Host "  #=======================================================================" -ForegroundColor DarkCyan
Write-Host "  #  [SERVEURS D'IMPRESSION]" -ForegroundColor Cyan
Write-Host "  #=======================================================================" -ForegroundColor DarkCyan
Write-Progress-Custom "Imprimantes" "Recuperation des imprimantes"
$printersnbr = 0

$printers = Get-AdObject -Filter "objectCategory -eq 'printqueue'" -Properties description,drivername,created,location |
    Select-Object name, description, drivername, created, location

$printersnbr = ($printers.name).count

if (!$printers) {
    $printers = "No printers Found"
}
Write-Success "Imprimantes collectees"
Write-Host "  >> Total: $printersnbr imprimante(s) publiee(s) dans l'AD" -ForegroundColor DarkGray
