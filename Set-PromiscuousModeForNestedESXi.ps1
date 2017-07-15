[CmdletBinding()]
Param(
    [ValidateScript(             {                 If ( $_ -eq $null -or $_.Length -eq 0 ) { $false } Else { $true }             }         )     ]     $ViServers
    ,
    [string]$ViServerUsername = "root"
    ,
    [string]$ViServerPassword = "Password"
)
# http://www.virtuallyghetto.com/2014/08/new-vmware-fling-to-improve-networkcpu-performance-when-using-promiscuous-mode-for-nested-esxi.html
# http://www.tomsitpro.com/articles/building-powershell-parameter-validation,1-3555.html # https://communities.vmware.com/thread/537366
# https://communities.vmware.com/message/2604368#2604368

If ( $ViServers -isnot [array] ) {
    Write-Host "Convert `$ViServers to array."
    $ViServers = [string[]]$ViServers
} Else {
    Write-Host "Do not convert `$ViServers to array."
}

If ( $global:DefaultVIServers ){
    Disconnect-VIServer -Server $global:DefaultVIServers -Force -Confirm:$false
} Else {
}

Write-Host "`$ViServers: $($ViServers)" -BackgroundColor Yellow -ForegroundColor Black

$UserPowerCliCredentialStore = "$env:UserProfile\PowerCLI\Credentials"
If ( Test-Path -PathType Container -Path $UserPowerCliCredentialStore ) {
} Else {
  Write-Host "Creating folder path '$UserPowerCliCredentialStore'."
  New-Item -Path $UserPowerCliCredentialStore -Force -ItemType Container
}

foreach( $ViServer in $ViServers ){
    Write-Host ""
    Write-Host " `$ViServer = $ViServer" -BackgroundColor Cyan -ForegroundColor Black

    $CredentialFile = $UserPowerCliCredentialStore + '\' + $ViServer +"--" + $ViServerUsername + ".xml"
    New-VICredentialStoreItem -Host $ViServer -User $ViServerUsername -Password $ViServerPassword -File $CredentialFile -OutVariable $OutputResult -InformationVariable $InformationResult -WarningVariable $WarningResult -ErrorVariable $ErrorResult | Out-Null
    $UserPowerCliCredential = Get-VICredentialStoreItem -User $ViServerUsername -Host $ViServer -File $CredentialFile
    Write-Host "Connect-VIServer -Server $($UserPowerCliCredential.Host)"
    $ConnectViServerResult = Connect-VIServer -Server $ViServer                    -User $UserPowerCliCredential.User -Password $UserPowerCliCredential.Password -ErrorAction SilentlyContinue -ErrorVariable ConnectViServerError
    If ($ConnectViServerError ){
        Write-Host "Unable to connect to $ViServer.'n'nError:'nConnectViServerError'n'nSkipping."
    } Else {
        Write-Host "`$ConnectViServerResult = $ConnectViServerResult"
        Write-Verbose "`$global:DefaultVIServer = $global:DefaultVIServer"
        Write-Verbose "`$VmHost = Get-VMHost -Server $ViServer"
        $VmHost = Get-VMHost -Server $ViServer -ErrorAction SilentlyContinue -ErrorVariable GetHostError
        If ( $GetHostError ){
            Write-Host " Unable to connect to VmHost $VmHost`n`nError:`n$GetHostError'n'nSkipping."
        } Else {
            Write-Host " `$VmHost = $($VmHost.Name)" -ForegroundColor Green

            $AllNestedEsxi = $VmHost| Get-VM | Where-Object { $_.GuestId -ilike "*vmkernel*" } | Sort-Object -Property Name
            Write-Verbose "`$AllNestedEsxi:"
            $AllNestedEsxi.Name | ForEach-Object { Write-Verbose $_ }

            foreach( $NestedEsxi in $AllNestedEsxi ){
                Write-Host ""
                Write-Host "`$NestedEsxi.Name = $($NestedEsxi.Name)" -ForegroundColor Cyan

                $AllEthernetSettings = $NestedEsxi | Get-AdvancedSetting -Name "*ethernet*" | Sort-Object -Property Name
                If ( $AllEthernetSettings ){
                    Write-Verbose "`$AllEthernetSettings:"
                    $AllEthernetSettings | ForEach-Object { Write-Verbose $_ }
                    Write-Verbose "-----"
                } Else {
                    Write-Verbose "`$AllEthernetSettings is null."
                }

                $AllNetworkAdapters  = $NestedEsxi | Get-NetworkAdapter | Sort-Object -Property Name
                If ( $AllNetworkAdapters ){
                    Write-Verbose "`$AllNetworkAdapters:"
                    $AllNetworkAdapters | foreach{
                        Write-Verbose $_
                        If ( $_.ExtensionData.SlotInfo.PciSlotNumber ) {
                            Write-Verbose "`$_.ExtensionData.SlotInfo.PciSlotNumber = $($_.ExtensionData.SlotInfo.PciSlotNumber)"
                        } Else {
                            Write-Verbose "`$_.ExtensionData.SlotInfo.PciSlotNumber is null."
                        }
                    } 
                    Write-Verbose "-----"
                } Else {
                    Write-Verbose "`$AllNetworkAdapters is null"
                }

                foreach( $NetworkAdapter in $AllNetworkAdapters ){
                    $PciSlotNumber = $NetworkAdapter.ExtensionData.SlotInfo.PciSlotNumber
                    If ($PciSlotNumber){
                        Write-Host "`$PciSlotNumber = $PciSlotNumber"
                        If ( $AllEthernetSettings ) {
                            $EthernetNumber = ( $AllEthernetSettings | Where-Object { $_.Name -ilike "*pciSlotNumber*" -and $_.Value -eq $PciSlotNumber } ).Name.Split(".")[0].Substring( "ethernet".Length )
                            $EthernetInstanceSettings = $AllEthernetSettings | Where-Object { $_.Name -ilike ( "ethernet" + $EthernetNumber + "*" ) }
                            Write-Host "`$EthernetInstanceSettings:"
                            #      $EthernetInstanceSettings | Format-Table -AutoSize
                        } Else {
                            Write-Host "`$AllEthernetSettings is null."
                        }
                    } Else {
                        Write-Host "`$PciSlotNumber is null" -ForegroundColor Red
                    }

                    $AdvancedSettingPartialName = "filter4.name"
                    $AdvancedSettingFullName = "ethernet" + $EthernetNumber + "." + $AdvancedSettingPartialName
                    $AdvancedSettingDesiredValue = "dvfilter-maclearn"
                    $EthernetSetting = $EthernetInstanceSettings | Where-Object { $_.Name -ilike ( "*" + $AdvancedSettingPartialName ) }
                    If ( $EthernetSetting ){
                        If ( $EthernetSetting.Value -ilike $AdvancedSettingDesiredValue ){
                            Write-Host "`$NetworkAdapter = $NetworkAdapter setting '$AdvancedSettingPartialName' is set to value '$AdvancedSettingDesiredValue'." -ForegroundColor Green
                        } Else {
                            Write-Host "`$NetworkAdapter = $NetworkAdapter setting '$AdvancedSettingPartialName' not set to value '$AdvancedSettingDesiredValue'." -ForegroundColor Red
                            #Write-Host "Set-AdvancedSetting"
                        }
                    } Else {
                        Write-Host "`$NetworkAdapter = $NetworkAdapter setting '$AdvancedSettingPartialName' not defined." -ForegroundColor Red
                        Write-Host "New-AdvancedSetting -Entity $NestedEsxi -Name $AdvancedSettingFullName -Value $AdvancedSettingDesiredValue -Type VM"
                        New-AdvancedSetting -Entity $NestedEsxi -Name $AdvancedSettingFullName -Value $AdvancedSettingDesiredValue -Type VM -Force -Confirm:$false
                    }

                    $AdvancedSettingPartialName = "filter4.onFailure"
                    $AdvancedSettingFullName = "ethernet" + $EthernetNumber + "." + $AdvancedSettingPartialName
                    $AdvancedSettingDesiredValue = "failOpen"
                    $EthernetSetting = $EthernetInstanceSettings | Where-Object { $_.Name -ilike ( "*" + $AdvancedSettingPartialName ) }
                    If ( $EthernetSetting ){
                        If ( $EthernetSetting.Value -ilike $AdvancedSettingDesiredValue ){
                            Write-Host "`$NetworkAdapter = $NetworkAdapter setting '$AdvancedSettingPartialName' is set to value '$AdvancedSettingDesiredValue'." -ForegroundColor Green
                        } Else {
                            Write-Host "`$NetworkAdapter = $NetworkAdapter setting '$AdvancedSettingPartialName' not set to value '$AdvancedSettingDesiredValue'." -ForegroundColor Red
                            #Write-Host "Set-AdvancedSetting"
                        }
                    } Else {
                        Write-Host "`$NetworkAdapter = $NetworkAdapter setting '$AdvancedSettingPartialName' not defined." -ForegroundColor Red
                        Write-Host "New-AdvancedSetting -Entity $NestedEsxi -Name $AdvancedSettingFullName -Value $AdvancedSettingDesiredValue -Type VM"
                        New-AdvancedSetting -Entity $NestedEsxi -Name $AdvancedSettingFullName -Value $AdvancedSettingDesiredValue -Type VM -Force -Confirm:$false
                    }
                }
            }
            Disconnect-VIServer -Server $ViServer -Force -Confirm:$false
        }
        Write-Host ""
    }
}
