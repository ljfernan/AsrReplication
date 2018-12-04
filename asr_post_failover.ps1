

#Connect-AzureRmAccount
Param(
    [parameter(Mandatory=$true)]
    $CsvFilePath
)

$ErrorActionPreference = "Stop"

$resolvedCsvPath = Resolve-Path -LiteralPath $CsvFilePath
$csvObj = Import-Csv $resolvedCsvPath -Delimiter ','

$CsvOutput = [string]::Concat($resolvedCsvPath.Path, ".postfailover.", (Get-Date).ToString("ddMMyyyy_HHmmss"), ".output.csv")
$TxtOutput = [string]::Concat($resolvedCsvPath.Path, ".postfailover.", (Get-Date).ToString("ddMMyyyy_HHmmss"), ".output.txt")

Function LogError([string] $Message)
{
    $logDate = (Get-Date).ToString("MM/dd/yyyy HH:mm:ss")
    $logMessage = [string]::Concat($logDate, "[ERROR]-", $Message)
    $logMessage | Out-File -FilePath $TxtOutput -Append
    Write-Host $logMessage
}

Function LogErrorAndThrow([string] $Message)
{
    $logDate = (Get-Date).ToString("MM/dd/yyyy HH:mm:ss")
    $logMessage = [string]::Concat($logDate, "[ERROR]-", $Message)
    $logMessage | Out-File -FilePath $TxtOutput -Append
    Write-Error $logMessage
}

Function LogTrace([string] $Message)
{
    $logDate = (Get-Date).ToString("MM/dd/yyyy HH:mm:ss")
    $logMessage = [string]::Concat($logDate, "[LOG]-", $Message)
    $logMessage | Out-File -FilePath $TxtOutput -Append
    Write-Host $logMessage
}

LogTrace("[START]-Post failover")
LogTrace("File: $($CsvFilePath)")

$protectedItemStatusArray = New-Object System.Collections.Generic.List[System.Object]

class PostFailOverInformation
{
    [string]$Machine
    [string]$Exception
    [string]$TargetMachine
    [string]$NsgId
}

Function ProcessItem($csvItem)
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

    $targetPostFailoverResourceGroup = $csvItem.TARGET_RESOURCE_GROUP
    $sourceMachineName = $csvItem.SOURCE_MACHINE_NAME
    $targetMachineName = $csvItem.TARGET_MACHINE_NAME
    $targetNsgName = $csvItem.TARGET_NSG_NAME
    $targetNsgResourceGroup = $csvItem.TARGET_NSG_RESOURCE_GROUP

    #Print replication settings
    LogTrace "[REPLICATIONJOB SETTINGS]-$($sourceMachineName)"
    LogTrace "SourceMachineName=$($sourceMachineName)"
    LogTrace "TargetMachineName=$($targetMachineName)"
    LogTrace "TargetNsgName=$($targetNsgName)"
    LogTrace "TargetNsgResourceGroup=$($targetNsgResourceGroup)"

    $statusItemInfo = [PostFailOverInformation]::new()
    $statusItemInfo.Machine = $sourceMachineName

    #Get target VM obj
    LogTrace "Getting target VM reference for VM '$($targetMachineName)' in resource group $($targetPostFailoverResourceGroup)"
    $targetVmObj = Get-AzureRmVm `
        -Name $targetMachineName `
        -ResourceGroupName $targetPostFailoverResourceGroup

    LogTrace "Getting Network Security Group reference for '$($targetNsgName)' in resource group '$($targetNsgResourceGroup)'"
    $targetNsgObj = Get-AzureRmNetworkSecurityGroup `
        -Name $targetNsgName `
        -ResourceGroupName $targetNsgResourceGroup

    $networkInterfaceId = $targetVmObj.NetworkProfile[0].NetworkInterfaces[0].Id
    LogTrace "Getting Raw Resource information for network interface '$($networkInterfaceId)'"
    $networkInterfaceResourceObj = Get-AzureRmResource `
        -ResourceId $networkInterfaceId

    LogTrace "Getting Network Interface reference for network interface '$($networkInterfaceResourceObj.Name)' in resource group '$($networkInterfaceResourceObj.ResourceGroupName)'"
    $networkInterfaceObj = Get-AzureRmNetworkInterface `
        -Name $networkInterfaceResourceObj.Name `
        -ResourceGroupName $networkInterfaceResourceObj.ResourceGroupName

    LogTrace "Setting Network Security Group to Network Interface '$($networkInterfaceResourceObj.Name)'"
    $networkInterfaceObj.NetworkSecurityGroup = $targetNsgObj
    Set-AzureRmNetworkInterface -NetworkInterface $networkInterfaceObj

    LogTrace "Network Security Group set for item '$($sourceMachineName)' in VM '$($targetMachineName)'"
    
    $statusItemInfo.TargetMachine = $targetMachineName
    $statusItemInfo.NsgId = $targetNsgObj.Id
    $protectedItemStatusArray.Add($statusItemInfo)
}


foreach ($csvItem in $csvObj)
{
    try {
        ProcessItem -csvItem $csvItem
    } catch {
        LogError "Exception executing item"
        $exceptionMessage = $_ | Out-String

        $statusItemInfo = [PostFailOverInformation]::new()
        $statusItemInfo.Machine = $csvItem.SOURCE_MACHINE_NAME
        $statusItemInfo.Exception = "ERROR RECOVERING INFO" 
        $protectedItemStatusArray.Add($statusItemInfo)

        LogError $exceptionMessage
    }
}

$protectedItemStatusArray.ToArray() | Export-Csv -LiteralPath $CsvOutput -Delimiter ',' -NoTypeInformation

LogTrace("[FINISH]-Post failover")

