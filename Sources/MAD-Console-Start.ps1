# === AVERTISSEMENT LIMITEDVIEW ===
# En mode PreCheck, le LimitedView ne s'applique pas : on analyse tout le parc sans restriction
if ($LimitedView -and -not $ShowSensitiveObjects.IsPresent -and -not $PreCheck.IsPresent) {
    Write-Host ""
    Write-Host "  [!] " -ForegroundColor Yellow -NoNewline
    Write-Host "MODE LIMITEDVIEW ACTIVE (par defaut)" -ForegroundColor Yellow
    Write-Host "  * Les comptes administrateurs (admincount=1) sont EXCLUS" -ForegroundColor Gray
    Write-Host "  * Les DC (Domain Controllers) sont EXCLUS" -ForegroundColor Gray
    Write-Host "  * Les groupes privilegies (Domain Admins, etc.) sont EXCLUS" -ForegroundColor Gray
    Write-Host "  * Utilisez " -ForegroundColor Gray -NoNewline
    Write-Host "-ShowSensitiveObjects" -ForegroundColor Cyan -NoNewline
    Write-Host " pour inclure TOUS les objets sensibles (comptes, DC, groupes, GPO-DC)" -ForegroundColor Gray
    Write-Host ""
}

if ($UnlimitedSearch.IsPresent) {
    $MaxSearchObjects = 300000
    $MaxSearchGroups  = 100000
}
