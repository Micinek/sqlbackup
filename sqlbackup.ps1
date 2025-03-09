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
    Localized-Message -messageEn "Server used: $serverName (default value)" -messageCs "Použitý server: $serverName (výchozí hodnota)"
}

# Enter an instance name (empty = default instance)
Localized-Message -messageEn "Enter the SQL Server instance name (leave blank for the default instance):" -messageCs "Zadejte název instance SQL Serveru (ponechte prázdné pro výchozí instanci):"
$instanceName = Read-Host
if ([string]::IsNullOrWhiteSpace($instanceName)) {
    $instanceName = ""
    Localized-Message -messageEn "Instance used: Default (empty value)" -messageCs "Použitá instance: Výchozí (prázdná hodnota)"
}

# Specifying a folder for backups
Localized-Message -messageEn "Enter the destination folder for storing backups (e.g. D:\DB_backup):" -messageCs "Zadejte cílovou složku pro ukládání záloh (např. D:\DB_backup):"
$backupFolder = Read-Host
if ([string]::IsNullOrWhiteSpace($backupFolder)) {
    $backupFolder = "D:\DB_backup"
    Localized-Message -messageEn "Folder used: $backupFolder (default value)" -messageCs "Použitá složka: $backupFolder (výchozí hodnota)"
}

# Specifying the number of backups to keep
Localized-Message -messageEn "Enter the number of most recent backups you want to keep (default: 5):" -messageCs "Zadejte počet nejnovějších záloh, které chcete uchovat (výchozí: 5):"
$backupRetentionCount = Read-Host
if (-not ($backupRetentionCount -match '^\d+$')) {
    $backupRetentionCount = 5
    Localized-Message -messageEn "Number of backups used: $backupRetentionCount (default value)" -messageCs "Použitý počet záloh: $backupRetentionCount (výchozí hodnota)"
} else {
    $backupRetentionCount = [int]$backupRetentionCount
    Localized-Message -messageEn "Number of backups used: $backupRetentionCount" -messageCs "Použitý počet záloh: $backupRetentionCount"
}

# Function to save login details to a secure file
function Save-Credentials {
    param (
        [string]$credentialFile
    )
    Localized-Message -messageEn "Enter the login name for SQL Server (leave blank for Windows Authentication):" -messageCs "Zadejte přihlašovací jméno pro SQL Server (ponechte prázdné pro Windows autentizaci):"
    $login = Read-Host
    if ($login) {
        Localized-Message -messageEn "Enter password:" -messageCs "Zadejte heslo:"
        $securePassword = Read-Host -AsSecureString
        $credentials = @{
            Login = $login
            Password = $securePassword
        }
    } else {
        $credentials = @{
            Login = ""
            Password = ""
        }
    }

    # Save to file
    $credentials | Export-Clixml -Path $credentialFile
    Localized-Message -messageEn "The login details have been saved in a secure file." -messageCs "Přihlašovací údaje byly uloženy do zabezpečeného souboru."
}

# Variables Definition
$credentialFile = "$backupFolder\sqlCredentials.xml"  # Secure file for saving login details

# Function to retrieve credentials from a secure file
function Load-Credentials {
    param (
        [string]$credentialFile
    )
    if (Test-Path $credentialFile) {
        $credentials = Import-Clixml -Path $credentialFile
        $login = $credentials.Login
        $securePassword = $credentials.Password
        if ($login) {
            $password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword))
        } else {
            $password = ""
        }
        return @{
            Login = $login
            Password = $password
        }
    } else {
        Localized-Message -messageEn "The credentials file was not found." -messageCs "Soubor s přihlašovacími údaji nebyl nalezen."
        exit
    }
}


# Function to connect to SQL server and get a list of databases
function Get-Databases {
    param (
        [string]$serverName,
        [string]$instanceName,
        [string]$login,
        [string]$password
    )

    $connectionString = "Server=$serverName$instanceName;"
    if ($login) {
        $connectionString += "User ID=$login;Password=$password;"
    } else {
        $connectionString += "Integrated Security=True;"
    }

    # SQL query to get a list of user databases
    $query = "SELECT name FROM sys.databases WHERE name NOT IN ('master', 'tempdb', 'model', 'msdb')"

    try {
        if ($login) {
            $databases = Invoke-Sqlcmd -Query $query -ServerInstance "$serverName$instanceName" -Username $login -Password $password | Select-Object -ExpandProperty name
        } else {
            $databases = Invoke-Sqlcmd -Query $query -ServerInstance "$serverName$instanceName" -IntegratedSecurity | Select-Object -ExpandProperty name
        }

        return @($databases)
    }
    catch {
        Write-Error "Failed to connect to SQL server or run query: $_"
        return @()
    }
}

# Database backup features
function Backup-Databases {
    param (
        [string[]]$databases,
        [string]$serverName,
        [string]$instanceName,
        [string]$backupFolder,
        [string]$login,
        [string]$password
    )
    
    foreach ($db in $databases) {
        $backupFile = "$backupFolder\$db-$(Get-Date -Format 'yyyyMMddHHmmss').bak"
        $sqlCommand = "BACKUP DATABASE [$db] TO DISK = '$backupFile' WITH FORMAT, MEDIANAME = 'SQLServerBackups', NAME = 'Full Backup of $db';"
        
        if ($login) {
            Invoke-Sqlcmd -Query $sqlCommand -ServerInstance "$serverName$instanceName" -Username $login -Password $password
        } else {
            Invoke-Sqlcmd -Query $sqlCommand -ServerInstance "$serverName$instanceName" -IntegratedSecurity
        }
        Log-BackupCompletion -db $db -backupFile $backupFile
    }
}

# Function to create a task in Task Scheduler with a local user
function Create-ScheduledTask {
    param (
        [string]$taskName,
        [string]$scriptPath,
        [string]$frequency,
        [string]$time
    )

    # Action: Starts PowerShell skript
    $action = New-ScheduledTaskAction -Execute "Powershell.exe" -Argument "-File `"$scriptPath`""

# Trigger definition by frequency
function Get-TriggerByFrequency {
    param (
        [string]$frequency,
        [string]$time
    )
    
    switch ($frequency) {
        "Daily" {
            return New-ScheduledTaskTrigger -Daily -At $time
        }
        "Weekly" {
            return New-ScheduledTaskTrigger -Weekly -At $time
        }
        default {
            Localized-Message -messageEn "Unsupported backup frequency." -messageCs "Nepodporovaná frekvence zálohování."
            return $null
        }
    }
}

# Setting the "Run with highest privileges" option
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

# First, we check if the task already exists
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Localized-Message -messageEn "Task '$taskName' already exists, will be overwritten..." -messageCs "Úloha '$taskName' již existuje, bude přepsána..."
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

# Create a task
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings

Localized-Message -messageEn "The task '$taskName' has been created in Task Scheduler." -messageCs "Úloha '$taskName' byla vytvořena v Plánovači úloh."
}

function Update-ScheduledTask {
    param (
        [string]$taskName
    )

    # We find an existing task
    Localized-Message -messageEn "Debug: Looking for task named '$taskName'..." -messageCs "Ladění: Hledání úlohy s názvem '$taskName'..."
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if (!$task) {
        Localized-Message -messageEn "Task '$taskName' does not exist." -messageCs "Úloha '$taskName' neexistuje."
        return
    }

    Localized-Message -messageEn "Debug: Task found. Running schtasks.exe to edit the task..." -messageCs "Ladění: Úloha nalezena. Spouští se schtasks.exe pro úpravu úlohy..."

    # Let's run schtasks.exe to edit the task
    $schtasksCommand = "schtasks /change /tn `"$taskName`" /ru System /rp /rl HIGHEST"
    Localized-Message -messageEn "Debug: we run the command: $schtasksCommand" -messageCs "Ladění: Spouštíme příkaz: $schtasksCommand"
    Invoke-Expression $schtasksCommand

    Localized-Message -messageEn "Task '$taskName' has been updated to run with the highest privileges and regardless of user login." -messageCs "Úloha '$taskName' byla aktualizována tak, aby se spouštěla s nejvyššími oprávněními a bez ohledu na přihlášení uživatele."
}


# The main part of the script
if (-not (Test-Path $credentialFile)) {
    Save-Credentials -credentialFile $credentialFile
}

$credentials = Load-Credentials -credentialFile $credentialFile
$login = $credentials.Login
$password = $credentials.Password

$databases = Get-Databases -serverName $serverName -instanceName $instanceName -login $login -password $password

if ($databases.Count -eq 0) {
    Localized-Message -messageEn "No databases were found to back up." -messageCs "Nebyly nalezeny žádné databáze k zálohování."
    exit
}

Localized-Message -messageEn "Available databases:" -messageCs "Dostupné databáze:"
$databases = @($databases) # Let's make sure it's an array
for ($i = 0; $i -lt $databases.Count; $i++) {
    Write-Host "$($i + 1). $($databases[$i])" # We will use the full database name
}

Localized-Message -messageEn "Enter the database numbers you want to back up (separated by a comma):" -messageCs "Zadejte čísla databází, které chcete zálohovat (oddělená čárkou):"
$selectedIndices = Read-Host
$selectedDatabases = $selectedIndices -split ',' | ForEach-Object {
    $index = $_.Trim() -as [int]  # Conversion to number
    if ($index -gt 0 -and $index -le $databases.Count) {
        $databases[$index - 1]  # Correct indexing of database names
    }
}

Localized-Message -messageEn "Selected databases to back up: $($selectedDatabases -join ', ')" -messageCs "Vybrané databáze k zálohování: $($selectedDatabases -join ', ')"

Localized-Message -messageEn "Select backup frequency:" -messageCs "Vyberte frekvenci zálohování:"
Localized-Message -messageEn "1. Daily" -messageCs "1. Denně"
Localized-Message -messageEn "2. Weekly" -messageCs "2. Týdně"
$frequencyChoice = Read-Host

switch ($frequencyChoice) {
    "1" { $frequency = "Daily" }
    "2" { $frequency = "Weekly" }
    default {
        Localized-Message -messageEn "Invalid choice." -messageCs "Neplatná volba."
        exit
    }
}

Localized-Message -messageEn "Enter the backup time (in 24h HH:mm format):" -messageCs "Zadejte čas zálohování (ve formátu 24h HH:mm):"
$time = Read-Host

# Creating a new backup script
$backupScriptPath = "$backupFolder\BackupScript.ps1"
$backupScriptContent = @"
# Definice proměnných
`$serverName = "$serverName"
`$instanceName = "$instanceName"
`$backupFolder = "$backupFolder"
`$credentialFile = "$credentialFile"
`$backupRetentionCount = $backupRetentionCount

# Function to clean up old backups by number
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
            Localized-Message -messageEn "Deleting old backups: `$(`$file.FullName)" -messageCs "Mazání starých záloh: `$(`$file.FullName)"
            Remove-Item `$file.FullName -Force
        }
    } else {
        Localized-Message -messageEn "No old backups to delete for `$databaseName. Retaining the last `$retentionCount backups." -messageCs "Žádné staré zálohy k odstranění pro `$databaseName. Uchovává se posledních `$retentionCount záloh."
    }
}

# Retrieve credentials
`$credentials = Import-Clixml -Path `$credentialFile
`$login = `$credentials.Login
`$securePassword = `$credentials.Password
`$password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR(`$securePassword))

# Database backup
`$databases = @($( $selectedDatabases | ForEach-Object { "'$_'" }) )
Backup-Databases -databases `$databases -serverName `$serverName -instanceName `$instanceName -backupFolder `$backupFolder -login `$login -password `$password

# Start cleaning old backups by number
foreach (`$db in `$databases) {
    Localized-Message -messageEn "Starting cleanup for database: `$db" -messageCs "Spouštím čištění pro databázi: `$db"
    Cleanup-OldBackups -backupFolder `$backupFolder -databaseName `$db -retentionCount `$backupRetentionCount
    Localized-Message -messageEn "Cleanup completed for database: `$db" -messageCs "Čištění dokončeno pro databázi: `$db"
}
"@


# Save script content to file
Set-Content -Path $backupScriptPath -Value $backupScriptContent


# Creating a task in Task Scheduler
$taskName = "MSSQL Backup Task"
Create-ScheduledTask -taskName $taskName -scriptPath $backupScriptPath -frequency $frequency -time $time

Update-ScheduledTask -taskName "MSSQL Backup Task"

Localized-Message -messageEn "Backup was successfully set up." -messageCs "Zálohování bylo úspěšně nastaveno."
