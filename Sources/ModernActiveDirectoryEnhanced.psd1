@{

# -------------------------------------------------------------------
# MODULE MANIFEST – ModernActiveDirectoryEnhanced
# Version : 1.9.9.07
# Author  : JCh – JCh Labs
# Fork of Modern Active Directory by Mehdi Dakhama
# -------------------------------------------------------------------

RootModule    = 'ModernActiveDirectoryEnhanced.psm1'
ModuleVersion = '1.9.9.07'
GUID          = 'd3f4c1f0-2a4b-4c9f-9f0d-8b7e3b0c4e12'

Author      = 'JCh'
CompanyName = 'JCh Labs'
Copyright   = '(c) 2026 JCh. Based on Modern_ActiveDirectory by Mehdi Dakhama.'

Description = 'Enhanced fork of ModernActiveDirectory.'

PowerShellVersion = '5.1'

RequiredModules = @(
    @{ ModuleName = 'PSWriteHTML';  ModuleVersion = '0.0.180'; Guid = 'a7bdf640-f5cb-4acf-9de0-365b322d245c' }
    @{ ModuleName = 'PSWriteExcel';  ModuleVersion = '0.1.15'; Guid = '82232c6a-27f1-435d-a496-929f7221334b' }
)

FunctionsToExport = @('Get-MADReport', 'Update-ADEoLDatabase')
CmdletsToExport   = @()
VariablesToExport = @()
AliasesToExport   = @('Update-EoL')

PrivateData = @{
    PSData = @{

        Tags = @(
            'ActiveDirectory',
            'AD-Report',
            'ModernActiveDirectoryEnhanced',
            'Get-MADReport',
            'HTML-Report',
            'EoL-Tracking'
        )

        LicenseUri = 'https://github.com/JCh-Labs/ModernActiveDirectoryEnhanced/blob/main/LICENSE'
        ProjectUri = 'https://github.com/JCh-Labs/ModernActiveDirectoryEnhanced'
        IconUri    = 'https://raw.githubusercontent.com/JCh-Labs/ModernActiveDirectoryEnhanced/main/Pictures/MAD_Logo.png'

        ReleaseNotes = @'
2.0.0 - Enhanced fork by JCh Labs
* Fork of Modern Active Directory (original by Mehdi Dakhama / Alphorm)
* Module renamed: ModernActiveDirectoryEnhanced
* Main function renamed: Get-MADReport
* New: Complete EoL tracking engine (EoL-Functions.ps1)
* New: External JSON database (eol-database.json) with API sync via endoflife.date
* New: Update-ADEoLDatabase / Update-EoL for database refresh
* New: PreCheck-Functions.ps1 for pre-execution validation
* New: Dashboard
* New: No HarCode
* Removed legacy code signature block
* Cleaned and refactored module structure
'@
    }
}

HelpInfoURI = 'https://github.com/JCh-Labs/ModernActiveDirectoryEnhanced/main/Docs'

}