# WoW 3.3.5a Italiano

Localizzazione italiana per World of Warcraft: Wrath of the Lich King **3.3.5a, build 12340, client enUS**, con installer Windows e Linux.

Manutenzione del progetto: **Salvatore ([Spirax-M1](https://github.com/Spirax-M1))**.

**Questo branch è una bozza di manutenzione.** Le modifiche agli installer sono verificate con file artificiali; il pacchetto non è una nuova release collaudata nel gioco. I file di localizzazione rimangono invariati.

## Cosa contiene

- Patch MPQ e addon per la localizzazione dell'interfaccia e dei testi.
- Verifica di build, struttura PE e istruzioni interessate prima della patch.
- Backup dei file preesistenti, refresh e disinstallazione.
- Patch dell'eseguibile per offset, senza distribuire un Wow.exe completo.

La provenienza del client e l'hash completo di `Wow.exe` non sono criteri di esclusione. Sono accettate varianti standard, ChromieCraft e HD se conservano la build 12340, il formato PE x86 e le istruzioni necessarie alla mod. Patch già applicate o applicate solo in parte vengono riconosciute; byte incompatibili nelle regioni interessate fanno interrompere l'operazione prima delle copie.

Il payload attuale richiede i file non vuoti `Data/enUS/locale-enUS.MPQ`, `Data/enUS/expansion-locale-enUS.MPQ` e `Data/enUS/lichking-locale-enUS.MPQ`. Un client con soli archivi di un'altra lingua richiede prima una conversione del payload; creare una cartella enUS vuota non basta. Il controllo di presenza non certifica l'integrità interna di tutti gli MPQ. Gli archivi HD aggiuntivi non vengono rimossi; conflitti tra i loro contenuti e la traduzione richiedono collaudo nel gioco.

I requisiti sono in `metadata/patch_manifest.json`, senza percorsi personali o dipendenze dalle installazioni di questo PC. La copertura e la qualità delle traduzioni richiedono una verifica nel gioco: il numero di file non è una misura della completezza linguistica.

## Uso

Chiudi il gioco e conserva una copia indipendente della cartella del client. Estrai completamente il pacchetto. Non eseguire questa bozza direttamente sulla tua unica installazione.

Su Windows, esegui `install.cmd`. Per indicare il client:

```bat
install.cmd -GamePath "D:\Games\WoW 3.3.5a"
refresh.cmd -GamePath "D:\Games\WoW 3.3.5a"
uninstall.cmd -GamePath "D:\Games\WoW 3.3.5a"
```

Su Linux servono Python 3.10+ e Bash:

```sh
./install-linux.sh "$HOME/Games/World of Warcraft 3.3.5a"
./refresh-linux.sh "$HOME/Games/World of Warcraft 3.3.5a"
./uninstall-linux.sh "$HOME/Games/World of Warcraft 3.3.5a"
```

Se specifichi un percorso errato, l'operazione si interrompe. Se non lo specifichi, l'installer cerca nelle cartelle previste e può chiedere il percorso.

## Backup e limiti

La baseline si trova in `WoW-ITA-Backup/v1.0.0-baseline/` dentro il client. Conserva i file presenti alla prima installazione e, quando disponibile, l'eseguibile originale. Il refresh riutilizza quella baseline. I nuovi backup del payload includono hash; le baseline precedenti non contengono questa verifica e restano meno verificabili.

Per i file del payload, la disinstallazione torna alla baseline iniziale. Per `Wow.exe`, ripristina soltanto le sei regioni della patch italiana, conservando le altre modifiche, anche successive all'installazione. Le regioni già patchate prima dell'installazione vengono anch'esse riportate ai byte precedenti alla patch italiana. Il backup completo dell'eseguibile resta un archivio e non viene copiato sopra l'eseguibile corrente. Non eliminare la baseline prima di aver verificato il ripristino.

I controlli preliminari evitano diverse modifiche parziali, ma **l'operazione non è ancora transazionale**: un'interruzione, spazio esaurito o un errore di copia può lasciare file già modificati. Non avviare due installer contemporaneamente. Consulta [audit e limiti](docs/audit.md) prima di valutare una nuova release.

## Integrità e sviluppo

`metadata/SHA256SUMS` descrive il payload. Gli hash rilevano alterazioni rispetto all'elenco, ma non costituiscono una firma dell'autore. I manifest della vecchia release sono conservati in `docs/releases/v1.0.0/` e non descrivono questa bozza.

```sh
python -m unittest discover -s tests -v
```

I test creano client artificiali in cartelle temporanee. La CI verifica Linux e Windows, compresi parsing PowerShell e un ciclo Windows di installazione/refresh/disinstallazione. Non equivale a un test dentro WoW o su Bazzite/Wine.

- [Riprendere il lavoro da un altro PC](docs/RESUME.md)
- [Audit tecnico](docs/audit.md)
- [Provenienza dei componenti](docs/provenance.md)

## Contatti

[smanciagli1@outlook.com](mailto:smanciagli1@outlook.com)

Se desideri sostenere la manutenzione: [donazione facoltativa](https://www.paypal.com/qrcodes/managed/437d6dd2-95e9-4bc9-9a92-8fb239820402). L'utilizzo non richiede donazioni.

Progetto non ufficiale. World of Warcraft e i relativi marchi appartengono ai rispettivi proprietari.
