La v1.0.1 corregge l’installer della patch italiana per **WoW 3.3.5 / 3.3.5a WotLK, build 12340**.

Scarica **WoW-ITA-v1.0.1.zip**, estrailo completamente e avvia `install.cmd` su Windows oppure `./install-linux.sh` su Linux. Il file `.sha256` permette di verificare il download.

- Accetta eseguibili standard e modificati/HD compatibili senza imporre un hash globale o una provenienza del client.
- Controlla build, istruzioni necessarie alla mod e i tre archivi di lingua enUS richiesti.
- Preserva le altre patch dell’eseguibile durante la disinstallazione.
- Migliora controlli di percorsi, checksum e backup.

La traduzione è invariata rispetto alla v1.0.0. I backup esistenti restano compatibili. Il pacchetto non contiene il gioco o un Wow.exe completo.

Test automatici su Windows e Linux; prove su eseguibili standard e HD. Il manutentore conferma l’uso della localizzazione sul proprio client HD. Possibili conflitti tra contenuti di mod HD richiedono verifica nel gioco. Conserva una copia del client: installazione e ripristino non sono ancora transazionali in caso di interruzione o errore di I/O.
