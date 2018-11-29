

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

LogTrace("[START]-Starting Asr Replication")
LogTrace("File: $($CsvFilePath)")

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
        $currentContext = Get-AzureRmContext
        $currentSubscription = $currentContext.Subscription
        if ($currentSubscription.Id -ne $subscriptionId)
        {
            LogErrorAndThrow("SubscriptionId '$($subscriptionId)' is not selected as current default subscription")
        }
    }

    $vaultName = $csvItem.VAULT_NAME
    $sourceMachineName = $csvItem.SOURCE_MACHINE_NAME
    $targetAvailabilitySet = $csvItem.AVAILABILITY_SET
    $targetPrivateIP = $csvItem.PRIVATE_IP
    $targetMachineSize = $csvItem.MACHINE_SIZE
    $sourceProcessServer = $csvItem.PROCESS_SERVER
    $targetPostFailoverResourceGroup = $csvItem.TARGET_RESOURCE_GROUP

    #Print replication settings
    LogTrace("[REPLICATIONJOB]-$($sourceMachineName)")
    LogTrace("SubscriptionId=$($subscriptionId)")
    LogTrace("SourceMachineName=$($sourceMachineName)")
    LogTrace("SourceProcessServer=$($sourceProcessServer)")
    LogTrace("VaultName=$($vaultName)")
    LogTrace("TargetAvailabilitySet=$($targetAvailabilitySet)")
    LogTrace("TargetResourceGroup=$($targetPostFailoverResourceGroup)")
    LogTrace("TargetPrivateIP=$($targetPrivateIP)")
    LogTrace("TargetMachineSize=$($targetMachineSize)")

    $targetVault = Get-AzureRmRecoveryServicesVault -Name $vaultName
    if ($targetVault -eq $null)
    {
        LogError("Vault with name '$($vaultName)' unable to find")
    }

    Set-AzureRmRecoveryServicesAsrVaultContext -Vault $targetVault

    $fabricServer = Get-AzureRmRecoveryServicesAsrFabric -FriendlyName $sourceProcessServer
    $protectionContainer = Get-AzureRmRecoveryServicesAsrProtectionContainer -Fabric $fabricServer
    
    $protectedItem = Get-AzureRmRecoveryServicesAsrReplicationProtectedItem `
        -ProtectionContainer $protectionContainer `
        -FriendlyName $sourceMachineName
    $nicDetails = $protectedItem.NicDetailsList[0]
    
    $targetAvailabilitySetObj = Get-AzureRmAvailabilitySet `
        -ResourceGroupName $targetPostFailoverResourceGroup `
        -Name $targetAvailabilitySet

    LogTrace "Creating job to set machine properties..."
    $updatePropertiesJob = Set-AzureRmRecoveryServicesAsrReplicationProtectedItem `
        -InputObject $protectedItem `
        -PrimaryNic $nicDetails.NicId `
        -RecoveryNicStaticIPAddress $targetPrivateIP `
        -RecoveryNetworkId $nicdetails.RecoveryVMNetworkId `
        -RecoveryNicSubnetName $nicdetails.RecoveryVMSubnetName `
        -UseManagedDisk $False `
        -RecoveryAvailabilitySet $targetAvailabilitySetObj.Id `
        -Size $targetMachineSize
    if ($updatePropertiesJob -eq $null)
    {
        LogErrorAndThrow("Error creating update properties job for '$($sourceMachineName)'")
    }
    LogTrace "Update machine properties job created"
}

LogTrace("[FINISH]-Finishing Asr Replication")

