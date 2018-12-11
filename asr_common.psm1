class AsrCommon
{
    [psobject]$Logger

    AsrCommon($logger)
    {
        $this.Logger = $logger
    }

    [void] EnsureVaultContext($vaultName)
    {
        $this.Logger.LogTrace("Ensuring services vault context '$($vaultName)'")
        $targetVault = Get-AzureRmRecoveryServicesVault -Name $vaultName
        if ($targetVault -eq $null)
        {
            $this.Logger.LogError("Vault with name '$($vaultName)' unable to find")
        }
        Set-AzureRmRecoveryServicesAsrVaultContext -Vault $targetVault
    }

    [psobject] GetProtectionContainer($sourceConfigurationServer)
    {
        $this.Logger.LogTrace("Getting protection container reference for configuration server '$($sourceConfigurationServer)'")
        $fabricServer = Get-AzureRmRecoveryServicesAsrFabric -FriendlyName $sourceConfigurationServer
        $protectionContainer = Get-AzureRmRecoveryServicesAsrProtectionContainer -Fabric $fabricServer
        return $protectionContainer
    }

    [psobject] GetProtectableItem($protectionContainer, $sourceMachineName)
    {
        $this.Logger.LogTrace("Getting protectable item reference '$($sourceMachineName)'")
        $protectableVM = Get-AzureRmRecoveryServicesAsrProtectableItem `
            -ProtectionContainer $protectionContainer `
            -FriendlyName $sourceMachineName
        return $protectableVM
    }

    [psobject] GetProtectedItem($protectionContainer, $sourceMachineName)
    {
        $this.Logger.LogTrace("Getting protected item reference '$($sourceMachineName)'")
        $protectedItem = Get-AzureRmRecoveryServicesAsrReplicationProtectedItem `
            -ProtectionContainer $protectionContainer `
            -FriendlyName $sourceMachineName
        return $protectedItem
    }
}

Function New-AsrCommonInstance($Logger)
{
  return [AsrCommon]::new($Logger)
}

Export-ModuleMember -Function New-AsrCommonInstance