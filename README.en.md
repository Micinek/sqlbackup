# SQL Server Backup Automation Script
🌍 **Language:** [🇬🇧 English](README.en.md) | [🇨🇿 Čeština](README.cs.md)

## Overview
This PowerShell script automates backups for Microsoft SQL Server databases, including SQL Server Express, which does not include SQL Server Agent. It supports both Windows Authentication and SQL Server Authentication, performs automatic backup retention cleanup, can run optional fragmentation-based maintenance, and sends a summary email report after each run.

The script is designed to be run manually or through Windows Task Scheduler.

## Features
- Supports **Windows Authentication** and **SQL Server Authentication**
- Works with **SQL Server Express**
- Automatically installs the **SqlServer PowerShell module** if missing
- Detects **SQL Server edition** and disables backup compression on Express automatically
- Creates **full database backups**
- Cleans up old backups **before** each new backup to ensure free disk space
- Uses configurable **backup retention**
- Supports **fragmentation-based daily maintenance**
  - skip indexes under 10% fragmentation
  - reorganize indexes from 10% to 30%
  - rebuild indexes above 30%
- Updates statistics with `sp_updatestats`
- Sends a **summary email report** after each run
- Logs all operations to a local log file
- Supports long-running operations with no query timeout
- Works well with **Windows Task Scheduler**

## Requirements
- Windows operating system
- PowerShell 5.1 or higher
- Microsoft SQL Server accessible from the host running the script
- Permission to write to the backup folder
- Internet access on first run if the `SqlServer` PowerShell module is not already installed
- SMTP server access if email reporting is enabled

## Installation

1. **Download the script and save it on your drive**

   ```sh
   https://raw.githubusercontent.com/Micinek/sqlbackup/refs/heads/main/sqlbackup.ps1
   ```

2. **Edit the script configuration**
   Open `sqlbackup.ps1` and set:

   * SQL Server name and instance
   * backup folder
   * retention count
   * databases to back up
   * databases to maintain
   * authentication method
   * SMTP settings for email reporting

3. **Run the script**
   Open PowerShell as Administrator and execute:

   ```sh
   .\sqlbackup.ps1
   ```

## Usage

### Running manually

To run the script manually:

```sh
powershell -ExecutionPolicy Bypass -NoProfile -File .\sqlbackup.ps1
```

### Scheduled execution

The script is intended to work well with Windows Task Scheduler.

Recommended Task Scheduler action:

**Program/script**

```text
powershell.exe
```

**Arguments**

```text
-ExecutionPolicy Bypass -NoProfile -File "C:\Path\To\sqlbackup.ps1"
```

Recommended scheduler settings:

* Run whether user is logged on or not
* Run with highest privileges

## Configuration

### SQL Server connection

Set the SQL Server host and instance:

```powershell
$serverName = "localhost"
$instanceName = ""
```

Examples:

* default instance: `localhost`
* named instance: `localhost\SQLEXPRESS`

### Backup folder

Set the folder where `.bak` files and logs are stored:

```powershell
$backupFolder = "D:\DB_backup"
```

### Backup retention

Set how many backup files to keep per database:

```powershell
$backupRetentionCount = 3
```

The script cleans up old backups **before** creating a new one.
This means it temporarily keeps `retention - 1` old backups, then creates the new backup, so the final count matches the configured retention.

### Authentication

#### Windows Authentication

Leave both values empty:

```powershell
$sqlUsername = ""
$sqlPassword = ""
```

#### SQL Server Authentication

Fill both values:

```powershell
$sqlUsername = "sa"
$sqlPassword = "YourStrongPassword"
```

If only one is filled, the script stops with an error.

### Databases to back up

```powershell
$databasesToBackup = @(
    "master",
    "MyDatabase1",
    "MyDatabase2"
)
```

### Databases to maintain

```powershell
$databasesToMaintain = @(
    "MyDatabase1",
    "MyDatabase2"
)
```

### Email reporting

The script can send a summary email after each run:

```powershell
$emailEnabled = $true
$smtpServer = "smtp.example.com"
$smtpPort = 587
$smtpUseSsl = $true
$smtpUsername = "backup@example.com"
$smtpPassword = "YourSmtpPassword"
$emailFrom = "backup@example.com"
$emailTo = @(
    "admin@example.com"
)
$emailSubjectPrefix = "[SQL Backup Report]"
```

## Backup behavior

For each configured database, the script:

1. Removes old backup files while keeping `retention - 1`
2. Creates a new full backup
3. Verifies that the backup file was created
4. Records the result for the final report

If the SQL Server edition is not Express, the script uses backup compression.
If it detects SQL Server Express, it automatically disables compression to avoid backup failure.

## Maintenance behavior

For each configured maintenance database, the script:

* checks index fragmentation
* skips lightly fragmented indexes
* reorganizes moderately fragmented indexes
* rebuilds heavily fragmented indexes
* updates statistics

This is lighter and safer than rebuilding all indexes every day.

## Logging

The script writes a log file to the backup folder:

```text
backup_log.txt
```

The log contains:

* start and finish messages
* backup success/failure
* cleanup operations
* maintenance success/failure
* email sending errors

The log file is trimmed automatically to the last 100 lines.

## Email reporting

At the end of the run, the script sends a summary report similar to:

```text
[SQL Backup Report] OK

Server: localhost
Started: 2026-04-10 11:02:51
Finished: 2026-04-10 11:15:55
Duration: 00:13:04

=== BACKUP RESULTS ===
master backup OK - D:\DB_backup\master-20260410110251.bak
MyDatabase1 backup OK - D:\DB_backup\MyDatabase1-20260410110255.bak
MyDatabase2 backup FAILED - Timeout expired

=== MAINTENANCE RESULTS ===
MyDatabase1 maintenance OK
MyDatabase2 maintenance FAILED - Some SQL error
```
