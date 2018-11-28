
#Connect-AzureRmAccount
[cmdletbinding(SupportsShouldProcess=$True)]
[parameter(Mandatory=$true)]
$CsvFilePath

$migrationDate = Get-Date
$logDate = $migrationDate.ToString("MM/dd/yyyy HH:mm:ss")

Function LogError([string] $Message)
{
    $logMessage = [string]::Concat($logDate, "[ERROR]-", $Message)
    Write-Output $logMessage
    Write-Error $logMessage
}

Function LogTrace([string] $Message)
{
    $logMessage = [string]::Concat($logDate, "[LOG]-", $Message)
    Write-Output $logMessage
    Write-Host $logMessage
}

LogTrace "[START]-Starting Asr Replication"

$resolvedCsvPath = Resolve-Path -LiteralPath $CsvFilePath
$csvObj = Import-Csv $resolvedCsvPath -Delimiter ','

$ErrorActionPreference = "Stop"

foreach ($csvItem in $csvObj)
{
    $subscriptionId = $csvItem.VAULT_SUBSCRIPTION_ID

    $currentContext = Get-AzureRmContext
    $currentSubscription = $currentContext.Subscription
    if ($currentSubscription.Id -ne $subscriptionId)
    {
        Set-AzureRmContext -Subscription $subscriptionId
        if ($currentSubscription.Id -ne $subscriptionId)
        {
            LogError "SubscriptionId '$($subscriptionId)' is not selected as current default subscription"
        }
    }

    $vaultName = $csvItem.VAULT_NAME
    $sourceAccountName = $csvItem.ACCOUNT_NAME
    $sourceProcessServer = $csvItem.PROCESS_SERVER
    $targetPostFailoverResourceGroup = $csvItem.TARGET_RESOURCE_GROUP
    $targetPostFailoverStorageAccountName = $csvItem.TARGET_STORAGE_ACCOUNT
    $targetPostFailoverVNET = $csvItem.TARGET_VNET
    $targetPostFailoverSubnet = $csvItem.TARGET_SUBNET
    $sourceMachineName = $csvItem.MACHINE_NAME
    $replicationPolicy = $csvItem.REPLICATION_POLICY
    $targetAvailabilitySet = $csvItem.AVAILABILITY_SET
    $targetPrivateIP = $csvItem.PRIVATE_IP
    $targetMachineSize = $csvItem.MACHINE_SIZE

    #Print replication settings
    LogTrace "[REPLICATIONJOB]-$($sourceMachineName)"
    LogTrace "SourceMachineName=$($sourceMachineName)"
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

    $targetVault = Get-AzureRmRecoveryServicesVault -Name $vaultName
    if ($targetVault -eq $null)
    {
        LogError "Vault with name '$($vaultName)' unable to find"
    }

    Set-AzureRmRecoveryServicesAsrVaultContext -Vault $targetVault

    $fabricServer = Get-AzureRmRecoveryServicesAsrFabric -FriendlyName $sourceProcessServer
    $protectionContainer = Get-AzureRmRecoveryServicesAsrProtectionContainer -Fabric $fabricServer
    #$replicationPolicyObj = Get-AzureRmRecoveryServicesAsrPolicy -Name $replicationPolicy

    #Assumption storage are already created
    $targetPostFailoverStorageAccount = Get-AzureRmStorageAccount `
        -Name $targetPostFailoverStorageAccountName `
        -ResourceGroupName $targetPostFailoverResourceGroup

    $targetResourceGroupObj = Get-AzureRmResourceGroup -Name $targetPostFailoverResourceGroup
    $targetVnetObj = Get-AzureRmVirtualNetwork `
        -Name $targetPostFailoverVNET `
        -ResourceGroupName $targetPostFailoverResourceGroup 
    $targetPolicyMap  =  Get-AzureRmRecoveryServicesAsrProtectionContainerMapping `
        -ProtectionContainer $protectionContainer | where PolicyFriendlyName -eq $replicationPolicy
    $protectableVM = Get-AzureRmRecoveryServicesAsrProtectableItem -ProtectionContainer $protectionContainer -FriendlyName $sourceMachineName
    $sourceProcessServerObj = $fabricServer.FabricSpecificDetails.ProcessServers | Where-Object { $_.FriendlyName -eq $sourceProcessServer }
    $sourceAccountObj = $fabricServer.FabricSpecificDetails.RunAsAccounts | Where-Object { $_.AccountName -eq $sourceAccountName }

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
        -RecoveryAzureSubnetName $targetPostFailoverSubnet 
}

LogTrace "[FINISH]-Finishing Asr Replication"
