# =============================================================================
# MAD-OSFamilyMap.ps1
# MAPPING FAMILLE OS — source de vérité unique
#
# Utilisé par :
#   MAD-Computers.ps1  → dispatch dans ClientList / ServerList / DiversList
#   EoL-Functions.ps1  → champ 'type' lors de Update-ADEoLDatabase
#
# Valeurs possibles : 'Client' | 'Server' | 'Divers'
# Pour ajouter ou recatégoriser un OS : modifier uniquement ce fichier.
# =============================================================================

$script:OSFamilyMap = @{

    # --- Windows Client ---
    'Windows 11'          = 'Client'
    'Windows 10'          = 'Client'
    'Windows 8.1'         = 'Client'
    'Windows 8'           = 'Client'
    'Windows 7'           = 'Client'
    'Windows Vista'       = 'Client'
    'Windows XP'          = 'Client'
    'Windows Embedded'    = 'Client'

    # --- Windows Server ---
    'Windows Server'      = 'Server'
    'Windows Server 2025' = 'Server'
    'Windows Server 2022' = 'Server'
    'Windows Server 2019' = 'Server'
    'Windows Server 2016' = 'Server'
    'Windows Server 2012' = 'Server'
    'Windows Server 2008' = 'Server'
    'Windows Server 2003' = 'Server'
    'Windows Server 2000' = 'Server'

    # --- macOS ---
    'macOS'               = 'Client'

    # --- Linux ---
    'Ubuntu'              = 'Server'
    'Debian'              = 'Server'
    'RHEL'                = 'Server'
    'CentOS'              = 'Server'
    'SUSE'                = 'Server'
    'SLES'                = 'Server'
    'Fedora'              = 'Server'

    # --- Divers (hyperviseurs, plateformes spéciales) ---
    'ESXi'                = 'Divers'
    'VMware'              = 'Divers'
    'Hyper-V'             = 'Divers'
    'XenServer'           = 'Divers'
    'Proxmox'             = 'Divers'
    'ChromeOS'            = 'Divers'
    'Android'             = 'Divers'
    'FreeBSD'             = 'Divers'
    'Unix'                = 'Divers'

}
