<#
.SYNOPSIS
    Manual SQL Server database backup, cleanup, and optional maintenance script.

.DESCRIPTION
    Performs full backups of selected SQL Server databases, removes older backup files
    based on retention count, and optionally runs maintenance on selected databases.

    Features:
    - Auto-checks and silently installs SqlServer PowerShell module if missing
    - Uses Windows Authentication
    - Supports long-running backups and maintenance
    - Prevents false success logs
    - Trusts SQL Server certificate for encrypted local/internal connections
#>

# --- User Configuration Variables ---

$serverName = "localhost"
$instanceName = ""                      # "" for default instance, "\SQLEXPRESS" for named instance
$backupFolder = "D:\DB_backup"
$backupRetentionCount = 3

# Optional SQL authentication
# Leave both empty to use Windows Authentication
$sqlUsername = ""
$sqlPassword = ""

# Databases to back up
$databasesToBackup = @(
    "master",
    "Helios001",
    "Helios002"
)

# Databases to maintain
$databasesToMaintain = @(
    "Helios001",
    "Helios002"
)

# Email reporting
$emailEnabled = $true
$smtpServer = "email.server.com"
$smtpPort = 587
$smtpUseSsl = $true
$smtpUsername = "smtp@domain.com"
$smtpPassword = "securepassword"
$emailFrom = "backup@contoso.com"
$emailTo = @(
    "report@email.contoso.com",
    "report2@email.contoso.com"
)
$emailSubjectPrefix = "[SQL Backup Report]"



$script:BackupResults = @()
$script:MaintenanceResults = @()


# --- Functions ---

function Send-ReportEmail {
    param (
        [string]$Subject,
        [string]$Body
    )

    if (-not $emailEnabled) {
        return
    }

    try {
        $securePassword = ConvertTo-SecureString $smtpPassword -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential($smtpUsername, $securePassword)

        Send-MailMessage `
            -SmtpServer $smtpServer `
            -Port $smtpPort `
            -UseSsl:$smtpUseSsl `
            -Credential $credential `
            -From $emailFrom `
            -To $emailTo `
            -Subject $Subject `
            -Body $Body `
            -BodyAsHtml:$false `
            -ErrorAction Stop
    }
    catch {
        Write-Log -Message "Failed to send report email: $($_.Exception.Message)" -Level "ERROR"
    }
}

function Build-RunReport {
    param (
        [datetime]$StartTime,
        [datetime]$EndTime,
        [string]$ServerInstance
    )

    $duration = New-TimeSpan -Start $StartTime -End $EndTime

    $backupFailedCount = ($script:BackupResults | Where-Object { $_.Status -eq "FAILED" }).Count
    $maintenanceFailedCount = ($script:MaintenanceResults | Where-Object { $_.Status -eq "FAILED" }).Count

    if ($backupFailedCount -gt 0 -or $maintenanceFailedCount -gt 0) {
        $overallStatus = "FAILED"
    }
    else {
        $overallStatus = "OK"
    }

    $lines = @()
    $lines += "$emailSubjectPrefix $overallStatus"
    $lines += ""
    $lines += "Server: $ServerInstance"
    $lines += "Started: $($StartTime.ToString('yyyy-MM-dd HH:mm:ss'))"
    $lines += "Finished: $($EndTime.ToString('yyyy-MM-dd HH:mm:ss'))"
    $lines += "Duration: $($duration.ToString())"
    $lines += ""

    $lines += "=== BACKUP RESULTS ==="
    if ($script:BackupResults.Count -eq 0) {
        $lines += "No backup results."
    }
    else {
        foreach ($item in $script:BackupResults) {
            if ([string]::IsNullOrWhiteSpace($item.Message)) {
                $lines += "$($item.Database) backup $($item.Status)"
            }
            else {
                $lines += "$($item.Database) backup $($item.Status) - $($item.Message)"
            }
        }
    }

    $lines += ""
    $lines += "=== MAINTENANCE RESULTS ==="
    if ($script:MaintenanceResults.Count -eq 0) {
        $lines += "No maintenance results."
    }
    else {
        foreach ($item in $script:MaintenanceResults) {
            if ([string]::IsNullOrWhiteSpace($item.Message)) {
                $lines += "$($item.Database) maintenance $($item.Status)"
            }
            else {
                $lines += "$($item.Database) maintenance $($item.Status) - $($item.Message)"
            }
        }
    }

    return @{
        OverallStatus = $overallStatus
        Body = ($lines -join [Environment]::NewLine)
    }
}

function Get-SqlEditionInfo {
    param (
        [string]$ServerInstance,
        [System.Management.Automation.PSCredential]$SqlCredential = $null
    )

    $query = "SELECT CAST(SERVERPROPERTY('Edition') AS nvarchar(200)) AS Edition;"

    $invokeParams = @{
        Query                  = $query
        ServerInstance         = $ServerInstance
        QueryTimeout           = 30
        TrustServerCertificate = $true
        ErrorAction            = 'Stop'
    }

    if ($null -ne $SqlCredential) {
        $invokeParams['Username'] = $SqlCredential.UserName
        $invokeParams['Password'] = $SqlCredential.GetNetworkCredential().Password
    }

    $result = Invoke-Sqlcmd @invokeParams

    if (-not $result -or -not $result.Edition) {
        throw "Unable to detect SQL Server edition."
    }

    return [string]$result.Edition
}

function Get-SqlCredential {
    param (
        [string]$Username,
        [string]$Password
    )

    if ([string]::IsNullOrWhiteSpace($Username) -and [string]::IsNullOrWhiteSpace($Password)) {
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($Username) -or [string]::IsNullOrWhiteSpace($Password)) {
        throw "If using SQL authentication, both `\$sqlUsername and `\$sqlPassword must be filled in."
    }

    $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
    return New-Object System.Management.Automation.PSCredential($Username, $securePassword)
}

function Write-Log {
    param (
        [string]$Message,
        [ValidateSet("INFO", "ERROR", "WARN")]
        [string]$Level = "INFO"
    )

    $logFile = Join-Path -Path $backupFolder -ChildPath "backup_log.txt"
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"

    Add-Content -Path $logFile -Value $logMessage
    Write-Host $logMessage
}

function Ensure-SqlServerModule {
    $module = Get-Module -ListAvailable -Name SqlServer

    if (-not $module) {
        try {
            Write-Host "SqlServer module not found. Installing silently..."

            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

            if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers -Confirm:$false -ErrorAction Stop | Out-Null
            }

            $psRepo = Get-PSRepository -Name "PSGallery" -ErrorAction SilentlyContinue
            if ($psRepo -and $psRepo.InstallationPolicy -ne "Trusted") {
                Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted -ErrorAction Stop
            }

            Install-Module SqlServer -Scope AllUsers -Force -AllowClobber -Confirm:$false -SkipPublisherCheck -ErrorAction Stop | Out-Null
        }
        catch {
            throw "Failed to install SqlServer module silently: $($_.Exception.Message)"
        }
    }

    try {
        Import-Module SqlServer -ErrorAction Stop
    }
    catch {
        throw "Failed to import SqlServer module: $($_.Exception.Message)"
    }
}

function Backup-Databases {
    param (
        [string[]]$Databases,
        [string]$ServerInstance,
        [string]$BackupFolder,
        [System.Management.Automation.PSCredential]$SqlCredential = $null
    )

    $edition = Get-SqlEditionInfo -ServerInstance $ServerInstance -SqlCredential $SqlCredential
    $useCompression = ($edition -notmatch 'Express')

    if ($useCompression) {
        Write-Log -Message "SQL Server edition detected: [$edition]. Backup compression enabled." -Level "INFO"
    }
    else {
        Write-Log -Message "SQL Server edition detected: [$edition]. Backup compression not supported, using uncompressed backups." -Level "WARN"
    }

    foreach ($db in $Databases) {
        Cleanup-OldBackups `
            -BackupFolder $BackupFolder `
            -DatabaseName $db `
            -RetentionCount $backupRetentionCount `
            -PrepareForNewBackup

        Write-Host "Starting backup for database: $db"

        $timestamp = Get-Date -Format "yyyyMMddHHmmss"
        $backupFile = Join-Path -Path $BackupFolder -ChildPath "$db-$timestamp.bak"

        if ($useCompression) {
            $sqlCommand = @"
BACKUP DATABASE [$db]
TO DISK = N'$backupFile'
WITH INIT, COMPRESSION, CHECKSUM, STATS = 10;
"@
        }
        else {
            $sqlCommand = @"
BACKUP DATABASE [$db]
TO DISK = N'$backupFile'
WITH INIT, CHECKSUM, STATS = 10;
"@
        }

        try {
            $invokeParams = @{
                Query                  = $sqlCommand
                ServerInstance         = $ServerInstance
                QueryTimeout           = 0
                TrustServerCertificate = $true
                ErrorAction            = 'Stop'
            }

            if ($null -ne $SqlCredential) {
                $invokeParams['Username'] = $SqlCredential.UserName
                $invokeParams['Password'] = $SqlCredential.GetNetworkCredential().Password
            }

            Invoke-Sqlcmd @invokeParams

            if (Test-Path $backupFile) {
                Write-Log -Message "Successfully backed up database: $db to $backupFile" -Level "INFO"
                $script:BackupResults += [pscustomobject]@{
                    Database = $db
                    Status   = "OK"
                    Message  = $backupFile
                }
                Write-Host "Backup for $db completed successfully."
            }
            else {
                throw "SQL command finished but backup file was not found: $backupFile"
            }
        }
        catch {
            $msg = $_.Exception.Message
            Write-Log -Message "Failed to back up database [$db]: $msg" -Level "ERROR"
            $script:BackupResults += [pscustomobject]@{
                Database = $db
                Status   = "FAILED"
                Message  = $msg
            }
            Write-Error "Failed to back up database [$db]: $msg"
        }
    }
}

function Cleanup-OldBackups {
    param (
        [string]$BackupFolder,
        [string]$DatabaseName,
        [int]$RetentionCount,
        [switch]$PrepareForNewBackup
    )

    Write-Host "Starting cleanup for database: $DatabaseName"

    $effectiveRetention = $RetentionCount

    if ($PrepareForNewBackup) {
        $effectiveRetention = [Math]::Max($RetentionCount - 1, 0)
    }

    $backupFiles = Get-ChildItem -Path $BackupFolder -Filter "$DatabaseName-*.bak" -File |
        Sort-Object LastWriteTime -Descending

    if ($backupFiles.Count -gt $effectiveRetention) {
        $filesToDelete = $backupFiles | Select-Object -Skip $effectiveRetention

        foreach ($file in $filesToDelete) {
            try {
                Write-Host "Deleting old backup: $($file.FullName)"
                Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                Write-Log -Message "Deleted old backup: $($file.FullName)" -Level "INFO"
            }
            catch {
                Write-Log -Message "Failed to delete old backup [$($file.FullName)]: $($_.Exception.Message)" -Level "ERROR"
                Write-Error "Failed to delete old backup [$($file.FullName)]: $($_.Exception.Message)"
            }
        }
    }
    else {
        Write-Host "No old backups to delete for $DatabaseName. Retaining up to $effectiveRetention backups before new backup."
    }

    Write-Host "Cleanup completed for database: $DatabaseName"
}

function Perform-Maintenance {
    param (
        [string[]]$Databases,
        [string]$ServerInstance,
        [System.Management.Automation.PSCredential]$SqlCredential = $null
    )

    foreach ($db in $Databases) {
        Write-Host "Starting maintenance for database: $db"

        $sqlCommand = @"
USE [$db];
SET NOCOUNT ON;

DECLARE
    @SchemaName sysname,
    @TableName sysname,
    @IndexName sysname,
    @Frag float,
    @PageCount bigint,
    @Command nvarchar(max);

DECLARE index_cursor CURSOR FAST_FORWARD FOR
SELECT
    s.name AS SchemaName,
    t.name AS TableName,
    i.name AS IndexName,
    ips.avg_fragmentation_in_percent,
    ips.page_count
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
JOIN sys.indexes i
    ON ips.object_id = i.object_id
   AND ips.index_id = i.index_id
JOIN sys.tables t
    ON ips.object_id = t.object_id
JOIN sys.schemas s
    ON t.schema_id = s.schema_id
WHERE
    ips.index_id > 0
    AND i.name IS NOT NULL
    AND ips.page_count >= 1000
ORDER BY
    ips.avg_fragmentation_in_percent DESC,
    ips.page_count DESC;

OPEN index_cursor;

FETCH NEXT FROM index_cursor
INTO @SchemaName, @TableName, @IndexName, @Frag, @PageCount;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @Command = NULL;

    IF @Frag >= 10 AND @Frag < 30
    BEGIN
        SET @Command =
            N'ALTER INDEX [' + REPLACE(@IndexName, ']', ']]') + N'] ON [' +
            REPLACE(@SchemaName, ']', ']]') + N'].[' +
            REPLACE(@TableName, ']', ']]') + N'] REORGANIZE';
    END
    ELSE IF @Frag >= 30
    BEGIN
        SET @Command =
            N'ALTER INDEX [' + REPLACE(@IndexName, ']', ']]') + N'] ON [' +
            REPLACE(@SchemaName, ']', ']]') + N'].[' +
            REPLACE(@TableName, ']', ']]') + N'] REBUILD';
    END

    IF @Command IS NOT NULL
    BEGIN
        BEGIN TRY
            EXEC sp_executesql @Command;
        END TRY
        BEGIN CATCH
            PRINT 'FAILED: [' + @SchemaName + '].[' + @TableName + '].[' + @IndexName + '] | ' + ERROR_MESSAGE();
        END CATCH
    END

    FETCH NEXT FROM index_cursor
    INTO @SchemaName, @TableName, @IndexName, @Frag, @PageCount;
END

CLOSE index_cursor;
DEALLOCATE index_cursor;

EXEC sp_updatestats;
"@

        try {
            $invokeParams = @{
                Query                  = $sqlCommand
                ServerInstance         = $ServerInstance
                QueryTimeout           = 0
                TrustServerCertificate = $true
                ErrorAction            = 'Stop'
            }

            if ($null -ne $SqlCredential) {
                $invokeParams['Username'] = $SqlCredential.UserName
                $invokeParams['Password'] = $SqlCredential.GetNetworkCredential().Password
            }

            Invoke-Sqlcmd @invokeParams

            Write-Log -Message "Fragmentation-based maintenance for database [$db] completed successfully." -Level "INFO"
            $script:MaintenanceResults += [pscustomobject]@{
                Database = $db
                Status   = "OK"
                Message  = ""
            }
            Write-Host "Maintenance for $db completed successfully."
        }
        catch {
            $msg = $_.Exception.Message
            Write-Log -Message "Failed to perform maintenance on database [$db]: $msg" -Level "ERROR"
            $script:MaintenanceResults += [pscustomobject]@{
                Database = $db
                Status   = "FAILED"
                Message  = $msg
            }
            Write-Error "Failed to perform maintenance on database [$db]: $msg"
        }
    }
}

# --- Script Execution ---

$scriptStartTime = Get-Date
$serverInstance = $null

try {
    if (-not (Test-Path $backupFolder)) {
        New-Item -Path $backupFolder -ItemType Directory -Force | Out-Null
    }

    Ensure-SqlServerModule

    $serverInstance = $serverName + $instanceName
    $sqlCredential = Get-SqlCredential -Username $sqlUsername -Password $sqlPassword

    if ($null -eq $sqlCredential) {
        Write-Log -Message "Using Windows Authentication for SQL connection." -Level "INFO"
    }
    else {
        Write-Log -Message "Using SQL Authentication for SQL connection with user [$($sqlCredential.UserName)]." -Level "INFO"
    }

    Write-Log -Message "Backup script started for server instance: $serverInstance" -Level "INFO"

    Backup-Databases `
        -Databases $databasesToBackup `
        -ServerInstance $serverInstance `
        -BackupFolder $backupFolder `
        -SqlCredential $sqlCredential

    if ($databasesToMaintain.Count -gt 0) {
        Write-Host "Starting database maintenance..."
        Perform-Maintenance `
            -Databases $databasesToMaintain `
            -ServerInstance $serverInstance `
            -SqlCredential $sqlCredential
    }
    else {
        Write-Host "No databases specified for maintenance. Skipping this step."
    }

    $logFile = Join-Path -Path $backupFolder -ChildPath "backup_log.txt"
    if (Test-Path $logFile) {
        $logContent = Get-Content -Path $logFile
        if ($logContent.Count -gt 100) {
            $logContent | Select-Object -Last 100 | Set-Content -Path $logFile
        }
    }

    Write-Log -Message "Backup and maintenance script finished." -Level "INFO"
}
catch {
    Write-Error "Fatal script error: $($_.Exception.Message)"
    Write-Log -Message "Fatal script error: $($_.Exception.Message)" -Level "ERROR"
}
finally {
    $scriptEndTime = Get-Date

    if ($null -ne $serverInstance) {
        $report = Build-RunReport `
            -StartTime $scriptStartTime `
            -EndTime $scriptEndTime `
            -ServerInstance $serverInstance

        $subject = "$emailSubjectPrefix $($report.OverallStatus) - $serverInstance - $($scriptEndTime.ToString('yyyy-MM-dd HH:mm:ss'))"
        Send-ReportEmail -Subject $subject -Body $report.Body
    }
}
