class MigrationLogger {
    
    [void] LogError([string] $Message)
    {
        $logDate = (Get-Date).ToString("MM/dd/yyyy HH:mm:ss")
        $logMessage = [string]::Concat($logDate, "[ERROR]-", $Message)
        Write-Output $logMessage
        Write-Host $logMessage
    }
    
    [void] LogErrorAndThrow([string] $Message)
    {
        $logDate = (Get-Date).ToString("MM/dd/yyyy HH:mm:ss")
        $logMessage = [string]::Concat($logDate, "[ERROR]-", $Message)
        Write-Output $logMessage
        Write-Error $logMessage
    }
    
    [void] LogTrace([string] $Message)
    {
        $logDate = (Get-Date).ToString("MM/dd/yyyy HH:mm:ss")
        $logMessage = [string]::Concat($logDate, "[LOG]-", $Message)
        Write-Output $logMessage
        Write-Host $logMessage
    }
}
