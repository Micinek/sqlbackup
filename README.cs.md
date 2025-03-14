# Automatizace zálohování SQL Serveru
🌍 **Jazyk:** [🇬🇧 English](README.en.md) | [🇨🇿 Čeština](README.cs.md)

## Přehled
Tento PowerShell skript automatizuje proces zálohování databází Microsoft SQL Server.  Vačetně SQL Server Express, které chybí SQL Agent pro automatické zálohy. Podporuje jak Windows autentizaci, tak autentizaci SQL Serveru a umožňuje plánování záloh pomocí Plánovače úloh ve Windows.

## Funkce
- Detekuje jazyk systému (angličtina/čeština) a poskytuje lokalizované zprávy.
- Umožňuje uživateli zadat název serveru SQL Server a instanci.
- Konfigurovatelné umístění pro ukládání záloh.
- Podporuje politiku uchovávání záloh – umožňuje nastavit počet záloh, které mají být zachovány.
- Používá zabezpečené uložení přihlašovacích údajů.
- Automatizuje plánované zálohy pomocí Plánovače úloh ve Windows.
- Automaticky odstraňuje staré zálohy.

## Požadavky
- Operační systém Windows.
- PowerShell 5.1 nebo novější.
- Nainstalovaný SQL Server Management Studio (SSMS) nebo `Invoke-Sqlcmd`.
- Plánovač úloh Windows pro automatizované zálohování.

## Spouštění
1. **Script můžete spustit přímo z githubu pomocí powershellu**
   ```sh
   irm https://raw.githubusercontent.com/Micinek/sqlbackup/refs/heads/main/sqlbackup.ps1 | iex
   ```

## Instalace
1. **Stáhněte nebo naklonujte repozitář**
   ```sh
   git clone https://github.com/Micinek/sqlbackup.git
   ```
2. **Spusťte PowerShell skript**
   Otevřete PowerShell jako správce a spusťte:
   ```sh
   .\sqlbackup.ps1
   ```
3. **Postupujte podle pokynů**
   - Zadejte podrobnosti o SQL Serveru (název serveru, instance, metoda ověřování).
   - Zvolte složku pro ukládání záloh.
   - Definujte politiku uchovávání záloh.
   - Nastavte frekvenci a čas zálohování.

## Použití
### Ruční spuštění
Pro spuštění zálohy ručně použijte příkaz:
```sh
powershell -ExecutionPolicy Bypass -File .\sqlbackup.ps1
```

### Plánované zálohování
- Skript vytvoří naplánovanou úlohu pomocí Plánovače úloh.
- Zálohování se spustí automaticky na základě zvolené frekvence (denně/týdně).
- Vygenerovaný soubor `BackupScript.ps1` provede skutečnou operaci zálohování.

## Konfigurace
Skript generuje konfigurační soubor a naplánovanou úlohu pro zálohování. Pokud je potřeba, můžete upravit parametry v `BackupScript.ps1`.

## Bezpečnostní aspekty
- Přihlašovací údaje SQL Serveru jsou bezpečně uloženy pomocí `Export-Clixml`.
- Přístup k naplánované úloze mají pouze uživatelé s odpovídajícími oprávněními.

## Řešení problémů
- Ujistěte se, že PowerShell je spuštěn jako správce.
- Ověřte správnost nastavení ověřování SQL Serveru.
- Zkontrolujte Plánovač úloh Windows pro případné chyby při spuštění.
- Ujistěte se, že zadaná složka pro zálohování existuje.

## Licence
MIT License. Podrobnosti naleznete v souboru `LICENSE`.

