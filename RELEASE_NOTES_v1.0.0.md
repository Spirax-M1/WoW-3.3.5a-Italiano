# WoW 3.3.5a Italiano v1.0.0

Prima release pubblica della localizzazione italiana all-in-one per **World of Warcraft: Wrath of the Lich King 3.3.5a build 12340 enUS**.

## Incluso

- login / Glue in italiano;
- interfaccia di gioco in italiano;
- quest, obiettivi, tracker e mappa localizzati;
- `patch-4.MPQ`;
- `patch-enUS-4.MPQ`;
- addon `QuestTradutor`;
- addon `WoWItaliano`;
- installer, refresh e uninstall per Windows;
- supporto Linux / Bazzite;
- backup automatico e restore;
- verifica SHA-256 del client e del payload.

## Sicurezza della patch

Il pacchetto **non distribuisce un Wow.exe completo**.

L'installer verifica il client supportato e applica localmente soltanto i 6 blocchi binari necessari. Se `Wow.exe` non corrisponde alla build supportata, viene rifiutato senza modificarlo.

L'installazione e idempotente e conserva una baseline per il ripristino.

## Compatibilita

Solo:

- WotLK 3.3.5a
- build 12340
- locale enUS

## Download

Scaricare **WoW-ITA-v1.0.0.zip**, estrarlo completamente e avviare:

- Windows: `install.cmd`
- Linux/Bazzite: `./install-linux.sh`

## SHA-256

`WoW-ITA-v1.0.0.zip`

`9f39eada53918d13c29463a7df9e85f428acea60b5a0db3e1496ffc6ae0c9481`

Il checksum e disponibile anche come asset separato `WoW-ITA-v1.0.0.zip.sha256`.

## Nota

Progetto non ufficiale. World of Warcraft e i relativi marchi appartengono ai rispettivi proprietari.
