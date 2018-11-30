

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

LogTrace("[START]-Starting Update properties")
LogTrace("File: $($CsvFilePath)")

$resolvedCsvPath = Resolve-Path -LiteralPath $CsvFilePath
$csvObj = Import-Csv $resolvedCsvPath -Delimiter ','

$CsvOutput = [string]::Concat($resolvedCsvPath.Path, ".updateproperties.", (Get-Date).ToString("ddMMyyyy_HHmmss"), ".output.csv")

$ErrorActionPreference = "Stop"

class UpdatePropertiesInformation
{
    [string]$Machine
    [string]$ProtectionState
    [string]$ProtectionStateDescription
    [string]$Exception
    [string]$UpdatePropertiesJobId
}

$protectedItemStatusArray = New-Object System.Collections.Generic.List[System.Object]

Function StartUpdatePropertiesJobItem($csvItem)
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

    $statusItemInfo = [UpdatePropertiesInformation]::new()
    $statusItemInfo.Machine = $sourceMachineName

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
    $statusItemInfo.ProtectionState = $protectedItem.ProtectionState
    $statusItemInfo.ProtectionStateDescription = $protectedItem.ProtectionStateDescription
    
    if ($protectedItem.ProtectionState -eq 'Protected')
    {
        LogTrace "Creating job to set machine properties..."
        $nicDetails = $protectedItem.NicDetailsList[0]
        if (($targetAvailabilitySet -eq '') -or ($targetAvailabilitySet -eq $null))
        {
            $updatePropertiesJob = Set-AzureRmRecoveryServicesAsrReplicationProtectedItem `
                -InputObject $protectedItem `
                -PrimaryNic $nicDetails.NicId `
                -RecoveryNicStaticIPAddress $targetPrivateIP `
                -RecoveryNetworkId $nicdetails.RecoveryVMNetworkId `
                -RecoveryNicSubnetName $nicdetails.RecoveryVMSubnetName `
                -UseManagedDisk $False `
                -Size $targetMachineSize
        } else {
            $targetAvailabilitySetObj = Get-AzureRmAvailabilitySet `
                -ResourceGroupName $targetPostFailoverResourceGroup `
                -Name $targetAvailabilitySet

            $updatePropertiesJob = Set-AzureRmRecoveryServicesAsrReplicationProtectedItem `
                -InputObject $protectedItem `
                -PrimaryNic $nicDetails.NicId `
                -RecoveryNicStaticIPAddress $targetPrivateIP `
                -RecoveryNetworkId $nicdetails.RecoveryVMNetworkId `
                -RecoveryNicSubnetName $nicdetails.RecoveryVMSubnetName `
                -UseManagedDisk $False `
                -RecoveryAvailabilitySet $targetAvailabilitySetObj.Id `
                -Size $targetMachineSize
        }

        if ($updatePropertiesJob -eq $null)
        {
            LogErrorAndThrow("Error creating update properties job for '$($sourceMachineName)'")
        }
        $statusItemInfo.UpdatePropertiesJobId = $updatePropertiesJob.Name
    } else {
        LogTrace "Item '$($sourceMachineName)' it is not in a Protected status"
    }
    $protectedItemStatusArray.Add($statusItemInfo)

    LogTrace "Update machine properties job created"
}

foreach ($csvItem in $csvObj)
{
    try {
        StartUpdatePropertiesJobItem -csvItem $csvItem
    } catch {
        LogError "Exception creating update properties job"
        $exceptionMessage = $_ | Out-String

        $statusItemInfo = [UpdatePropertiesInformation]::new()
        $statusItemInfo.Machine = $csvItem.SOURCE_MACHINE_NAME
        $statusItemInfo.Exception = "ERROR PROCESSING ITEM" 
        $protectedItemStatusArray.Add($statusItemInfo)

        LogError $exceptionMessage
    }
}

$protectedItemStatusArray.ToArray() | Export-Csv -LiteralPath $CsvOutput -Delimiter ',' -NoTypeInformation

LogTrace("[FINISH]-Finishing Asr update properties")

