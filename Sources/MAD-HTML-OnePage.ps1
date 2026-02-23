function HTMLOnePage {
    #region OnePageHTML generatehtml

    # Helper : construit une ligne pour les tableaux Lifecycle (partagé avec MultiPage)
    function Build-LifecycleRow {
        param($osItem, $WarningStatusName)

        $eolInfo = Get-OSEoLInfo -OSName $osItem.OS

        # Déterminer le statut principal depuis les compteurs
        $primaryStatus = 'Unknown'
        if     ($osItem.EOL -gt 0)                    { $primaryStatus = 'EOL' }
        elseif ($osItem.$WarningStatusName -gt 0)     { $primaryStatus = $WarningStatusName }
        elseif ($osItem.Supported -gt 0)              { $primaryStatus = 'Supported' }

        # Construire EoLDate et DaysUntilEoL
        $eolDateDisplay = 'Unknown'
        $daysInfo       = ''

        if ($eolInfo) {
            $rawEol = $eolInfo.eol_date
            if ($rawEol -and $rawEol -ne $false -and $rawEol -ne 'False' -and $rawEol -ne 'N/A') {
                # Date connue
                try {
                    $eolDate      = [DateTime]::Parse($rawEol)
                    $daysUntilEoL = ($eolDate - (Get-Date)).Days
                    $eolDateDisplay = $rawEol
                    $daysInfo = if ($daysUntilEoL -gt 0) {
                        "$daysUntilEoL days remaining"
                    } elseif ($daysUntilEoL -eq 0) {
                        "Ends today"
                    } else {
                        "Ended $([Math]::Abs($daysUntilEoL)) days ago"
                    }
                } catch { $eolDateDisplay = $rawEol }
            } else {
                # Clé en DB mais eol_date = False → date non annoncée
                # On n'écrase PAS $primaryStatus : les compteurs sont la source de vérité.
                $eolDateDisplay = 'No date announced'
                $daysInfo       = 'No date announced'
                if ($primaryStatus -eq 'Unknown' -or $primaryStatus -eq 'Supported') {
                    $primaryStatus = 'Supported (no end of life announced)'
                }
            }
        } elseif ($primaryStatus -eq 'Unknown') {
            $eolDateDisplay = 'Unknown'
            $daysInfo       = ''
        }

        return [PSCustomObject]@{
            'OSName'         = $osItem.OS
            'Total'          = $osItem.Total
            'EoLDate'        = $eolDateDisplay
            'DaysUntilEoL'   = $daysInfo
            'PrimaryStatus'  = $primaryStatus
            'Supported'      = $osItem.Supported
            'WarningStatus'  = $osItem.$WarningStatusName
            'EOL'            = $osItem.EOL
        }
    }
    $time = (get-date)
    Write-Verbose "HTML - Generation du rapport final (OnePage)"
    $htmlParams = @{ TitleText = $ReportTitle; Online = $true; FilePath = $OutputPath }
    # ANOMALIE4 FIX : $ShowReport est maintenant [bool] — evaluation directe (plus de .IsPresent)
    if ($ShowReport) { $htmlParams["ShowHTML"] = $true }
    New-HTML @htmlParams {
        New-HTMLHeader {
            New-HTMLSection -Invisible {
                New-HTMLPanel -Invisible -AlignContentText center -BackGroundColor SlateGray {
                    New-HTMLText -Text $ReportTitle -FontSize 22 -Color White -FontWeight bold
                }
            }
        }

        #Page Dashboard    
        New-HTMLTab -Name 'Dashboard' -IconRegular chart-bar  {   
            New-HTMLTabStyle  -BackgroundColorActive teal    
            New-HTMLSection  -Name 'Block infos' -Invisible  {
                New-HTMLPanel -Margin 10 -Width "80%" {
                    New-HTMLPanel -BackgroundColor silver  {
                        New-HTMLText -TextBlock  {
                            New-HTMLText -Text  "Domain : $Forest" -Alignment justify -FontSize 15 -FontWeight bold
                            New-HTMLText -Text  "AD Recycle Bin : $ADRecycleBin" -Alignment justify -FontSize 15 -FontWeight bold
                            New-HTMLText -LineBreak
                            New-HTMLText -Text "FSMO Roles" -Alignment center -FontSize 15 -FontWeight bold
                            New-HTMLText -Text  "Infra : $InfrastructureMaster" -Alignment justify -FontSize 15 -FontWeight bold
                            New-HTMLText -Text  "Rid : $RIDMaster" -Alignment justify -FontSize 15 -FontWeight bold
                            New-HTMLText -Text  "PDC  : $PDCEmulator" -Alignment justify -FontSize 15 -FontWeight bold
                            New-HTMLText -Text  "Naming : $DomainNamingMaster" -Alignment justify -FontSize 15 -FontWeight bold
                            New-HTMLText -Text  "Schema : $SchemaMaster" -Alignment justify -FontSize 15 -FontWeight bold

                        }
                    }
                }
        # Panel Domain Trusts (en dessous de Domain)
        New-HTMLPanel -BackgroundColor lightblue -BorderRadius 10px {
            New-HTMLText -TextBlock {
                if ($TrustsStats.Total -gt 0) {
                    New-HTMLText -Text "Domain Trusts" -Alignment center -FontSize 15 -FontWeight bold -Color black
                    New-HTMLText -LineBreak
                    New-HTMLText -Text "Total: $($TrustsStats.Total)" -Alignment left -FontSize 13
                    New-HTMLText -Text "Internal: $($TrustsStats.IntraForest)" -Alignment left -FontSize 13
                    New-HTMLText -Text "External: $($TrustsStats.External)" -Alignment left -FontSize 13
                    if ($TrustsStats.External -gt 0) {
                        $unsecured = $TrustsStats.External - $TrustsStats.WithSIDFiltering
                        if ($unsecured -gt 0) {
                            New-HTMLText -Text "[!] $unsecured without SID Filtering" -Alignment left -FontSize 12 -Color red
                        }
                    }
                } else {
                    New-HTMLText -Text "Domain Trusts" -Alignment center -FontSize 15 -FontWeight bold -Color gray
                    New-HTMLText -LineBreak
                    New-HTMLText -Text "No trusts configured" -Alignment center -FontSize 13 -Color gray -FontStyle italic
                    New-HTMLText -Text "(Single domain forest)" -Alignment center -FontSize 11 -Color darkgray -FontStyle italic
                    New-HTMLText -LineBreak
                    New-HTMLText -LineBreak
                    New-HTMLText -LineBreak
                    New-HTMLText -LineBreak
                    New-HTMLText -LineBreak
                }
            }
        }

                New-HTMLPanel -Margin 10  {
                    New-HTMLPanel -BackgroundColor lightgreen -AlignContentText right -BorderRadius 10px  {
                        New-HTMLText -TextBlock {
                            New-HTMLText -Text $UserDisabled -Alignment justify -FontSize 25 -FontWeight bold 
                            New-HTMLText -Text 'Disabled Users' -Alignment justify -FontSize 15 
                            New-HTMLTag -Tag 'i' -Attributes @{ class = "fas fa-user-slash fa-3x" } 
                        } 
                    }
                    New-HTMLPanel -BackgroundColor yellowgreen -AlignContentText right -BorderRadius 10px {
                        New-HTMLText -TextBlock {
                            New-HTMLText -Text $userinactive -Alignment justify -FontSize 25 -FontWeight bold
                            New-HTMLText -Text "Users not logged in Last $UserInactiveDays Days" -Alignment justify -FontSize 15
                            New-HTMLTag -Tag 'span' -Attributes @{ class = "fas fa-user-clock fa-3x" }
                        }                 
                    }
                }
                New-HTMLPanel -Margin 10 {
                    New-HTMLPanel -BackgroundColor lightpink  -AlignContentText right -BorderRadius 10px {
                        New-HTMLText -TextBlock {
                            New-HTMLText -Text $neverlogedenabled -Alignment left -FontSize 25 -FontWeight bold
                            New-HTMLText -Text 'Users Never Logged' -Alignment left -FontSize 15
                            New-HTMLTag -Tag 'i' -Attributes @{ class = "fas fa-house-user fa-3x" } 
                        }
                    }
                    New-HTMLPanel -BackgroundColor palevioletred  -AlignContentText right -BorderRadius 10px  {
                        New-HTMLText -TextBlock {
                            New-HTMLText -Text $usercomputerdeleted -Alignment left -FontSize 25 -FontWeight bold
                            New-HTMLText -Text 'Users/computer in RecycleBin' -Alignment left -FontSize 15
                            New-HTMLTag -Tag 'i' -Attributes @{ class = "fas fa-trash-alt fa-3x" } 
                        }
                    }
                }
                New-HTMLPanel -Margin 10 {
                    New-HTMLPanel -BackgroundColor lightblue  -AlignContentText right -BorderRadius 10px {
                        New-HTMLText -TextBlock {
                            New-HTMLText -Text $DomainAdminTable -Alignment left -FontSize 25 -FontWeight bold
                            New-HTMLText -Text 'Domain Admins' -Alignment left -FontSize 15
                            New-HTMLTag -Tag 'i' -Attributes @{ class = "fas fa-user-edit fa-3x" } 
                        }
                    }
                    New-HTMLPanel -BackgroundColor steelblue -AlignContentText right -BorderRadius 10px {
                        New-HTMLText -TextBlock {
                            New-HTMLText -Text $EnterpriseAdminTable -Alignment left -FontSize 25 -FontWeight bold
                            New-HTMLText -Text 'Entreprise Admins' -Alignment left -FontSize 15
                            New-HTMLTag -Tag 'i' -Attributes @{ class = "fas fa-user-tie fa-3x" } 
                            }
                    }      
                }     
                New-HTMLPanel -Margin 10  {
                    New-HTMLPanel -BackgroundColor bisque -AlignContentText right -BorderRadius 10px  {
                        New-HTMLText -TextBlock {
                            New-HTMLText -Text $totalEOL -Alignment left -FontSize 25 -FontWeight bold
                            New-HTMLText -Text 'Computers Not Supported' -Alignment left -FontSize 15
                            New-HTMLTag -Tag 'i' -Attributes @{ class = "fas fa-laptop-medical fa-3x" } 
                        }
                    }
                    New-HTMLPanel -BackgroundColor orange -AlignContentText right -BorderRadius 10px  {
                        New-HTMLText -TextBlock {
                            # BUG2 FIX : guard $nogpomod pour eviter NullRef sur .Count
                            if ($nogpomod) {
                                New-HTMLText -Text 'N/A' -Alignment left -FontSize 25 -FontWeight bold
                            } else {
                                New-HTMLText -Text $($GPO_NotLinked.Count) -Alignment left -FontSize 25 -FontWeight bold
                            }
                            New-HTMLText -Text 'GPOs not Linked' -Alignment left -FontSize 15
                            New-HTMLTag -Tag 'i' -Attributes @{ class = "fas fa-scroll fa-3x" } 
                        }
                    }
                }  
                New-HTMLPanel -Margin 10 {
                    New-HTMLPanel -BackgroundColor paleturquoise -AlignContentText right -BorderRadius 10px {
                        New-HTMLText -TextBlock {
                            New-HTMLText -Text $($ExpiringAccountsTable) -Alignment left -FontSize 25 -FontWeight bold
                            New-HTMLText -Text 'Expired Account and still Enabled' -Alignment left -FontSize 15
                            New-HTMLTag -Tag 'i' -Attributes @{ class = "fas fa-umbrella-beach fa-3x" } 
                        }
                    }
                    New-HTMLPanel -BackgroundColor mediumaquamarine -AlignContentText right -BorderRadius 10px {
                        New-HTMLText -TextBlock {
                            New-HTMLText -Text $expiredsoon -Alignment left -FontSize 25 -FontWeight bold
                            New-HTMLText -Text "Account Expiring Soon (within $UserPasswordExpireDays days)" -Alignment left -FontSize 15
                            New-HTMLTag -Tag 'i' -Attributes @{ class = "fas fa-bell fa-3x" } 
                        }
                    }
                }  
            }
                
            New-HTMLSection  -HeaderBackGroundColor teal -HeaderTextAlignment left  {
                New-HTMLSection -Name "Created Machines / Users By date in last $RecentObjectsDays Days" -Invisible  {
                    New-HTMLPanel  {
                        New-HTMLChart -Title "Created Machines / Users By date in last $RecentObjectsDays Days" -TitleAlignment center -Height 280 {                 
                            New-ChartAxisX -Names $(($barcreateobject).date)
                            New-ChartLine -Name 'User created' -Value $(($barcreateobject).Nbr_users)
                            New-ChartLine -Name 'PC Created' -Value $(($barcreateobject).Nbr_PC)                  
                        }
                    }    
                }
                New-HTMLSection -HeaderBackGroundColor teal -Invisible -Width "70%" {    
                    New-HTMLPanel  {
                        New-HTMLChart -Title 'Created Objects VS Deleted' -TitleAlignment center -Height "100%" {
                            New-ChartToolbar -Download pan
                            New-ChartBarOptions -Gradient -Vertical
                            New-ChartLegend -Name 'Created users', 'Created Machines', 'Deleted Users/machines' 
                            New-ChartBar -Name "Result Current $RecentObjectsDays Days" -Value $lastcreatedusers, $lastcreatedpc, $deletedobject
                        }
                    }  
                New-HTMLSection -Name 'Objects in Default OU'  -Width "80%"  {
                        New-HTMLChart -Gradient  {
                            New-ChartLegend -LegendPosition bottom 
                            New-ChartDonut -Name 'Users' -Value $DefaultUsersinDefaultOUTable.Count
                            New-ChartDonut -Name 'Computers' -Value $DefaultComputersinDefaultOU
                        }
                    }
                }     
            }
            
            New-HTMLSection -Invisible {
                New-HTMLSection -Name "Last Locked Users" -HeaderBackGroundColor DarkGreen  -HeaderTextAlignment left {
                    new-htmlTable -HideFooter -DataTable $Unlockusers -HideButtons -DisableSearch -TextWhenNoData 'No locked users found'
                }
                New-HTMLSection -Name 'UPN Suffix' -HeaderTextAlignment center -HeaderBackGroundColor Black -Width "60%"  {
                    New-HTMLTable -DataTable $DomainTable -HideButtons -DisableInfo -DisableSearch -HideFooter -TextWhenNoData 'Information: No UPN Suffixes were found'
                }
                New-HTMLSection -Width "60%" -HeaderBackGroundColor Teal -name 'Groups Without members'  {
                    New-HTMLGage -Label 'Empty Groups' -MinValue 0 -MaxValue $totalgroups -Value $Groupswithnomembership -ValueColor Black -LabelColor Black -Pointer
                }
                New-HTMLSection -Name "Accounts Created in $UserCreatedDays Days or Less" -HeaderBackGroundColor DarkBlue {
                            new-htmlTable -HideFooter -DataTable $NewCreatedUsersTable -DisableInfo -HideButtons -PagingLength 6 -DisableSearch -TextWhenNoData 'Information: No new users have been recently created'
                }
            }
            New-HTMLSection -Name 'Objects in Default OUs' -Invisible  {
                New-HTMLSection -Name 'AD Objects in Recycle Bin' -HeaderBackGroundColor skyblue -Width "70%" {
                    New-HTMLTableOption -DataStore JavaScript -DateTimeFormat 'yyyy-MM-dd' -ArrayJoin -ArrayJoinString ','
                    New-htmlTable -HideFooter -DataTable $ADObjectTable -PagingLength 12 -Buttons csvHtml5 
                } 
                New-HTMLSection -Name 'Computers in default OU' -HeaderBackGroundColor teal   {
                    New-HTMLTableOption -DataStore JavaScript -DateTimeFormat 'yyyy-MM-dd' -ArrayJoin -ArrayJoinString ','
                    New-htmlTable -HideFooter -DataTable $DefaultComputersinDefaultOUTable -PagingLength 12 -HideButtons 
                }
                New-HTMLSection -Name 'Users in Default OU' -HeaderBackGroundColor brown {
                    New-HTMLTableOption -DataStore JavaScript -DateTimeFormat 'yyyy-MM-dd' -ArrayJoin -ArrayJoinString ','
                    New-HTMLTable -HideFooter -DataTable $DefaultUsersinDefaultOUTable -PagingLength 12 -HideButtons 
                }
            }    
        }
        
        #Page Groups    
        New-HTMLTab -Name 'Groups' -IconSolid user-alt   {
            New-HTMLSection -Invisible {
                New-HTMLPanel {
                    new-htmlTable -HideFooter -HideButtons -DataTable $TOPGroupsTable -DisablePaging -DisableSelect -DisableStateSave -DisableInfo -DisableSearch 
                }
            }          
            New-HTMLSection -Name 'Active Directory Groups With Members' -HeaderBackGroundColor teal -HeaderTextAlignment left {
                New-HTMLPanel {
                    New-HTMLTableOption -DataStore JavaScript -DateTimeFormat 'yyyy-MM-dd' -ArrayJoin -ArrayJoinString ',' -BoolAsString
                    new-htmlTable -HideFooter -DataTable $Table -TextWhenNoData 'Information: No Groups were found' -DataTableID 'adGroupsTable'
                }
            }
            New-HTMLSection -HeaderText 'Active Directory Groups Chart' -HeaderBackGroundColor teal -HeaderTextAlignment left {
                New-HTMLPanel -Invisible {
                    New-HTMLChart -Gradient -Title 'Group Types' -TitleAlignment center -Height 200  {
                        New-ChartTheme -Palette palette2 
                        New-ChartPie -Name 'Security Groups' -Value $SecurityCount
                        New-ChartPie -Name 'Distribution Groups' -Value $DistroCount                                    
                    }
                }
                New-HTMLPanel -Invisible {
                    New-HTMLChart -Gradient -Title 'Custom vs Default Groups' -TitleAlignment center -Height 200  {
                        New-ChartTheme -Palette palette1
                        New-ChartPie -Name 'Custom Groups' -Value $CustomGroup
                        New-ChartPie -Name 'Default Groups' -Value ($DefaultSGs.count)
                    }
                }
                New-HTMLPanel -Invisible {
                    New-HTMLChart -Gradient -Title 'Group Membership' -TitleAlignment center -Height 200  {
                        New-ChartTheme -Palette palette3 
                        New-ChartPie -Name 'With Members' -Value $Groupswithmemebrship
                        New-ChartPie -Name 'No Members' -Value $Groupswithnomembership  
                    }
                }
                New-HTMLPanel -Invisible {
                    New-HTMLChart -Gradient -Title 'Group Protected From Deletion' -TitleAlignment center -Height 200 {
                        New-ChartTheme -Palette palette4
                        New-ChartPie -Name 'Not Protected' -Value $GroupsNotProtected
                        New-ChartPie -Name 'Protected' -Value $GroupsProtected                   
                    }
                }
            } 

        New-HTMLSection -Name 'Membres détaillés des groupes (récursif)' -HeaderBackGroundColor teal -HeaderTextAlignment left {
            New-HTMLPanel {
                New-HTMLTableOption -DataStore JavaScript -DateTimeFormat 'yyyy-MM-dd' -ArrayJoin -ArrayJoinString ',' -BoolAsString
                New-HTMLText -Text '<style>
#adGroupsTable tbody tr { cursor: pointer; }
#adGroupsTable tbody tr.grp-selected td { background: #b2dfdb !important; font-weight: bold; }
</style>
<script>
(function(){
  document.addEventListener(''DOMContentLoaded'', function(){
    setTimeout(function(){
      var dtTop = $.fn.dataTable.isDataTable(''#adGroupsTable'') ? $(''#adGroupsTable'').DataTable() : null;
      var dtBot = $.fn.dataTable.isDataTable(''#adGroupMembersTable'') ? $(''#adGroupMembersTable'').DataTable() : null;
      if(!dtTop || !dtBot) return;
      var selectedGroups = [];
      var srcColIdx = -1;
      dtBot.columns().header().each(function(h,i){ if(h.textContent.trim()===''Source Group'') srcColIdx=i; });
      function applyFilter() {
        if(selectedGroups.length === 0) {
          if(srcColIdx >= 0) dtBot.columns(srcColIdx).search('''', true, false).draw();
          try { dtBot.searchBuilder.rebuild({ criteria: [], logic: ''AND'' }); } catch(e){}
          return;
        }
        if(srcColIdx >= 0) {
          var regex = selectedGroups.map(function(g){
            return ''^'' + $.fn.dataTable.util.escapeRegex(g) + ''$'';
          }).join(''|'');
          dtBot.columns(srcColIdx).search(regex, true, false).draw();
        }
        try {
          dtBot.searchBuilder.rebuild({
            criteria: selectedGroups.map(function(g){
              return { condition: ''='', data: ''Source Group'', origData: ''Source Group'', type: ''string'', value: [g], value1: g };
            }),
            logic: ''OR''
          });
        } catch(e){}
      }
      $(''#adGroupsTable tbody'').on(''click'', ''tr'', function(e){
        var rowData = dtTop.row(this).data();
        if(!rowData) return;
        var groupName = rowData[''Name''] !== undefined ? rowData[''Name''] : rowData[0];
        var idx = selectedGroups.indexOf(groupName);
        var isSelected = $(this).hasClass(''grp-selected'');
        if(!e.ctrlKey && !e.metaKey) {
          if(isSelected && selectedGroups.length === 1) {
            selectedGroups = [];
            $(''#adGroupsTable tbody tr'').removeClass(''grp-selected'');
          } else {
            selectedGroups = [groupName];
            $(''#adGroupsTable tbody tr'').removeClass(''grp-selected'');
            $(this).addClass(''grp-selected'');
          }
        } else {
          if(isSelected) { selectedGroups.splice(idx, 1); $(this).removeClass(''grp-selected''); }
          else { selectedGroups.push(groupName); $(this).addClass(''grp-selected''); }
        }
        applyFilter();
      });
    }, 1000);
  });
})();
</script>'
                New-HTMLTable -DataTable $GroupMembersDetailTable -DefaultSortColumn 'Source Group' -HideFooter -TextWhenNoData 'Aucun membre utilisateur trouvé' -DataTableID 'adGroupMembersTable' {
                    New-HTMLTableCondition -Name 'Enabled' -Value 'False' -BackgroundColor LightCoral -Color White -ComparisonType string
                    New-HTMLTableCondition -Name 'Privileged' -Value 'Yes' -BackgroundColor Orange -Color White -ComparisonType string
                    New-HTMLTableCondition -Name 'Password Never Expired' -Value 'True' -BackgroundColor LightYellow -ComparisonType string
                }
            }
        }
        }    

        #Page Groups Without Members
        New-HTMLTab -Name 'Groups Without Members' -IconSolid users-slash {
            New-HTMLSection -Name 'Informations' -Invisible  {
                New-HTMLPanel {
                    new-htmlTable  -DataTable $Groupsnomembers
                }
            }
        }                
        
        #Page OU
        New-HTMLTab -Name 'Organizational Units' -IconRegular folder {          
            New-HTMLSection -Name 'Organizational Units infos' -Invisible {
                New-HTMLPanel {
                    new-htmlTable -HideFooter -DataTable $OUTable -TextWhenNoData 'Information: No OUs were found'
                }
            }      
            New-HTMLSection -HeaderText "Organizational Units Charts" -HeaderBackGroundColor teal -HeaderTextAlignment left {
                New-HTMLPanel  {
                    New-HTMLChart -Gradient -Title 'OU Gpos Links' -TitleAlignment center -Height 200  {
                        New-ChartTheme -Palette palette2 
                        New-ChartPie -Name "OUs with GPO's linked" -Value $OUwithLinked
                        New-ChartPie -Name "OUs with no GPO's linked" -Value $OUwithnoLink                                      
                    }
                }
                New-HTMLPanel  {
                    New-HTMLChart -Gradient -Title 'Organizations Units Protected from deletion' -TitleAlignment center -Height 200  {
                        New-ChartTheme -Palette palette1
                        New-ChartPie -Name "Protected" -Value $OUProtected
                        New-ChartPie -Name "Not Protected" -Value $OUNotProtected
                    }
                }
            }                
        }     

        # BUG2 FIX : tab GPO conditionnel — $GPOs/$GPO_NotLinked/$GPO_Details
        # n'existent que si GPMC est present ($nogpomod=$false).
        if (-not $nogpomod) {
        #Page GPO
        New-HTMLTab -Name 'Group Policy' -IconRegular hourglass {
            New-HTMLSection -Name 'All GPOs'  {
                new-htmlTable  -DataTable $GPOs
            }
            
            # === SECTION DÉTAILLÉE : Visible seulement avec -ShowSensitiveObjects ===
            if (-not $LimitedView -or $ShowSensitiveObjects.IsPresent) {
                New-HTMLSection -Name 'GPO Application Scope - Sensitive Objects (DC-Linked)' -HeaderBackGroundColor DarkCyan {
                    New-HTMLPanel {
                        New-HTMLText -Text "[!]  SENSITIVE INFORMATION" -FontSize 16 -FontWeight bold -Color Red
                        New-HTMLText -Text "This section reveals WHERE each GPO is applied in your AD structure." -FontSize 12 -Color Gray
                        New-HTMLText -Text "Includes GPO linked to Domain Controllers OU. Only visible when using -ShowSensitiveObjects flag." -FontSize 12 -Color DarkGray
                        New-HTMLTable -DataTable $GPO_Details -PagingLength 20 {
                            New-TableCondition -Name 'Link Count' -ComparisonType number -Operator gt -Value 5 -BackgroundColor Orange -Color White -Row
                            New-TableCondition -Name 'Link Count' -ComparisonType number -Operator eq -Value 1 -BackgroundColor LightGreen -Row
                            New-TableCondition -Name 'Status' -ComparisonType string -Operator eq -Value 'AllSettingsDisabled' -BackgroundColor Red -Color White -Row
                        } -SearchPane -Filtering
                    }
                }
            }
            
            New-HTMLSection -Name 'GPO Status' -HeaderBackGroundColor Teal {
                New-HTMLSection -name 'Unlinked GPOs (Orphaned)' -HeaderBackGroundColor Teal {
                    New-HTMLTable -DataTable $GPO_NotLinked 
                }
                New-HTMLSection -Name 'Linked vs Unlinked GPOs' -HeaderBackGroundColor Teal  {
                    New-HTMLChart {
                        New-ChartLegend -LegendPosition bottom 
                        New-ChartBarOptions -Gradient
                        New-ChartDonut -Name 'Unlinked' -Value $GPO_NotLinked.Count -Color silver
                        New-ChartDonut -Name 'Linked' -Value $GPOs.Count -Color orange
                    }
                }
            }
        }          
        } # Fin if (-not $nogpomod)

        #Page Trusts
        New-HTMLTab -Name 'Domain Trusts' -IconRegular handshake {
            
            # Statistics Panel
            New-HTMLSection -Name 'Trust Overview' -HeaderBackGroundColor DarkCyan {
                New-HTMLPanel {
                    if ($TrustsStats.Total -gt 0) {
                        New-HTMLText -Text "Domain Trust Relationships" -FontSize 16 -FontWeight bold
                    } else {
                        New-HTMLText -Text "No Domain Trusts Configured" -FontSize 16 -FontWeight bold -Color gray
                        New-HTMLText -Text "(Single domain forest)" -FontSize 12 -Color darkgray -FontStyle italic
                    }
                    New-HTMLTable -DataTable @([PSCustomObject]@{
                        'Total Trusts' = $TrustsStats.Total
                        'Internal (Intra-Forest)' = $TrustsStats.IntraForest
                        'External' = $TrustsStats.External
                        'Bidirectional' = $TrustsStats.Bidirectional
                        'Inbound Only' = $TrustsStats.Inbound
                        'Outbound Only' = $TrustsStats.Outbound
                        'Protected (SID Filtering)' = $TrustsStats.WithSIDFiltering
                        'Selective Authentication' = $TrustsStats.WithSelectiveAuth
                    }) -HideFooter -DisableSearch
                }
            }
            
            # Detailed Trust Table
            New-HTMLSection -Name 'Trust Details' -HeaderBackGroundColor Teal {
                New-HTMLPanel {
                    New-HTMLText -Text "Complete list of all trust relationships" -FontSize 12 -Color Gray
                    New-HTMLTable -DataTable $TrustsTable -PagingLength 20 {
                        New-TableCondition -Name 'Security Status' -ComparisonType string -Operator eq -Value 'Review Needed' -BackgroundColor Orange -Color White -Row
                        New-TableCondition -Name 'Security Status' -ComparisonType string -Operator eq -Value 'Hardened' -BackgroundColor Green -Color White -Row
                        New-TableCondition -Name 'Security Status' -ComparisonType string -Operator eq -Value 'Partially Secured' -BackgroundColor '#b8860b' -Color White -Row
                        New-TableCondition -Name 'SID Filtering' -ComparisonType string -Operator eq -Value 'No' -BackgroundColor Orange -Color White -Row
                    } -Filtering -SearchPane
                }
            }
            
            # Charts Section
            New-HTMLSection -Name 'Trust Analysis' -HeaderBackGroundColor Teal {
                
                # Direction Chart
                if ($TrustsStats.Bidirectional -gt 0 -or $TrustsStats.Inbound -gt 0 -or $TrustsStats.Outbound -gt 0) {
                    New-HTMLPanel {
                        New-HTMLChart -Title 'Trust Direction' -TitleAlignment center {
                            New-ChartLegend -LegendPosition bottom
                            New-ChartBarOptions -Gradient
                            if ($TrustsStats.Bidirectional -gt 0) {
                                New-ChartPie -Name 'Bidirectional ↔️' -Value $TrustsStats.Bidirectional -Color '#3498db'
                            }
                            if ($TrustsStats.Inbound -gt 0) {
                                New-ChartPie -Name 'Inbound ⬅️' -Value $TrustsStats.Inbound -Color '#2ecc71'
                            }
                            if ($TrustsStats.Outbound -gt 0) {
                                New-ChartPie -Name 'Outbound ➡️' -Value $TrustsStats.Outbound -Color '#e74c3c'
                            }
                        }
                    }
                }
                
                # Type Chart
                if ($TrustsStats.IntraForest -gt 0 -or $TrustsStats.External -gt 0) {
                    New-HTMLPanel {
                        New-HTMLChart -Title 'Trust Type' -TitleAlignment center {
                            New-ChartLegend -LegendPosition bottom
                            New-ChartBarOptions -Gradient
                            if ($TrustsStats.IntraForest -gt 0) {
                                New-ChartPie -Name 'Internal' -Value $TrustsStats.IntraForest -Color '#27ae60'
                            }
                            if ($TrustsStats.External -gt 0) {
                                New-ChartPie -Name 'External' -Value $TrustsStats.External -Color '#e67e22'
                            }
                        }
                    }
                }
            }
            
            # Security Warning if needed
            if (($TrustsStats.External - $TrustsStats.WithSIDFiltering) -gt 0) {
                New-HTMLSection -Name 'Security Recommendations' -HeaderBackGroundColor Red {
                    New-HTMLPanel {
                        New-HTMLText -Text "[!] SECURITY WARNING" -FontSize 16 -FontWeight bold -Color Red
                        New-HTMLText -Text "Some external trusts do not have SID Filtering enabled." -FontSize 14 -Color DarkRed
                        New-HTMLText -Text "" -LineBreak
                        New-HTMLText -Text "Risk: Without SID Filtering, users from trusted domains could potentially access resources using fake SIDs." -FontSize 12 -Color Gray
                        New-HTMLText -Text "Recommendation: Enable SID Filtering on all external trusts or review if the trust is still necessary." -FontSize 12 -Color Gray
                        New-HTMLText -Text "" -LineBreak
                        New-HTMLText -Text "Reference: Microsoft Security Advisory on Trust Hardening" -FontSize 10 -Color DarkGray
                    }
                }
            }
        }
        # Fin du Tab Trusts

        #Page PrintServer
        New-HTMLTab -Name 'Printer server' -IconSolid print {
            New-HTMLSection -Name 'Informations' -Invisible  {
                New-HTMLPanel {
                    new-htmlTable  -DataTable $printers
                }
            }
        }

        #Page Users  
        New-HTMLTab -Name 'Users' -IconSolid audio-description  {
            New-HTMLSection -Name 'Users Overivew' -Invisible  {
                New-HTMLPanel {
                    new-htmlTable -HideFooter -HideButtons  -DataTable $TOPUserTable -DisableSearch
                }
            }
            New-HTMLSection -Invisible {
            New-HTMLPanel {
                New-HTMLText -Text '<div style="margin:8px 0"><div style="display:flex;gap:6px;align-items:center;flex-wrap:wrap;margin-bottom:4px"><b>&#128100; Inactifs depuis :</b><button onclick="adFilterU(30)" style="border-radius:4px;padding:4px 12px;cursor:pointer;font-size:12px;border:1px solid #ccc;background:#fff3cd">+30j</button><button onclick="adFilterU(60)" style="border-radius:4px;padding:4px 12px;cursor:pointer;font-size:12px;border:1px solid #ccc;background:#ffd8a8">+60j</button><button onclick="adFilterU(90)" style="border-radius:4px;padding:4px 12px;cursor:pointer;font-size:12px;border:1px solid #ccc;background:#f8d7da">+90j</button><button onclick="adFilterU(180)" style="border-radius:4px;padding:4px 12px;cursor:pointer;font-size:12px;border:1px solid #ccc;background:#d9534f;color:white">+180j</button><button onclick="adFilterU(365)" style="border-radius:4px;padding:4px 12px;cursor:pointer;font-size:12px;border:1px solid #ccc;background:#7b1818;color:white">+1 an</button><input id="uCustom" type="number" min="1" max="9999" placeholder="jours" style="width:65px;padding:3px 6px;border-radius:4px;border:1px solid #aaa;font-size:12px;text-align:center"/><button onclick="adCustomU()" style="border-radius:4px;padding:4px 12px;cursor:pointer;font-size:12px;border:1px solid #0077cc;background:#0077cc;color:white">Appliquer</button></div><div style="display:flex;gap:6px;align-items:center;flex-wrap:wrap"><b>&#128197; Crees depuis :</b><button onclick="adFilterUC(7)" style="border-radius:4px;padding:4px 12px;cursor:pointer;font-size:12px;border:1px solid #ccc;background:#d4edda">7j</button><button onclick="adFilterUC(30)" style="border-radius:4px;padding:4px 12px;cursor:pointer;font-size:12px;border:1px solid #ccc;background:#b8daff">30j</button><button onclick="adFilterUC(90)" style="border-radius:4px;padding:4px 12px;cursor:pointer;font-size:12px;border:1px solid #ccc;background:#80bdff">90j</button><button onclick="adFilterUC(365)" style="border-radius:4px;padding:4px 12px;cursor:pointer;font-size:12px;border:1px solid #004085;background:#004085;color:white">1 an</button><button onclick="adClrU()" style="border-radius:4px;padding:4px 12px;cursor:pointer;font-size:12px;border:1px solid #999;background:#e9ecef">&#x2716; Effacer</button><span id="uInfo" style="font-size:12px;color:#555;font-style:italic;margin-left:8px"></span></div></div><script>var adDT_u=null,adDT_pc=null;document.addEventListener("DOMContentLoaded",function(){setTimeout(function(){var eu=document.getElementById("adUserTable");var ep=document.getElementById("adPcTable");if(eu)adDT_u=$(eu).DataTable();if(ep)adDT_pc=$(ep).DataTable();},600);});var adSt={u:null,pc:null};function adFilterU(d){adFilter("u","inactive",d);}function adFilterUC(d){adFilter("u","created",d);}function adFilterPC(d){adFilter("pc","inactive",d);}function adFilterPCC(d){adFilter("pc","created",d);}function adCustomU(){var d=parseInt(document.getElementById("uCustom").value);if(!isNaN(d)&&d>0)adFilter("u","inactive",d);else alert("Nombre invalide");}function adCustomPC(){var d=parseInt(document.getElementById("pcCustom").value);if(!isNaN(d)&&d>0)adFilter("pc","inactive",d);else alert("Nombre invalide");}function adClrU(){adClr("u");}function adClrPC(){adClr("pc");}function getTable(ns){var tid=(ns==="u")?"adUserTable":"adPcTable";var el=document.getElementById(tid);if(!el){var tbls=document.querySelectorAll(".dataTable");return tbls.length>0?$(tbls[(ns==="u")?0:1]).DataTable():null;}return $(el).DataTable();}function adFilter(ns,type,days){var c=new Date();c.setDate(c.getDate()-days);var cs=c.toISOString().split("T")[0];var col;if(ns==="u"){col=(type==="inactive")?"Last Logon Date":"Created";}else{col=(type==="inactive")?"Last Logon Date":"Created Date";}adSt[ns]={type:type,days:days,cutoff:cs,col:col};adRun(ns);document.getElementById(ns+"Info").textContent=((type==="inactive")?"Inactifs avant":"Crees depuis")+" le "+cs+" ("+days+"j)";}function adRun(ns){var s=adSt[ns];if(!s)return;var dt=getTable(ns);if(!dt)return;var ci=-1;dt.columns().header().each(function(h,i){if(h.textContent.trim()===s.col)ci=i;});if(ci<0){console.log("Colonne non trouvee:",s.col);return;}$.fn.dataTable.ext.search.push(function(x,data){var v=data[ci];var m=(s.type==="inactive")?(!v||v<s.cutoff):(v&&v>=s.cutoff);return m;});dt.draw();$.fn.dataTable.ext.search.pop();rebuildSB(ns,s);var lbl=(s.type==="inactive")?"Inactifs avant":"Crees depuis";document.getElementById(ns+"Info").textContent=lbl+" le "+s.cutoff+" ("+s.days+"j)";}function adClr(ns){adSt[ns]=null;var dt=getTable(ns);if(dt){dt.search("").columns().search("").draw();rebuildSB(ns,null);}document.getElementById(ns+"Info").textContent="";}document.addEventListener("keydown",function(e){if(e.key==="Enter"){if(e.target&&e.target.id==="uCustom")adCustomU();if(e.target&&e.target.id==="pcCustom")adCustomPC();}});function rebuildSB(ns,s){var dt=(ns==="u")?adDT_u:adDT_pc;if(!dt||!dt.searchBuilder||typeof dt.searchBuilder.rebuild!=="function")return;try{if(!s){dt.searchBuilder.rebuild({criteria:[],logic:"AND"});}else{var cond=(s.type==="inactive")?"<":">";dt.searchBuilder.rebuild({criteria:[{condition:cond,data:s.col,origData:s.col,type:"date",value:[s.cutoff]}],logic:"AND"});console.log("SB rebuilt:",s.col,cond,s.cutoff);}}catch(e){console.log("SB err:",e.message);}}</script>'
            }
        }
        New-HTMLSection -Name 'Active Directory Users' -HeaderBackGroundColor Teal -HeaderTextAlignment left  {
                New-HTMLPanel {
                    New-HTMLTableOption -DataStore JavaScript -DateTimeFormat 'yyyy-MM-dd' -ArrayJoin -ArrayJoinString ',' -BoolAsString
                    if ($ShowSensitiveObjects.IsPresent) {
                        New-HTMLTable -DataTable $UserTable -DefaultSortColumn Name -HideFooter -DataTableID "adUserTable" {
                            New-HTMLTableCondition -Name 'Enabled' -Value 'False' -BackgroundColor LightCoral -Color White -ComparisonType string
                            New-HTMLTableCondition -Name 'Privileged' -Value 'Yes' -BackgroundColor Orange -Color White -ComparisonType string
                            New-HTMLTableCondition -Name 'Password Never Expired' -Value 'True' -BackgroundColor LightYellow -ComparisonType string
                        }
                    } else {
                        New-HTMLTable -DataTable ($UserTable | Select-Object * -ExcludeProperty 'Privileged') -DefaultSortColumn Name -HideFooter {
                            New-HTMLTableCondition -Name 'Enabled' -Value 'False' -BackgroundColor LightCoral -Color White -ComparisonType string
                            New-HTMLTableCondition -Name 'Password Never Expired' -Value 'True' -BackgroundColor LightYellow -ComparisonType string
                        }
                    }
                }
            }                
            New-HTMLSection -HeaderText "Users Charts" -HeaderBackGroundColor DarkBlue -HeaderTextAlignment left  {
                New-HTMLPanel {
                    New-HTMLChart -Gradient -Title 'Enabled vs Disabled Users' -TitleAlignment center -Height 200 {
                        New-ChartTheme -Palette palette2
                        New-ChartPie -Name "Enabled" -Value $UserEnabled
                        New-ChartPie -Name "Disabled" -Value $UserDisabled                    
                    }
                }
                New-HTMLPanel {
                    New-HTMLChart -Gradient -Title 'Password Expiration' -TitleAlignment center -Height 200 {
                        New-ChartTheme -Palette palette1
                        New-ChartPie -Name "Password Never Expires" -Value $UserPasswordNeverExpires
                        New-ChartPie -Name "Password Expires" -Value $UserPasswordExpires 
                    }
                }
                New-HTMLPanel {
                    New-HTMLChart -Gradient -Title 'Users Protected from Deletion' -TitleAlignment center -Height 200 {
                        New-ChartTheme -Palette palette1
                        New-ChartPie -Name "Protected" -Value $ProtectedUsers
                        New-ChartPie -Name "Not Protected" -Value $NonProtectedUsers 
                    }
                }
            }
        }            

        #Page Computers  
        New-HTMLTab -Name 'Computers' -IconSolid desktop {
            New-HTMLSection -Name 'Computers Overivew' -Invisible  {
                New-HTMLPanel {
                    New-HTMLTable -HideFooter -HideButtons -DataTable $TOPComputersTable
                }
            }
            New-HTMLSection -Name 'Computers' -HeaderBackGroundColor teal -HeaderTextAlignment left {
                New-HTMLPanel -Invisible {
                    New-HTMLTableOption -DataStore JavaScript -DateTimeFormat 'yyyy-MM-dd' -ArrayJoin -ArrayJoinString ',' -BoolAsString
                                New-HTMLText -Text '<div style="margin:8px 0"><div style="display:flex;gap:6px;align-items:center;flex-wrap:wrap;margin-bottom:4px"><b>&#128187; Inactifs depuis :</b><button onclick="adFilterPC(30)" style="border-radius:4px;padding:4px 12px;cursor:pointer;font-size:12px;border:1px solid #ccc;background:#fff3cd">+30j</button><button onclick="adFilterPC(60)" style="border-radius:4px;padding:4px 12px;cursor:pointer;font-size:12px;border:1px solid #ccc;background:#ffd8a8">+60j</button><button onclick="adFilterPC(90)" style="border-radius:4px;padding:4px 12px;cursor:pointer;font-size:12px;border:1px solid #ccc;background:#f8d7da">+90j</button><button onclick="adFilterPC(180)" style="border-radius:4px;padding:4px 12px;cursor:pointer;font-size:12px;border:1px solid #ccc;background:#d9534f;color:white">+180j</button><button onclick="adFilterPC(365)" style="border-radius:4px;padding:4px 12px;cursor:pointer;font-size:12px;border:1px solid #ccc;background:#7b1818;color:white">+1 an</button><input id="pcCustom" type="number" min="1" max="9999" placeholder="jours" style="width:65px;padding:3px 6px;border-radius:4px;border:1px solid #aaa;font-size:12px;text-align:center"/><button onclick="adCustomPC()" style="border-radius:4px;padding:4px 12px;cursor:pointer;font-size:12px;border:1px solid #0077cc;background:#0077cc;color:white">Appliquer</button></div><div style="display:flex;gap:6px;align-items:center;flex-wrap:wrap"><b>&#128197; Crees depuis :</b><button onclick="adFilterPCC(7)" style="border-radius:4px;padding:4px 12px;cursor:pointer;font-size:12px;border:1px solid #ccc;background:#d4edda">7j</button><button onclick="adFilterPCC(30)" style="border-radius:4px;padding:4px 12px;cursor:pointer;font-size:12px;border:1px solid #ccc;background:#b8daff">30j</button><button onclick="adFilterPCC(90)" style="border-radius:4px;padding:4px 12px;cursor:pointer;font-size:12px;border:1px solid #ccc;background:#80bdff">90j</button><button onclick="adFilterPCC(365)" style="border-radius:4px;padding:4px 12px;cursor:pointer;font-size:12px;border:1px solid #004085;background:#004085;color:white">1 an</button><button onclick="adClrPC()" style="border-radius:4px;padding:4px 12px;cursor:pointer;font-size:12px;border:1px solid #999;background:#e9ecef">&#x2716; Effacer</button><span id="pcInfo" style="font-size:12px;color:#555;font-style:italic;margin-left:8px"></span></div></div>'
                    New-HTMLTable -DataTable $ComputersTable -DataTableID "adPcTable"  
                }
            }
            New-HTMLSection -HeaderText 'Computers Charts' -HeaderBackGroundColor DarkBlue -HeaderTextAlignment left  {
                New-HTMLPanel {
                    New-HTMLChart -Gradient -Title 'Computers Protected from Deletion' -TitleAlignment center -Height 200 {
                        New-ChartTheme -Palette palette10 -Mode light
                        New-ChartPie -Name 'Protected' -Value $ComputersProtected
                        New-ChartPie -Name 'Not Protected' -Value $ComputersNotProtected                              
                    }
                }

            New-HTMLPanel {
                    New-HTMLChart -Gradient -Title 'Computers Enabled Vs Disabled' -TitleAlignment center -Height 200 {
                        New-ChartTheme -Palette palette4 -Mode light
                        New-ChartPie -Name 'Enabled' -Value $ComputerEnabled
                        New-ChartPie -Name 'Disabled' -Value $ComputerDisabled                  
                    }
                }
            }
            #Section All OS
            New-HTMLSection -Invisible {
                New-HTMLSection -HeaderText 'Computers Operating System Distrubiton' -HeaderBackGroundColor teal -HeaderTextAlignment left  {
                    New-HTMLPanel {
                        New-HTMLChart -Gradient -Title 'Computers Operating Systems' -TitleAlignment center  { 
                            New-ChartTheme  -Mode light
                            $GraphComputerOS.GetEnumerator() | ForEach-Object {
                            New-ChartPie -Name $_.name -Value $_.count 
                            }                    
                        }
                    }
                }
            }
            # Section spécifique Poste Client
            New-HTMLSection -HeaderText 'Client Computers' -HeaderBackGroundColor DarkBlue -HeaderTextAlignment left {
                New-HTMLPanel {
                    New-HTMLChart -Gradient -Title 'Client OS Distribution' {
                        New-ChartTheme -Mode light
                        $ClientOSStats | ForEach-Object {
                            New-ChartPie -Name $_.Name -Value $_.Count
                        }
                    }
                }

                # --- Obsolescence Clients avec barres visuelles ---
                New-HTMLPanel {
    if ($ClientOSDetails -and $ClientOSDetails.Count -gt 0) {
        New-HTMLText -Text "Client OS - End of Support Status" -FontSize 16 -FontWeight bold -Alignment center
        
        $osColors = @{ 0 = '#3498db'; 1 = '#2ecc71'; 2 = '#f39c12'; 3 = '#e74c3c'; 4 = '#9b59b6'; 5 = '#1abc9c' }
        $statuses = @('Supported', $WarningStatusName, 'EOL', 'Unknown')
        $statusColors = @{ 'Supported' = '#d5f4e6'; $WarningStatusName = '#fff3cd'; 'EOL' = '#f8d7da'; 'Unknown' = '#e2e3e5' }
        
        foreach ($status in $statuses) {
            $total = ($ClientOSDetails | ForEach-Object { $_.$status } | Measure-Object -Sum).Sum
            
            New-HTMLPanel -BackgroundColor $statusColors[$status] -BorderRadius 5px -Margin 5 {
                New-HTMLText -Text "$status ($total machines)" -FontWeight bold -FontSize 14
                
                if ($total -gt 0) {
                    $barHtml = "<div style='display: flex; width: 100%; height: 30px; border: 1px solid #ccc; border-radius: 5px; overflow: hidden; margin-top: 10px;'>"
                    $osIndex = 0
                    foreach ($osItem in $ClientOSDetails) {
                        $value = $osItem.$status
                        if ($value -gt 0) {
                            $percentage = [math]::Round(($value / $total) * 100, 1)
                            $color = $osColors[$osIndex % $osColors.Count]
                            $barHtml += "<div style='width: $percentage%; background-color: $color; display: flex; align-items: center; justify-content: center; color: white; font-weight: bold; font-size: 12px;' title='$($osItem.OS): $value machines ($percentage%)'>$($osItem.OS): $value</div>"
                        }
                        $osIndex++
                    }
                    $barHtml += "</div>"
                    New-HTMLText -Text $barHtml
                    
                    $legendHtml = "<div style='margin-top: 5px; font-size: 12px;'>"
                    $osIndex = 0
                    foreach ($osItem in $ClientOSDetails) {
                        $value = $osItem.$status
                        if ($value -gt 0) {
                            $percentage = [math]::Round(($value / $total) * 100, 1)
                            $color = $osColors[$osIndex % $osColors.Count]
                            $legendHtml += "<span style='margin-right: 15px;'><span style='display: inline-block; width: 12px; height: 12px; background-color: $color; border-radius: 2px; margin-right: 5px;'></span>$($osItem.OS): $value ($percentage%)</span>"
                        }
                        $osIndex++
                    }
                    $legendHtml += "</div>"
                    New-HTMLText -Text $legendHtml
                } else {
                    New-HTMLText -Text "Aucune machine dans ce statut" -FontSize 12 -Color Gray -Alignment center
                }
            }
        }
    } else {
        New-HTMLText -Text "No client OS data available" -FontSize 14 -Color Gray
    }
                }
            }
            New-HTMLSection -HeaderText 'Client OS - Lifecycle Table' -HeaderBackGroundColor SteelBlue -HeaderTextAlignment left {
                New-HTMLPanel {
                    New-HTMLText -Text "Client OS - Lifecycle Table" -FontSize 16 -FontWeight bold -Alignment center
                    New-HTMLText -LineBreak
                    
                    if ($ClientOSDetails -and $ClientOSDetails.Count -gt 0) {
                        $lifecycleData = $ClientOSDetails | ForEach-Object { Build-LifecycleRow -osItem $_ -WarningStatusName $WarningStatusName }
                        
                        New-HTMLTable -DataTable ($lifecycleData | Sort-Object 'Total' -Descending) -PagingLength 20 {
                            New-TableCondition -Name 'PrimaryStatus' -ComparisonType string -Operator eq -Value 'EOL'                                   -BackgroundColor '#f8d7da' -Color '#721c24' -Row
                            New-TableCondition -Name 'PrimaryStatus' -ComparisonType string -Operator eq -Value $WarningStatusName                     -BackgroundColor '#fff3cd' -Color '#856404' -Row
                            New-TableCondition -Name 'PrimaryStatus' -ComparisonType string -Operator eq -Value 'Supported'                            -BackgroundColor '#d5f4e6' -Color '#155724' -Row
                            New-TableCondition -Name 'PrimaryStatus' -ComparisonType string -Operator eq -Value 'Supported (no end of life announced)' -BackgroundColor '#d5f4e6' -Color '#155724' -Row
                            New-TableCondition -Name 'PrimaryStatus' -ComparisonType string -Operator eq -Value 'Unknown'                              -BackgroundColor '#e2e3e5' -Color '#383d41' -Row
                            New-TableCondition -Name 'EoLDate' -ComparisonType string -Operator eq -Value 'Unknown'                                    -BackgroundColor '#f0f0f0'
                            New-TableCondition -Name 'EoLDate' -ComparisonType string -Operator eq -Value 'No date announced'                          -BackgroundColor '#d5f4e6' -Color '#155724'
                        } -Filtering -FilteringLocation Top -HideFooter
                    } else {
                        New-HTMLText -Text "No client OS data available" -FontSize 12 -Color Gray
                    }
                }
            }
            # Section spécifique Serveur
            New-HTMLSection -HeaderText 'Server Computers' -HeaderBackGroundColor DarkBlue -HeaderTextAlignment left {
                # --- Camembert OS Serveurs ---
                New-HTMLPanel {
                    New-HTMLChart -Gradient -Title 'Server OS Distribution' {
                        New-ChartTheme -Mode light
                        $ServerOSStats | ForEach-Object {
                            New-ChartPie -Name $_.Name -Value $_.Count
                        }
                    }
                }

                # --- Obsolescence Serveurs avec barres visuelles ---
                New-HTMLPanel {
    if ($ServerOSDetails -and $ServerOSDetails.Count -gt 0) {
        New-HTMLText -Text "Server OS - End of Support Status" -FontSize 16 -FontWeight bold -Alignment center
        
        $osColors = @{ 0 = '#3498db'; 1 = '#2ecc71'; 2 = '#f39c12'; 3 = '#e74c3c'; 4 = '#9b59b6'; 5 = '#1abc9c' }
        $statuses = @('Supported', $WarningStatusName, 'EOL', 'Unknown')
        $statusColors = @{ 'Supported' = '#d5f4e6'; $WarningStatusName = '#fff3cd'; 'EOL' = '#f8d7da'; 'Unknown' = '#e2e3e5' }
        
        foreach ($status in $statuses) {
            $total = ($ServerOSDetails | ForEach-Object { $_.$status } | Measure-Object -Sum).Sum
            
            New-HTMLPanel -BackgroundColor $statusColors[$status] -BorderRadius 5px -Margin 5 {
                New-HTMLText -Text "$status ($total machines)" -FontWeight bold -FontSize 14
                
                if ($total -gt 0) {
                    $barHtml = "<div style='display: flex; width: 100%; height: 30px; border: 1px solid #ccc; border-radius: 5px; overflow: hidden; margin-top: 10px;'>"
                    $osIndex = 0
                    foreach ($osItem in $ServerOSDetails) {
                        $value = $osItem.$status
                        if ($value -gt 0) {
                            $percentage = [math]::Round(($value / $total) * 100, 1)
                            $color = $osColors[$osIndex % $osColors.Count]
                            $barHtml += "<div style='width: $percentage%; background-color: $color; display: flex; align-items: center; justify-content: center; color: white; font-weight: bold; font-size: 12px;' title='$($osItem.OS): $value machines ($percentage%)'>$($osItem.OS): $value</div>"
                        }
                        $osIndex++
                    }
                    $barHtml += "</div>"
                    New-HTMLText -Text $barHtml
                    
                    $legendHtml = "<div style='margin-top: 5px; font-size: 12px;'>"
                    $osIndex = 0
                    foreach ($osItem in $ServerOSDetails) {
                        $value = $osItem.$status
                        if ($value -gt 0) {
                            $percentage = [math]::Round(($value / $total) * 100, 1)
                            $color = $osColors[$osIndex % $osColors.Count]
                            $legendHtml += "<span style='margin-right: 15px;'><span style='display: inline-block; width: 12px; height: 12px; background-color: $color; border-radius: 2px; margin-right: 5px;'></span>$($osItem.OS): $value ($percentage%)</span>"
                        }
                        $osIndex++
                    }
                    $legendHtml += "</div>"
                    New-HTMLText -Text $legendHtml
                } else {
                    New-HTMLText -Text "Aucune machine dans ce statut" -FontSize 12 -Color Gray -Alignment center
                }
            }
        }
    } else {
        New-HTMLText -Text "No server OS data available" -FontSize 14 -Color Gray
    }
                }
            }
            New-HTMLSection -HeaderText 'Server OS - Lifecycle Table' -HeaderBackGroundColor SteelBlue -HeaderTextAlignment left {
                New-HTMLPanel {
                    New-HTMLText -Text "Server OS - Lifecycle Table" -FontSize 16 -FontWeight bold -Alignment center
                    New-HTMLText -LineBreak
                    
                    if ($ServerOSDetails -and $ServerOSDetails.Count -gt 0) {
                        $lifecycleData = $ServerOSDetails | ForEach-Object { Build-LifecycleRow -osItem $_ -WarningStatusName $WarningStatusName }
                        
                        New-HTMLTable -DataTable ($lifecycleData | Sort-Object 'Total' -Descending) -PagingLength 20 {
                            New-TableCondition -Name 'PrimaryStatus' -ComparisonType string -Operator eq -Value 'EOL'                                   -BackgroundColor '#f8d7da' -Color '#721c24' -Row
                            New-TableCondition -Name 'PrimaryStatus' -ComparisonType string -Operator eq -Value $WarningStatusName                     -BackgroundColor '#fff3cd' -Color '#856404' -Row
                            New-TableCondition -Name 'PrimaryStatus' -ComparisonType string -Operator eq -Value 'Supported'                            -BackgroundColor '#d5f4e6' -Color '#155724' -Row
                            New-TableCondition -Name 'PrimaryStatus' -ComparisonType string -Operator eq -Value 'Supported (no end of life announced)' -BackgroundColor '#d5f4e6' -Color '#155724' -Row
                            New-TableCondition -Name 'PrimaryStatus' -ComparisonType string -Operator eq -Value 'Unknown'                              -BackgroundColor '#e2e3e5' -Color '#383d41' -Row
                            New-TableCondition -Name 'EoLDate' -ComparisonType string -Operator eq -Value 'Unknown'                                    -BackgroundColor '#f0f0f0'
                            New-TableCondition -Name 'EoLDate' -ComparisonType string -Operator eq -Value 'No date announced'                          -BackgroundColor '#d5f4e6' -Color '#155724'
                        } -Filtering -FilteringLocation Top -HideFooter
                    } else {
                        New-HTMLText -Text "No server OS data available" -FontSize 12 -Color Gray
                    }
                }
            }

        }      

        #Page Resume
        New-HTMLTab -Name 'Resume' {        
            New-HTMLSection -HeaderBackGroundColor teal -Name 'All Members' -HeaderTextAlignment left  {
                New-HTMLSection  -HeaderBackGroundColor Teal -Invisible  {
                    New-HTMLPanel -Margin 10 {      
                        New-HTMLPanel -BackgroundColor lightgreen -AlignContentText right {
                            New-HTMLText -Text $Allobjects[0].count -Alignment left -FontSize 40 -FontWeight bold 
                            New-HTMLText -Text $Allobjects[0].name -Alignment left -FontSize 20
                            New-HTMLTag -Tag 'i' -Attributes @{ class = "fas fa-users fa-3x" } 
                        }
                        New-HTMLText -LineBreak 
                        New-HTMLPanel -BackgroundColor bisque -AlignContentText right {
                            New-HTMLText -Text $Allobjects[1].count -Alignment left -FontSize 40 -FontWeight bold
                            New-HTMLText -Text $Allobjects[1].name -Alignment left -FontSize 20
                            New-HTMLTag -Tag 'i' -Attributes @{ class = "fas fa-user fa-3x" } 
                        }
                    }
                    New-HTMLPanel -Margin 10 {
                        New-HTMLPanel -BackgroundColor lightblue  -AlignContentText right  {
                            New-HTMLText -Text $Allobjects[2].count -Alignment left -FontSize 40 -FontWeight bold
                            New-HTMLText -Text $Allobjects[2].name -Alignment left -FontSize 20
                            New-HTMLTag -Tag 'i' -Attributes @{ class = "fas fa-laptop fa-3x" } 
                        }
                        New-HTMLText -LineBreak 
                        New-HTMLPanel -BackgroundColor lightpink  -AlignContentText right  {
                            New-HTMLText -Text $Allobjects[3].count -Alignment left -FontSize 40 -FontWeight bold
                            New-HTMLText -Text $Allobjects[3].name -Alignment left -FontSize 20
                            New-HTMLTag -Tag 'i' -Attributes @{ class = "fas fa-address-card fa-3x" } 
                        }
                    }    
                    New-HTMLPanel -Margin 10 {
                        New-HTMLPanel -BackgroundColor khaki  -AlignContentText right  {
                            New-HTMLText -Text $Allobjects[4].count -Alignment left -FontSize 40 -FontWeight bold
                            New-HTMLText -Text $Allobjects[4].name -Alignment left -FontSize 20
                            New-HTMLTag -Tag 'i' -Attributes @{ class = "fas fa-users-slash fa-3x" } 
                        }
                        New-HTMLText -LineBreak 
                    }   
                }      
                New-HTMLSection -HeaderText 'All Members' -Invisible {
                    New-HTMLPanel -Width "70%" {
                        New-HTMLChart -Gradient -Title 'Pourcent By AD Objects' -TitleAlignment center -Height 300  {
                            New-ChartTheme  -Mode light                    
                            $Allobjects.GetEnumerator() | ForEach-Object {
                                New-ChartPie -Name $_.name -Value $_.count
                            }                    
                        }
                    }
                }
            }   
            New-HTMLSection -Name 'About' -HeaderBackGroundColor teal -HeaderTextAlignment left {   
                New-HTMLPanel {
                    New-HTMLList {
                        New-HTMLListItem -Text "Generated date : $time"
                        New-HTMLListItem -Text 'Modern Active Directory Enhanced _ Version : 2.0.0 _ Release : 02/2026' 
                        New-HTMLListItem -Text 'Author : JCh Labs<br> 
                        <br> Inspired ModernAD Dakhama Mehdi <br>
                        <br> Inspired ADReportHTLM Bradley Wyatt [thelazyadministrator](https://www.thelazyadministrator.com/)<br>
                        <br> Credit : Thirrey Demon-Barcelo, Mattieu Souin, Mahmoud Hatira, Zouhair sarouti<br>
                        <br> Thanks : Boss Przemyslaw Klys - Module PSWriteHTML- [Evotec](https://evotec.xyz)'
                    } -FontSize 14
                }         
                New-HTMLTag -Tag 'img' -Attributes @{ 
                    src   = $RightLogo
                    style = "height:100%; width:100%; object-fit:contain;"
                } -SelfClosing
            }
        } 
    } 
}


#endregion generatehtml

