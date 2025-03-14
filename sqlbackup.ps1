# Function to check OS language
function Get-OSLanguage {
    try {
        $culture = Get-WinSystemLocale | Select-Object -ExpandProperty Name
        return $culture
    } catch {
        return "en-US"  # Default to English if detection fails
    }
}

# Detect system language
$systemLanguage = Get-OSLanguage
$useCzech = $systemLanguage -like "cs*"

# Function for displaying localized messages
function Localized-Message {
    param (
        [string]$messageEn,
        [string]$messageCs
    )
    if ($useCzech) {
        Write-Host $messageCs
    } else {
        Write-Host $messageEn
    }
}

# Enter the server name (empty = localhost)
Localized-Message -messageEn "Enter the server name for SQL Server (leave blank for the default localhost):" -messageCs "Zadejte název serveru pro SQL Server (ponechte prázdné pro výchozí localhost):"
$serverName = Read-Host
if ([string]::IsNullOrWhiteSpace($serverName)) {
    $serverName = "localhost"
}

# Enter an instance name (empty = default instance)
Localized-Message -messageEn "Enter the SQL Server instance name (leave blank for the default instance):" -messageCs "Zadejte název instance SQL Serveru (ponechte prázdné pro výchozí instanci):"
$instanceName = Read-Host
if ([string]::IsNullOrWhiteSpace($instanceName)) {
    $instanceName = ""
}

# Specifying a folder for backups
Localized-Message -messageEn "Enter the destination folder for storing backups (e.g. D:\DB_backup):" -messageCs "Zadejte cílovou složku pro ukládání záloh (např. D:\DB_backup):"
$backupFolder = Read-Host
if ([string]::IsNullOrWhiteSpace($backupFolder)) {
    $backupFolder = "D:\DB_backup"
}

# Ensure backup folder exists
if (!(Test-Path -Path $backupFolder)) {
    New-Item -ItemType Directory -Path $backupFolder | Out-Null
}

# Specifying the number of backups to keep
do {
    Localized-Message -messageEn "Enter the number of most recent backups you want to keep (default: 5):" -messageCs "Zadejte počet nejnovějších záloh, které chcete uchovat (výchozí: 5):"
    $backupRetentionCount = Read-Host
    if ([string]::IsNullOrWhiteSpace($backupRetentionCount)) {
        $backupRetentionCount = 5
        break
    }
} while (-not ($backupRetentionCount -match '^\d+$'))

$backupRetentionCount = [int]$backupRetentionCount

# Saving SQL Credentials
$credentialFile = "$backupFolder\sqlCredentials.xml"
if (!(Test-Path $credentialFile)) {
    Localized-Message -messageEn "Enter the login name for SQL Server (leave blank for Windows Authentication):" -messageCs "Zadejte přihlašovací jméno pro SQL Server (ponechte prázdné pro Windows autentizaci):"
    $login = Read-Host
    if ($login) {
        Localized-Message -messageEn "Enter password:" -messageCs "Zadejte heslo:"
        $securePassword = Read-Host -AsSecureString
        $credentials = @{ Login = $login; Password = $securePassword }
    } else {
        $credentials = @{ Login = ""; Password = "" }
    }
    $credentials | Export-Clixml -Path $credentialFile
}

# Function to define the trigger based on backup frequency
function Get-TriggerByFrequency {
    param ([string]$frequency, [string]$time)
    switch ($frequency) {
        "Daily" { return New-ScheduledTaskTrigger -Daily -At $time }
        "Weekly" {
            Localized-Message -messageEn "Enter the day of the week for the backup (Monday-Sunday):" -messageCs "Zadejte den v týdnu pro zálohování (Pondělí-Neděle):"
            $dayOfWeek = Read-Host
            return New-ScheduledTaskTrigger -Weekly -DaysOfWeek $dayOfWeek -At $time
        }
        default {
            Localized-Message -messageEn "Unsupported backup frequency." -messageCs "Nepodporovaná frekvence zálohování."
            return $null
        }
    }
}

# Select backup frequency
do {
    Localized-Message -messageEn "Select backup frequency (1 = Daily, 2 = Weekly):" -messageCs "Vyberte frekvenci zálohování (1 = Denně, 2 = Týdně):"
    $frequencyChoice = Read-Host
} while ($frequencyChoice -notmatch "^[12]$")

$frequency = if ($frequencyChoice -eq "1") { "Daily" } else { "Weekly" }

# Enter backup time
do {
    Localized-Message -messageEn "Enter the backup time (24h HH:mm format):" -messageCs "Zadejte čas zálohování (ve formátu 24h HH:mm):"
    $time = Read-Host
} while (-not ($time -match '^(?:[01]\d|2[0-3]):[0-5]\d$'))

# Ensure backup folder exists
if (!(Test-Path -Path $backupFolder)) {
    New-Item -ItemType Directory -Path $backupFolder | Out-Null
}

# Creating a new backup script
$backupScriptPath = "$backupFolder\BackupScript.ps1"
$backupScriptContent = @"
# Define variables
`$serverName = "$serverName"
`$instanceName = "$instanceName"
`$backupFolder = "$backupFolder"
`$credentialFile = "$credentialFile"
`$backupRetentionCount = $backupRetentionCount
`$databases = @($selectedDatabases)

# Function to clean up old backups
function Cleanup-OldBackups {
    param (
        [string]`$backupFolder,
        [string]`$databaseName,
        [int]`$retentionCount
    )

    `$backupFiles = Get-ChildItem -Path `$backupFolder -Filter "`$databaseName-*.bak" | Sort-Object CreationTime -Descending
    if (`$backupFiles.Count -gt `$retentionCount) {
        `$filesToDelete = `$backupFiles | Select-Object -Skip `$retentionCount
        foreach (`$file in `$filesToDelete) {
            Write-Host "Deleting old backup: `$(`$file.FullName)"
            Remove-Item `$file.FullName -Force
        }
    } else {
        Write-Host "No old backups to delete for `$databaseName. Retaining last `$retentionCount backups."
    }
}

# Check if credentials exist before loading
if (Test-Path `$credentialFile) {
    `$credentials = Import-Clixml -Path `$credentialFile
    `$login = `$credentials.Login
    `$securePassword = `$credentials.Password
    `$password = if (`$securePassword) { 
        [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR(`$securePassword)
        ) 
    } else { 
        "" 
    }
} else {
    Write-Host "Credentials file missing! Exiting..."
    exit
}

# Function to perform database backup
function Backup-Databases {
    param (
        [string[]]`$databases,
        [string]`$serverName,
        [string]`$instanceName,
        [string]`$backupFolder,
        [string]`$login,
        [string]`$password
    )

    if (`$databases.Count -eq 0) {
        Write-Host "No databases selected for backup. Exiting..."
        exit
    }

    foreach (`$db in `$databases) {
        `$backupFile = "`$backupFolder\$db-$(Get-Date -Format 'yyyyMMddHHmmss').bak"
        `$sqlCommand = "BACKUP DATABASE [`$db] TO DISK = '`$backupFile' WITH FORMAT, MEDIANAME = 'SQLServerBackups', NAME = 'Full Backup of `$db';"

        try {
            if (`$login) {
                Invoke-Sqlcmd -Query `$sqlCommand -ServerInstance "`$serverName`$instanceName" -Username `$login -Password `$password
            } else {
                Invoke-Sqlcmd -Query `$sqlCommand -ServerInstance "`$serverName`$instanceName" -IntegratedSecurity
            }
            Write-Host "Backup completed for database: `$db, saved to `$backupFile"
        } catch {
            Write-Host "Error backing up database: `$db. Error: `$_"
        }
    }
}

# Execute the backup process
Backup-Databases -databases `$databases -serverName `$serverName -instanceName `$instanceName -backupFolder `$backupFolder -login `$login -password `$password

# Clean up old backups
foreach (`$db in `$databases) {
    Write-Host "Starting cleanup for database: `$db"
    Cleanup-OldBackups -backupFolder `$backupFolder -databaseName `$db -retentionCount `$backupRetentionCount
    Write-Host "Cleanup completed for database: `$db"
}
"@

# Save script content to file
Set-Content -Path $backupScriptPath -Value $backupScriptContent

# Define task name
$taskName = "MSSQL Backup Task"

# Generate trigger
$trigger = Get-TriggerByFrequency -frequency $frequency -time $time
if ($null -eq $trigger) {
    Localized-Message -messageEn "Failed to create a trigger. Exiting script." -messageCs "Nepodařilo se vytvořit spouštěč. Skript se ukončuje."
    exit
}

# Remove existing task if present
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

# Re-generate trigger after task removal
$trigger = Get-TriggerByFrequency -frequency $frequency -time $time
if ($null -eq $trigger) {
    Localized-Message -messageEn "Failed to create a trigger. Exiting script." -messageCs "Nepodařilo se vytvořit spouštěč. Skript se ukončuje."
    exit
}

# Create Scheduled Task
$action = New-ScheduledTaskAction -Execute "Powershell.exe" -Argument "-File `"$backupScriptPath`""
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings

Localized-Message -messageEn "Backup was successfully set up." -messageCs "Zálohování bylo úspěšně nastaveno."
