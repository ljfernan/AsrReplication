Param(
    [parameter(Mandatory=$true)]
    $CsvFilePath
)

$ErrorActionPreference = "Stop"

$scriptsPath = $PSScriptRoot
if ($PSScriptRoot -eq "") {
    $scriptsPath = "."
}

Import-Module "$scriptsPath\asr_logger.psm1"
Import-Module "$scriptsPath\asr_common.psm1"
Import-Module "$scriptsPath\asr_csv_processor.psm1"

Function ProcessItem($processor, $csvItem, $reportItem)
{
    try {
        $reportItem | Add-Member NoteProperty "ProtectableStatus" $null
        $reportItem | Add-Member NoteProperty "ProtectionState" $null
        $reportItem | Add-Member NoteProperty "ProtectionStateDescription" $null
        
        $vaultName = $csvItem.VAULT_NAME
        $sourceMachineName = $csvItem.SOURCE_MACHINE_NAME
        $sourceConfigurationServer = $csvItem.CONFIGURATION_SERVER
    
        $asrCommon.EnsureVaultContext($vaultName)
        $protectionContainer = $asrCommon.GetProtectionContainer($sourceConfigurationServer)
        $protectableVM = $asrCommon.GetProtectableItem($protectionContainer, $sourceMachineName)
    
        $reportItem.ProtectableStatus = $protectableVM.ProtectionStatus
    
        if ($protectableVM.ReplicationProtectedItemId -ne $null)
        {
            $protectedItem = $asrCommon.GetProtectedItem($protectionContainer, $sourceMachineName)
    
            $reportItem.ProtectionState = $protectedItem.ProtectionState
            $reportItem.ProtectionStateDescription = $protectedItem.ProtectionStateDescription
        }
    }
    catch {
        $exceptionMessage = $_ | Out-String
        $processor.Logger.LogError($exceptionMessage)
        throw
    }
}

$logger = New-AsrLoggerInstance -CommandPath $PSCommandPath
$asrCommon = New-AsrCommonInstance -Logger $logger
$processor = New-CsvProcessorInstance -Logger $logger -ProcessItemFunction $function:ProcessItem
$processor.ProcessFile($CsvFilePath)
