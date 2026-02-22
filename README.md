
Under development

Use at your own risk

-----
![PowerShell Gallery Version](https://img.shields.io/powershellgallery/v/ModernActiveDirectoryEnhanced)
![Language](https://img.shields.io/badge/Powershell-100.0%25-blue)
![License](https://img.shields.io/bower/l/Bootstrap?style=plastic)
![Platform](https://img.shields.io/badge/Platform-Windows-brightgreen)
![PowerShell Gallery Downloads](https://img.shields.io/powershellgallery/dt/ModernActiveDirectoryEnhanced?color=orange&label=Download%20Powershell%20Gallery)


# ModernActiveDirectoryEnhanced

![Logo](Pictures/Logo.png "Logo")

### Version 2.0.0 – Enhanced Fork by JCh
> 🔁 Fork amélioré de [Modern Active Directory](https://github.com/dakhama-mehdi/Modern_ActiveDirectory)
> par [Mehdi Dakhama](https://github.com/dakhama-mehdi)


---

# 🔍 Présentation

**ModernActiveDirectoryEnhanced** 
> est un fork amélioré de [Modern Active Directory](https://github.com/dakhama-mehdi/Modern_ActiveDirectory)
> par [Mehdi Dakhama](https://github.com/dakhama-mehdi)

## 🚀 Nouveautés version 2.0.0 (Enhanced)

- Nouveau nom de module : **ModernActiveDirectoryEnhanced**
- Fonction principale renommée : **Get-MADReport**
- **Moteur EoL intégré** : suivi Windows, Windows Server, Linux, macOS, ...
- Base de données JSON externe (`eol-database.json`) synchronisable via API [endoflife.date](https://endoflife.date)
- Nouvelle fonction : **Update-ADEoLDatabase** / alias **Update-EoL**
- Fonctions de pré-vérification : `PreCheck-Functions.ps1`
- Structure nettoyée et refactorisée sans hardcode

---

# 🛠️ Prérequis

- Windows Server ou Windows 10/11
- PowerShell 5.1+
- Module ActiveDirectory (RSAT)
- **PSWriteHTML** ≥ 0.0.180
- **PSWriteExcel** ≥ 0.1.15

---

# 📦 Installation depuis Powershell Gallery


### Importer le module
```powershell
Import-Module ModernActiveDirectoryEnhanced
```

### Vérifier l'import
```powershell
Get-Module ModernActiveDirectoryEnhanced
```

---

# Installation depuis GitHub


### Cloner le dépôt
```powershell
git clone https://github.com/JCh-Labs/Modern_ActiveDirectoryEnhanced/Modern_ActiveDirectory_Enhanced.git
```

### Importer le module
```powershell
Import-Module .\Modern_ActiveDirectory_Enhanced\ModernActiveDirectoryEnhanced.psd1
```
### Vérifier l'import
```powershell
Get-Module ModernActiveDirectoryEnhanced
```

```
```

---

# 🧪 Utilisation


### PreCheck
```powershell
Get-MADReport -PreCheck
```

### MAJ de la Database eol
```powershell
Update-ADEoLDatabase
# ou via alias :
Update-EoL
```

### Exemple de generation d'un rapport personnalisé multipage sans ou avec données sensitives
```powershell
Get-MADReport -ReportTitle "v1.9.9.02 : Overview AD Report" -SavePath "C:\Temp\MultiPage\" -MaxSearchObjects 10000 -MaxSearchGroups 10000 -OUSearchScope "Subtree" -LimitedView:$false -ShowSensitiveObjects -ShowEoLOverview
Get-MADReport -ReportTitle "v1.9.9.02 : Overview AD Report" -SavePath "C:\Temp\MultiPage\" -MaxSearchObjects 10000 -MaxSearchGroups 10000 -OUSearchScope "Subtree" -LimitedView:$false -ShowEoLOverview
```

### Exemple de generation d'un rapport personnalisé Monopage sans ou avec données sensitives
```powershell
Get-MADReport -ReportTitle "v1.9.9.02 : Overview AD Report" -SavePath "C:\Temp\OnePage\" -MaxSearchObjects 10000 -MaxSearchGroups 10000 -OUSearchScope "Subtree" -LimitedView:$false -ShowSensitiveObjects -ShowEoLOverview -SinglePageReport
Get-MADReport -ReportTitle "v1.9.9.02 : Overview AD Report" -SavePath "C:\Temp\OnePage\" -MaxSearchObjects 10000 -MaxSearchGroups 10000 -OUSearchScope "Subtree" -LimitedView:$false -ShowEoLOverview -SinglePageReport
```


---

# 🧩 Fonctionnalités

- 🔎 Analyse complète de l'Active Directory
- 📊 Rapport HTML interactif (PSWriteHTML)
- 📁 Export Excel (PSWriteExcel)
- 🛡️ Filtrage intelligent des comptes et groupes sensibles
- ⏱️ Suivi End-of-Life des OS (Windows, Server, Linux, macOS)
- 📈 Statistiques globales et tableaux de bord
- 🧱 Architecture modulaire extensible

---

# 📁 Structure du projet

```
ModernActiveDirectoryEnhanced/
├── Sources/
│   ├── ModernActiveDirectoryEnhanced.psm1
│   ├── ModernActiveDirectoryEnhanced.psd1
│   ├── EoL-Functions.ps1
│   ├── EoL-Versioning.ps1
│   ├── PreCheck-Functions.ps1
│   └── eol-database.json
├── Examples/
├── Pictures/
├── Docs/
├── LICENSE
└── README.md
```

---

# 🧑‍💻 Auteur

**JCh** — JCh Labs, 2026
[github.com/JCh-Labs](https://github.com/JCh-Labs/)

---

## 📜 Crédit original

Fork du module **Modern Active Directory** par :
**Mehdi Dakhama** — [github.com/dakhama-mehdi/Modern_ActiveDirectory](https://github.com/dakhama-mehdi/Modern_ActiveDirectory)

---

## 📄 Licence

Voir fichier [LICENSE](LICENSE).