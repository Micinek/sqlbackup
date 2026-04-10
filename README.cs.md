# SQL Server Backup Automation Script
🌍 **Jazyk:** [🇬🇧 English](README.en.md) | [🇨🇿 Čeština](README.cs.md)

## Přehled
Tento PowerShell skript automatizuje zálohování databází Microsoft SQL Serveru, včetně SQL Server Express, který neobsahuje SQL Server Agent. Podporuje jak Windows Authentication, tak SQL Server Authentication, provádí automatické mazání starých záloh podle retenční politiky, umožňuje volitelnou údržbu databází na základě fragmentace a po každém běhu odesílá souhrnný e-mail.

Skript je navržen pro manuální spuštění nebo plánované spouštění pomocí Windows Task Scheduler.

## Funkce
- Podpora **Windows Authentication** i **SQL Server Authentication**
- Funguje i se **SQL Server Express**
- Automaticky nainstaluje modul **SqlServer**, pokud chybí
- Detekuje edici SQL Serveru a automaticky vypne kompresi záloh u Express Edition
- Vytváří **plné zálohy databází**
- Maže staré zálohy **před vytvořením nové**, aby bylo vždy dost místa
- Konfigurovatelná **retenční politika záloh**
- Podpora **denní údržby na základě fragmentace**
  - pod 10 % → nic
  - 10–30 % → reorganize
  - nad 30 % → rebuild
- Aktualizuje statistiky pomocí `sp_updatestats`
- Odesílá **souhrnný e-mail po dokončení běhu**
- Loguje všechny operace do souboru
- Podporuje dlouhotrvající operace (bez timeoutu)
- Vhodné pro použití s **Windows Task Scheduler**

## Požadavky
- Windows operační systém
- PowerShell 5.1 nebo vyšší
- Dostupný Microsoft SQL Server
- Oprávnění k zápisu do cílové složky pro zálohy
- Přístup k internetu při prvním spuštění (pro instalaci modulu `SqlServer`)
- SMTP server (pokud je zapnutý e-mailový report)

## Instalace

1. **Stáhněte skript a uložte ho na disk**

   ```sh
   https://raw.githubusercontent.com/Micinek/sqlbackup/refs/heads/main/sqlbackup.ps1
   ```

2. **Upravte konfiguraci**
   Otevřete `sqlbackup.ps1` a nastavte:

   * SQL Server (název a instance)
   * složku pro zálohy
   * retenční počet záloh
   * databáze k zálohování
   * databáze pro údržbu
   * typ autentizace
   * SMTP nastavení pro e-mail

3. **Spusťte skript**
   Otevřete PowerShell jako administrátor a spusťte:

   ```sh
   .\sqlbackup.ps1
   ```

## Použití

### Ruční spuštění

```sh
powershell -ExecutionPolicy Bypass -NoProfile -File .\sqlbackup.ps1
```

### Plánované spouštění

Doporučené nastavení v Task Scheduleru:

**Program/script**

```text
powershell.exe
```

**Argumenty**

```text
-ExecutionPolicy Bypass -NoProfile -File "C:\Cesta\k\sqlbackup.ps1"
```

Doporučení:

* Spouštět i bez přihlášeného uživatele
* Spouštět s administrátorskými právy

## Konfigurace

### Připojení k SQL Serveru

```powershell
$serverName = "localhost"
$instanceName = ""
```

Příklady:

* default instance: `localhost`
* pojmenovaná instance: `localhost\SQLEXPRESS`

### Složka pro zálohy

```powershell
$backupFolder = "D:\DB_backup"
```

### Retence záloh

```powershell
$backupRetentionCount = 3
```

Skript maže staré zálohy **před vytvořením nové**.
To znamená, že si dočasně ponechá `retention - 1` záloh a po vytvoření nové bude celkový počet odpovídat nastavení.

### Autentizace

#### Windows Authentication

```powershell
$sqlUsername = ""
$sqlPassword = ""
```

#### SQL Server Authentication

```powershell
$sqlUsername = "sa"
$sqlPassword = "Heslo"
```

Pokud je vyplněná jen jedna hodnota, skript skončí chybou.

### Databáze k zálohování

```powershell
$databasesToBackup = @(
    "master",
    "MojeDB1",
    "MojeDB2"
)
```

### Databáze pro údržbu

```powershell
$databasesToMaintain = @(
    "MojeDB1",
    "MojeDB2"
)
```

### E-mailový report

```powershell
$emailEnabled = $true
$smtpServer = "smtp.example.com"
$smtpPort = 587
$smtpUseSsl = $true
$smtpUsername = "backup@example.com"
$smtpPassword = "Heslo"
$emailFrom = "backup@example.com"
$emailTo = @(
    "admin@example.com"
)
$emailSubjectPrefix = "[SQL Backup Report]"
```

## Chování zálohování

Pro každou databázi skript:

1. Smaže staré zálohy (ponechá `retention - 1`)
2. Vytvoří novou plnou zálohu
3. Ověří, že soubor existuje
4. Zapíše výsledek do reportu

U ne-Express edic používá kompresi, u Express ji automaticky vypne.

## Chování údržby

Pro každou databázi:

* zkontroluje fragmentaci indexů
* malé fragmentace ignoruje
* střední reorganizuje
* velké rebuilduje
* aktualizuje statistiky

Je to výrazně šetrnější než rebuild všech indexů.

## Logování

Log se ukládá do:

```text
backup_log.txt
```

Obsahuje:

* průběh skriptu
* výsledky záloh
* mazání souborů
* výsledky údržby
* chyby e-mailu

Log se automaticky zkracuje na posledních 100 řádků.

## E-mailový report

Na konci běhu přijde souhrn:

```text
[SQL Backup Report] OK

Server: localhost
Started: 2026-04-10 11:02:51
Finished: 2026-04-10 11:15:55
Duration: 00:13:04

=== BACKUP RESULTS ===
master backup OK - D:\DB_backup\master-20260410110251.bak
MojeDB1 backup OK - D:\DB_backup\MojeDB1-20260410110255.bak
MojeDB2 backup FAILED - Timeout expired

=== MAINTENANCE RESULTS ===
MojeDB1 maintenance OK
MojeDB2 maintenance FAILED - SQL chyba
```
