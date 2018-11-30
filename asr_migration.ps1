
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

LogTrace "[START]-Starting Asr Replication"
LogTrace "File: $CsvFilePath"

$resolvedCsvPath = Resolve-Path -LiteralPath $CsvFilePath
$csvObj = Import-Csv $resolvedCsvPath -Delimiter ','

$CsvOutput = [string]::Concat($resolvedCsvPath.Path, ".migration.", (Get-Date).ToString("ddMMyyyy_HHmmss"), ".output.csv")

$ErrorActionPreference = "Stop"

class ReplicationInformation
{
    [string]$Machine
    [string]$ProtectableStatus
    [string]$ProtectionState
    [string]$ProtectionStateDescription
    [string]$Exception
    [string]$ReplicationJobId
}

$protectedItemStatusArray = New-Object System.Collections.Generic.List[System.Object]

Function StartReplicationJobItem($csvItem)
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
            LogErrorAndThrow "SubscriptionId '$($subscriptionId)' is not selected as current default subscription"
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

    $statusItemInfo = [ReplicationInformation]::new()
    $statusItemInfo.Machine = $sourceMachineName

    $targetVault = Get-AzureRmRecoveryServicesVault -Name $vaultName
    if ($targetVault -eq $null)
    {
        LogErrorAndThrow "Unable to find Vault with name '$($vaultName)'"
    }

    Set-AzureRmRecoveryServicesAsrVaultContext -Vault $targetVault

    $fabricServer = Get-AzureRmRecoveryServicesAsrFabric -FriendlyName $sourceProcessServer
    $protectionContainer = Get-AzureRmRecoveryServicesAsrProtectionContainer -Fabric $fabricServer
    #$replicationPolicyObj = Get-AzureRmRecoveryServicesAsrPolicy -Name $replicationPolicy

    #Assumption storage are already created
    $targetPostFailoverStorageAccount = Get-AzureRmStorageAccount `
        -Name $targetPostFailoverStorageAccountName `
        -ResourceGroupName $targetStorageAccountRG

    $targetResourceGroupObj = Get-AzureRmResourceGroup -Name $targetPostFailoverResourceGroup
    $targetVnetObj = Get-AzureRmVirtualNetwork `
        -Name $targetPostFailoverVNET `
        -ResourceGroupName $targetVNETRG 
    $targetPolicyMap  =  Get-AzureRmRecoveryServicesAsrProtectionContainerMapping `
        -ProtectionContainer $protectionContainer | Where-Object { $_.PolicyFriendlyName -eq $replicationPolicy }
    if ($targetPolicyMap -eq $null)
    {
        LogErrorAndThrow "Policy map '$($replicationPolicy)' was not found"
    }
    $protectableVM = Get-AzureRmRecoveryServicesAsrProtectableItem -ProtectionContainer $protectionContainer -FriendlyName $sourceMachineName
    $statusItemInfo.ProtectableStatus = $protectableVM.ProtectionStatus

    if ($protectableVM.ReplicationProtectedItemId -eq $null)
    {
        $sourceProcessServerObj = $fabricServer.FabricSpecificDetails.ProcessServers | Where-Object { $_.FriendlyName -eq $sourceProcessServer }
        if ($sourceProcessServerObj -eq $null)
        {
            LogErrorAndThrow "Process server with name '$($sourceProcessServer)' was not found"
        }
        $sourceAccountObj = $fabricServer.FabricSpecificDetails.RunAsAccounts | Where-Object { $_.AccountName -eq $sourceAccountName }
        if ($sourceAccountObj -eq $null)
        {
            LogErrorAndThrow "Account name '$($sourceAccountName)' was not found"
        }

        LogTrace "Starting replication Job for source '$($sourceMachineName)'"
        $replicationJob = New-AzureRmRecoveryServicesAsrReplicationProtectedItem `
            -VMwareToAzure `
            -ProtectableItem $protectableVM `
            -Name (New-Guid).Guid `
            -ProtectionContainerMapping $targetPolicyMap `
            -RecoveryAzureStorageAccountId $targetPostFailoverStorageAccount.Id `
            -ProcessServer $sourceProcessServerObj `
            -Account $sourceAccountObj `
            -RecoveryResourceGroupId $targetResourceGroupObj.ResourceId `
            -RecoveryAzureNetworkId $targetVnetObj.Id `
            -RecoveryAzureSubnetName $targetPostFailoverSubnet `
            -RecoveryVmName $targetMachineName

        $replicationJobObj = Get-AzureRmRecoveryServicesAsrJob -Name $replicationJob.Name
        $statusItemInfo.ReplicationJobId = replicationJobObj.Name
        while ($replicationJobObj.State -eq 'NotStarted') {
            Write-Host "." -NoNewline 
            $replicationJobObj = Get-AzureRmRecoveryServicesAsrJob -Name $replicationJob.Name
        }

        if ($replicationJobObj.State -eq 'Failed')
        {
            LogError "Error starting replication job"
            foreach ($replicationJobError in $replicationJobObj.Errors)
            {
                LogError $replicationJobError.ServiceErrorDetails.Message
                LogError $replicationJobError.ServiceErrorDetails.PossibleCauses
            }
        } else {
            LogTrace "ReplicationJob initiated"        
        }
    } else {
        $protectedItem = Get-AzureRmRecoveryServicesAsrReplicationProtectedItem `
            -ProtectionContainer $protectionContainer `
            -FriendlyName $sourceMachineName
        $statusItemInfo.ProtectionState = $protectedItem.ProtectionState
        $statusItemInfo.ProtectionStateDescription = $protectedItem.ProtectionStateDescription
    }
    $protectedItemStatusArray.Add($statusItemInfo)
}

foreach ($csvItem in $csvObj)
{
    try {
        StartReplicationJobItem -csvItem $csvItem
    } catch {
        LogError "Exception creating replication job"
        $exceptionMessage = $_ | Out-String

        $statusItemInfo = [ReplicationInformation]::new()
        $statusItemInfo.Machine = $csvItem.SOURCE_MACHINE_NAME
        $statusItemInfo.Exception = "ERROR PROCESSING ITEM" 
        $protectedItemStatusArray.Add($statusItemInfo)

        LogError $exceptionMessage
    }
}

$protectedItemStatusArray.ToArray() | Export-Csv -LiteralPath $CsvOutput -Delimiter ',' -NoTypeInformation

LogTrace "[FINISH]-Finishing Asr Replication"
