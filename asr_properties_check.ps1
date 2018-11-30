

#Connect-AzureRmAccount
Param(
    [parameter(Mandatory=$true)]
    $CsvFilePath
)

Function LogError([string] $Message)
{
    $logDate = (Get-Date).ToString("MM/dd/yyyy HH:mm:ss")
    $logMessage = [string]::Concat($logDate, "[ERROR]-", $Message)
    Write-Output $logMessage
    Write-Host $logMessage
}

Function LogErrorAndThrow([string] $Message)
{
    $logDate = (Get-Date).ToString("MM/dd/yyyy HH:mm:ss")
    $logMessage = [string]::Concat($logDate, "[ERROR]-", $Message)
    Write-Output $logMessage
    Write-Error $logMessage
}

Function LogTrace([string] $Message)
{
    $logDate = (Get-Date).ToString("MM/dd/yyyy HH:mm:ss")
    $logMessage = [string]::Concat($logDate, "[LOG]-", $Message)
    Write-Output $logMessage
    Write-Host $logMessage
}

LogTrace("[START]-Checking properties")
LogTrace("File: $($CsvFilePath)")

$resolvedCsvPath = Resolve-Path -LiteralPath $CsvFilePath
$csvObj = Import-Csv $resolvedCsvPath -Delimiter ','

$CsvOutput = [string]::Concat($resolvedCsvPath.Path, ".propertiescheck.", (Get-Date).ToString("ddMMyyyy_HHmmss"), ".output.csv")

$ErrorActionPreference = "Stop"

$protectedItemStatusArray = New-Object System.Collections.Generic.List[System.Object]
# $statusItemInfo = New-Object PSObject
# $statusItemInfo | Add-Member -type NoteProperty -Name 'Machine' -Value $sourceMachineName
# $protectedItemStatusArray +=$statusItemInfo

class CheckInformation
{
    [string]$Machine
    [string]$Exception
    [string]$VaultNameCheck
    [string]$SourceProcessServerCheck
    [string]$SourceMachineNameCheck
    [string]$TargetPostFailoverResourceGroupCheck
    [string]$TargetPostFailoverStorageAccountNameCheck
    [string]$TargetPostFailoverVNETCheck
    [string]$TargetPostFailoverSubnetCheck
    [string]$ReplicationPolicyCheck
    [string]$TargetAvailabilitySetCheck
    [string]$TargetPrivateIPCheck
    [string]$TargetMachineSizeCheck
    [string]$TargetMachineNameCheck
}

Function CheckParameter([string]$ParameterName, [string]$ExpectedValue, [string]$ActualValue)
{
    LogError "Parameter check '$($ParameterName)'. ExpectedValue: '$($ExpectedValue)', ActualValue: '$($ActualValue)'"
    if ($ExpectedValue -ne $ActualValue)
    {
        throw "Expected value '$($ExpectedValue)' does not match actual value '$($ActualValue)' for parameter $($ParameterName)"
    } else {
        LogTrace "Parameter check '$($ParameterName)' DONE"
    }
}

Function GetProtectedItemStatus($csvItem)
{
    $subscriptionId = $csvItem.VAULT_SUBSCRIPTION_ID

    $currentContext = Get-AzureRmContext
    $currentSubscription = $currentContext.Subscription
    if ($currentSubscription.Id -ne $subscriptionId)
    {
        Set-AzureRmContext -Subscription $subscriptionId
        $currentContext = Get-AzureRmContext
        $currentSubscription = $currentContext.Subscription
        if ($currentSubscription.Id -ne $subscriptionId)
        {
            LogErrorAndThrow("SubscriptionId '$($subscriptionId)' is not selected as current default subscription")
        }
    }

    $vaultName = $csvItem.VAULT_NAME
    $sourceAccountName = $csvItem.ACCOUNT_NAME
    $sourceProcessServer = $csvItem.PROCESS_SERVER
    $targetPostFailoverResourceGroup = $csvItem.TARGET_RESOURCE_GROUP
    $targetPostFailoverStorageAccountName = $csvItem.TARGET_STORAGE_ACCOUNT
    $targetPostFailoverVNET = $csvItem.TARGET_VNET
    $targetPostFailoverSubnet = $csvItem.TARGET_SUBNET
    $sourceMachineName = $csvItem.SOURCE_MACHINE_NAME
    $replicationPolicy = $csvItem.REPLICATION_POLICY
    $targetAvailabilitySet = $csvItem.AVAILABILITY_SET
    $targetPrivateIP = $csvItem.PRIVATE_IP
    $targetMachineSize = $csvItem.MACHINE_SIZE
    $targetMachineName = $csvItem.TARGET_MACHINE_NAME
    $targetStorageAccountRG = $csvItem.TARGET_STORAGE_ACCOUNT_RG
    $targetVNETRG = $csvItem.TARGET_VNET_RG

    #Print replication settings
    LogTrace "[REPLICATIONJOB SETTINGS]-$($sourceMachineName)"
    LogTrace "SourceMachineName=$($sourceMachineName)"
    LogTrace "TargetMachineName=$($targetMachineName)"
    LogTrace "VaultName=$($vaultName)"
    LogTrace "AccountName=$($sourceAccountName)"
    LogTrace "TargetPostFailoverResourceGroup=$($targetPostFailoverResourceGroup)"
    LogTrace "TargetPostFailoverStorageAccountName=$($targetPostFailoverStorageAccountName)"
    LogTrace "TargetPostFailoverVNET=$($targetPostFailoverVNET)"
    LogTrace "TargetPostFailoverSubnet=$($targetPostFailoverSubnet)"
    LogTrace "TargetPostFailoverSubnet=$($targetPostFailoverSubnet)"
    LogTrace "ReplicationPolicy=$($replicationPolicy)"
    LogTrace "TargetAvailabilitySet=$($targetAvailabilitySet)"
    LogTrace "TargetPrivateIP=$($targetPrivateIP)"
    LogTrace "TargetMachineSize=$($targetMachineSize)"

    $statusItemInfo = [CheckInformation]::new()
    $statusItemInfo.Machine = $sourceMachineName

    $targetVault = Get-AzureRmRecoveryServicesVault -Name $vaultName
    if ($targetVault -eq $null)
    {
        LogError("Vault with name '$($vaultName)' unable to find")
    }
    $statusItemInfo.VaultNameCheck = "DONE"

    Set-AzureRmRecoveryServicesAsrVaultContext -Vault $targetVault

    $fabricServer = Get-AzureRmRecoveryServicesAsrFabric -FriendlyName $sourceProcessServer
    $protectionContainer = Get-AzureRmRecoveryServicesAsrProtectionContainer -Fabric $fabricServer
    $statusItemInfo.SourceProcessServerCheck = "DONE"
    
    $protectableVM = Get-AzureRmRecoveryServicesAsrProtectableItem `
        -ProtectionContainer $protectionContainer `
        -FriendlyName $sourceMachineName
    $statusItemInfo.SourceMachineNameCheck = "DONE"

    if ($protectableVM.ReplicationProtectedItemId -ne $null)
    {
        $protectedItem = Get-AzureRmRecoveryServicesAsrReplicationProtectedItem `
            -ProtectionContainer $protectionContainer `
            -FriendlyName $sourceMachineName

        
        $apiVersion = "2018-01-10"
        $resourceRawData = Get-AzureRmResource -ResourceId $protectedItem.ID -ApiVersion $apiVersion
        
        #RESOURCE_GROUP
        try {
            #$resourceRawData.Properties.providerSpecificDetails.recoveryAzureResourceGroupId
            $sourceResourceGroup = Get-AzureRmResourceGroup -Name $targetPostFailoverResourceGroup
            CheckParameter 'TARGET_RESOURCE_GROUP' $sourceResourceGroup.ResourceId $resourceRawData.Properties.providerSpecificDetails.recoveryAzureResourceGroupId
            $statusItemInfo.TargetPostFailoverResourceGroupCheck = "DONE"
        }
        catch {
            $statusItemInfo.TargetPostFailoverResourceGroupCheck = "ERROR"
            $exceptionMessage = $_ | Out-String
            LogError $exceptionMessage
        }

        #$resourceRawData.Properties.providerSpecificDetails.RecoveryAzureStorageAccount
        try {
            $RecoveryAzureStorageAccountRef = Get-AzureRmResource -ResourceId $resourceRawData.Properties.providerSpecificDetails.RecoveryAzureStorageAccount
            CheckParameter 'TARGET_STORAGE_ACCOUNT' $targetPostFailoverStorageAccountName $RecoveryAzureStorageAccountRef.ResourceName
            $statusItemInfo.TargetPostFailoverStorageAccountNameCheck = "DONE"
        }
        catch {
            $statusItemInfo.TargetPostFailoverStorageAccountNameCheck = "ERROR"
            $exceptionMessage = $_ | Out-String
            LogError $exceptionMessage
        }

        # #$resourceRawData.Properties.PolicyFriendlyName
        # $statusItemInfo.replicationPolicy = "DONE"
        try {
            CheckParameter 'REPLICATION_POLICY' $replicationPolicy $resourceRawData.Properties.PolicyFriendlyName
            $statusItemInfo.ReplicationPolicyCheck = "DONE"
        }
        catch {
            $statusItemInfo.ReplicationPolicyCheck = "ERROR"
            $exceptionMessage = $_ | Out-String
            LogError $exceptionMessage
        }

        # #$resourceRawData.Properties.providerSpecificDetails.recoveryAvailabilitySetId
        # $statusItemInfo.targetAvailabilitySet = "DONE"
        try {
            $actualAvailabilitySet = $resourceRawData.Properties.providerSpecificDetails.recoveryAvailabilitySetId
            if ($targetAvailabilitySet -eq '' -and $actualAvailabilitySet -eq '')
            {
                $statusItemInfo.TargetAvailabilitySetCheck = "DONE"
            } else {
                $targetAvailabilitySetObj = Get-AzureRmAvailabilitySet `
                    -ResourceGroupName $targetPostFailoverResourceGroup `
                    -Name $targetAvailabilitySet
                CheckParameter 'AVAILABILITY_SET' $targetAvailabilitySetObj.Id $actualAvailabilitySet
                $statusItemInfo.TargetAvailabilitySetCheck = "DONE"
            }
        }
        catch {
            $statusItemInfo.TargetAvailabilitySetCheck = "ERROR"
            $exceptionMessage = $_ | Out-String
            LogError $exceptionMessage
        }
      
        # #$resourceRawData.Properties.providerSpecificDetails.recoveryAzureVMSize
        # $statusItemInfo.targetMachineSize = "DONE"
        try {
            CheckParameter 'MACHINE_SIZE' $targetMachineSize $resourceRawData.Properties.providerSpecificDetails.recoveryAzureVMSize
            $statusItemInfo.TargetMachineSizeCheck = "DONE"
        }
        catch {
            $statusItemInfo.TargetMachineSizeCheck = "ERROR"
            $exceptionMessage = $_ | Out-String
            LogError $exceptionMessage
        }

        # #$resourceRawData.Properties.providerSpecificDetails.recoveryAzureVMName
        try {
            CheckParameter 'TARGET_MACHINE_NAME' $targetMachineName $resourceRawData.Properties.providerSpecificDetails.recoveryAzureVMName
            $statusItemInfo.TargetMachineNameCheck = "DONE"
        }
        catch {
            $statusItemInfo.TargetMachineNameCheck = "ERROR"
            $exceptionMessage = $_ | Out-String
            LogError $exceptionMessage
        }

        # #nic
        # #$resourceRawData.Properties.providerSpecificDetails.vmNics[0].replicaNicStaticIPAddress
        # $statusItemInfo.targetPrivateIP = "DONE"
        try {
            CheckParameter 'PRIVATE_IP' $targetPrivateIP $resourceRawData.Properties.providerSpecificDetails.vmNics[0].replicaNicStaticIPAddress
            $statusItemInfo.TargetPrivateIPCheck = "DONE"
        }
        catch {
            $statusItemInfo.TargetPrivateIPCheck = "ERROR"
            $exceptionMessage = $_ | Out-String
            LogError $exceptionMessage
        }

        # #$resourceRawData.Properties.providerSpecificDetails.vmNics[0].recoveryVMNetworkId
        # $statusItemInfo.targetPostFailoverVNET = "DONE"
        try {
            $VNETRef = Get-AzureRmResource -ResourceId $resourceRawData.Properties.providerSpecificDetails.vmNics[0].recoveryVMNetworkId
            CheckParameter 'TARGET_VNET' $VNETRef.ResourceId $resourceRawData.Properties.providerSpecificDetails.vmNics[0].recoveryVMNetworkId
            $statusItemInfo.TargetPostFailoverVNETCheck = "DONE"
        }
        catch {
            $statusItemInfo.TargetPostFailoverVNETCheck = "ERROR"
            $exceptionMessage = $_ | Out-String
            LogError $exceptionMessage
        }

        # #$resourceRawData.Properties.providerSpecificDetails.vmNics[0].recoveryVMSubnetName
        # $statusItemInfo.targetPostFailoverSubnet = "DONE"
        try {
            CheckParameter 'TARGET_SUBNET' $targetPostFailoverSubnet $resourceRawData.Properties.providerSpecificDetails.vmNics[0].recoveryVMSubnetName
            $statusItemInfo.TargetPostFailoverSubnetCheck = "DONE"
        }
        catch {
            $statusItemInfo.TargetPostFailoverSubnetCheck = "ERROR"
            $exceptionMessage = $_ | Out-String
            LogError $exceptionMessage
        }


    }

    $protectedItemStatusArray.Add($statusItemInfo)
}


foreach ($csvItem in $csvObj)
{
    try {
        GetProtectedItemStatus -csvItem $csvItem
    } catch {
        LogError "Exception creating update properties job"
        $exceptionMessage = $_ | Out-String

        $statusItemInfo = [CheckInformation]::new()
        $statusItemInfo.Machine = $csvItem.SOURCE_MACHINE_NAME
        $statusItemInfo.Exception = "ERROR RECOVERING INFO" 
        $protectedItemStatusArray.Add($statusItemInfo)

        LogError $exceptionMessage
    }
}

$protectedItemStatusArray.ToArray() | Export-Csv -LiteralPath $CsvOutput -Delimiter ',' -NoTypeInformation

LogTrace("[FINISH]-Finishing properties check")

