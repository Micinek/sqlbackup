# SQL Server Backup Automation Script
🌍 **Language:** [🇬🇧 English](README.en.md) | [🇨🇿 Čeština](README.cs.md)

## Overview
This PowerShell script automates the backup process for Microsoft SQL Server databases. Including SQL Server Express, which lacks SQL Agent for automated backups. It supports both Windows and SQL Server authentication and allows scheduling backups using Windows Task Scheduler.

## Features
- Detects the system language (English/Czech) and provides localized messages.
- Allows the user to specify SQL Server name and instance.
- Configurable backup storage location.
- Supports retention policy to keep only a specified number of backups.
- Uses secure credential storage for authentication.
- Automates scheduled backups via Windows Task Scheduler.
- Cleans up old backups automatically.

## Requirements
- Windows operating system.
- PowerShell 5.1 or higher.
- SQL Server Management Studio (SSMS) or `Invoke-Sqlcmd` installed.
- Windows Task Scheduler for scheduled backups.

## Installation
1. **Clone or Download**
   ```sh
   git clone https://github.com/Micinek/sqlbackup.git
   ```
2. **Run PowerShell Script**
   Open PowerShell as Administrator and execute:
   ```sh
   .\sqlbackup.ps1
   ```
3. **Follow Prompts**
   - Enter SQL Server details (server name, instance, authentication method).
   - Specify backup folder.
   - Define backup retention policy.
   - Choose backup frequency and time.

## Usage
### Running Manually
To run the backup manually:
```sh
powershell -ExecutionPolicy Bypass -File .\sqlbackup.ps1
```

### Scheduled Backups
- The script sets up a scheduled task using Task Scheduler.
- The backup process runs automatically based on the selected frequency (Daily/Weekly).
- The generated `BackupScript.ps1` handles the actual backup execution.

## Configuration
The script generates a backup configuration file and scheduled task. Modify parameters in `BackupScript.ps1` if necessary.

## Security Considerations
- SQL credentials are stored securely using `Export-Clixml`.
- Only users with the necessary permissions can access the scheduled task.

## Troubleshooting
- Ensure PowerShell is run as Administrator.
- Verify that SQL Server authentication settings are correct.
- Check Windows Task Scheduler for any execution errors.
- Confirm that the specified backup folder exists.

## License
MIT License. See `LICENSE` file for details.
