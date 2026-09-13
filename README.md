# WoW 3.3.5a Italiano - v1.0.0

Localizzazione italiana all-in-one per World of Warcraft:
Wrath of the Lich King 3.3.5a build 12340 enUS.

## Compatibilita

E supportato esclusivamente:

- World of Warcraft WotLK 3.3.5a
- build 12340
- client enUS

L'installer verifica Wow.exe prima di modificarlo.

Se l'eseguibile non corrisponde alla versione originale supportata
o alla versione gia patchata, l'installazione viene interrotta.

## Windows

Estrarre completamente lo ZIP.

Installazione:

    install.cmd

Refresh / riparazione:

    refresh.cmd

Disinstallazione:

    uninstall.cmd

L'installer prova a rilevare automaticamente la cartella del client.
Se non riesce, chiede il percorso che contiene Wow.exe.

## Linux / Bazzite

Richiede Python 3 e Bash.

Installazione:

    ./install-linux.sh

Con percorso esplicito:

    ./install-linux.sh "$HOME/Games/World of Warcraft 3.3.5a"

Refresh:

    ./refresh-linux.sh

Disinstallazione:

    ./uninstall-linux.sh

Se necessario:

    chmod +x install-linux.sh refresh-linux.sh uninstall-linux.sh linux/wow_ita_linux.py

## Backup

Alla prima installazione viene creata:

    WoW-ITA-Backup/v1.0.0-baseline/

La baseline conserva i file preesistenti che vengono sovrascritti.

Se l'installer parte da un Wow.exe originale compatibile,
ne salva inoltre una copia verificata in:

    WoW-ITA-Backup/v1.0.0-baseline/Wow.exe.original

La baseline iniziale non viene sovrascritta dai successivi refresh.

## Patch di Wow.exe

Il pacchetto NON distribuisce un Wow.exe completo.

L'installer:

1. verifica SHA-256;
2. verifica i byte originali negli offset previsti;
3. crea il backup quando possibile;
4. modifica solamente i byte necessari;
5. verifica l'SHA-256 finale.

L'uninstaller puo anche applicare la patch inversa verificata.

## Contenuto

- Data/patch-4.MPQ
- Data/enUS/patch-enUS-4.MPQ
- QuestTradutor
- WoWItaliano
- installer Windows
- installer Linux/Bazzite
- manifest
- checksum

## Integrita

SHA256SUMS.txt contiene gli hash SHA-256 dei file della release.

Il file:

    WoW-ITA-v1.0.0.zip.sha256

contiene invece l'hash dello ZIP pubblicabile.

## Supporta il progetto

Se questa localizzazione ti e stata utile e vuoi supportare lo sviluppo e gli aggiornamenti futuri, puoi lasciare una donazione tramite PayPal:

**[Dona con PayPal](https://www.paypal.com/qrcodes/managed/437d6dd2-95e9-4bc9-9a92-8fb239820402?utm_source=consapp_download)**

Le donazioni sono completamente facoltative e non sono necessarie per utilizzare il progetto.

## Nota

Questa release e destinata esclusivamente al client 3.3.5a
build 12340 enUS.

La localizzazione non e un prodotto ufficiale Blizzard Entertainment.
World of Warcraft e i relativi marchi appartengono ai rispettivi proprietari.
