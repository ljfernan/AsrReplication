

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

$CsvOutput = [string]::Concat($resolvedCsvPath.Path, ".testfailover.", (Get-Date).ToString("ddMMyyyy_HHmmss"), ".output.csv")

$ErrorActionPreference = "Stop"

$protectedItemStatusArray = New-Object System.Collections.Generic.List[System.Object]
# $statusItemInfo = New-Object PSObject
# $statusItemInfo | Add-Member -type NoteProperty -Name 'Machine' -Value $sourceMachineName
# $protectedItemStatusArray +=$statusItemInfo

class TestFailOverInformation
{
    [string]$Machine
    [string]$Exception
    [string]$TestFailoverJobId
    [string]$TestFailoverState
    [string]$TestFailoverStateDescription
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
    $targetTestFailoverVNET = $csvItem.TESTFAILOVER_VNET
    $targetTestFailoverResourceGroup = $csvItem.TESTFAILOVER_RESOURCE_GROUP

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
    LogTrace "TargetTestFailoverVNET=$($targetTestFailoverVNET)"
    LogTrace "TargetTestFailoverResourceGroup=$($targetTestFailoverResourceGroup)"

    $statusItemInfo = [TestFailOverInformation]::new()
    $statusItemInfo.Machine = $sourceMachineName

    $targetVault = Get-AzureRmRecoveryServicesVault -Name $vaultName
    if ($targetVault -eq $null)
    {
        LogError("Vault with name '$($vaultName)' unable to find")
    }

    Set-AzureRmRecoveryServicesAsrVaultContext -Vault $targetVault

    $fabricServer = Get-AzureRmRecoveryServicesAsrFabric -FriendlyName $sourceProcessServer
    $protectionContainer = Get-AzureRmRecoveryServicesAsrProtectionContainer -Fabric $fabricServer
    
    $protectableVM = Get-AzureRmRecoveryServicesAsrProtectableItem `
        -ProtectionContainer $protectionContainer `
        -FriendlyName $sourceMachineName

    if ($protectableVM.ReplicationProtectedItemId -ne $null)
    {
        $protectedItem = Get-AzureRmRecoveryServicesAsrReplicationProtectedItem `
            -ProtectionContainer $protectionContainer `
            -FriendlyName $sourceMachineName
        
        if ($protectedItem.AllowedOperations.Contains('TestFailover'))
        {
            #Get details of the test failover virtual network to be used
            $targetTestFailoverVNETObj = Get-AzureRmVirtualNetwork `
                -Name $targetTestFailoverVNET `
                -ResourceGroupName $targetTestFailoverResourceGroup 

            #Start the test failover operation
            $testFailoverJob = Start-AzureRmRecoveryServicesAsrTestFailoverJob `
                -ReplicationProtectedItem $protectedItem `
                -AzureVMNetworkId $targetTestFailoverVNETObj.Id `
                -Direction PrimaryToRecovery
            $statusItemInfo.TestFailoverJobId = $testFailoverJob.ID
        } else {
            LogTrace "TestFailover operation not allowed for item '$($sourceMachineName)'"
            $statusItemInfo.TestFailoverState = $protectedItem.TestFailoverState
            $statusItemInfo.TestFailoverStateDescription = $protectedItem.TestFailoverStateDescription
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

        $statusItemInfo = [TestFailOverInformation]::new()
        $statusItemInfo.Machine = $csvItem.SOURCE_MACHINE_NAME
        $statusItemInfo.Exception = "ERROR RECOVERING INFO" 
        $protectedItemStatusArray.Add($statusItemInfo)

        LogError $exceptionMessage
    }
}

$protectedItemStatusArray.ToArray() | Export-Csv -LiteralPath $CsvOutput -Delimiter ',' -NoTypeInformation

LogTrace("[FINISH]-Finishing properties check")

