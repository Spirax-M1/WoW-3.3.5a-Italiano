# Audit degli installer

La revisione riguarda gli installer pubblicati, non certifica la traduzione o i diritti sui componenti inclusi. Nessun client reale è stato modificato durante il lavoro.

## Difetti affrontati

- Il percorso esplicito non valido poteva far selezionare un altro client: ora viene rifiutato.
- Linux verificava un numero fisso di checksum ma copiava tutti i file: ora l'elenco verificato deve coincidere con il payload. Windows controlla anche file extra e duplicati.
- La disinstallazione scopriva backup mancanti dopo aver iniziato a modificare i file: la disponibilità dei backup è controllata prima del ripristino.
- Un eseguibile sconosciuto poteva portare a una disinstallazione parziale: ora viene rifiutato prima di ripristinare il payload.
- Le patch non rifiutavano esplicitamente offset negativi: aggiunti controlli sui limiti.
- I wrapper CMD non propagavano esplicitamente il codice finale: ora lo restituiscono.
- I percorsi provenienti dagli elenchi richiedevano controlli: aggiunte restrizioni su traversal e link nei percorsi verificati.
- Nuove baseline registrano gli hash dei backup del payload; la disinstallazione verifica gli hash quando presenti. Linux accetta anche BOM UTF-8 e separatori Windows nelle baseline.

Windows e Linux pre-calcolano la patch e verifica il risultato prima di copiare il payload. Le prove coprono ripetizione dell'installazione, ripristino, patch inversa senza backup dell'eseguibile, file extra, backup mancanti/corrotti, istruzioni incompatibili e percorsi non validi.

## Lavoro ancora necessario

- Rendere installazione e ripristino transazionali, con journal recuperabile dopo crash e gestione di spazio esaurito/permessi. I controlli preliminari non risolvono gli errori di I/O durante la copia.
- Mantenere la parità Windows/Linux: entrambi pre-calcolano patch diretta/inversa e validano le baseline esistenti prima delle copie.
- Gestire concorrenza e cambiamenti dei file tra verifica e scrittura. I controlli sui link non costituiscono una protezione contro un processo ostile concorrente.
- Gestire i conflitti con modifiche successive ai file del payload: il loro ripristino torna alla baseline iniziale. Le modifiche estranee alle sei regioni di Wow.exe sono invece conservate.
- Rigenerare manifest/checksum di distribuzione dopo il collaudo; quelli storici sono ora sotto docs/releases/v1.0.0.
- Verificare compatibilità del client reale, copertura linguistica, font, caratteri speciali, addon e disinstallazione su Windows/Linux/Bazzite.
- Documentare autori originali e permessi dei componenti prima di assegnare una licenza complessiva.

Il payload e i byte sostitutivi della patch non sono cambiati. Il manifest aggiunge otto byte di contesto prima e dopo ogni regione e i requisiti dei file enUS. Gli hash globali restano riferimenti storici, senza bloccare varianti della stessa build. Il riconoscimento verifica PE x86, sezioni eseguibili, versione fissa 3.3.5.12340 nella sezione risorse, contesti e byte old/new di tutte le regioni. Non cerca offset alternativi alla cieca.

Prove locali in sola lettura su quattro eseguibili/backup standard e HD: riconoscimento riuscito e risultati identici tra Python e PowerShell. Questi file non vengono distribuiti né inclusi nei test CI. I test automatici usano PE artificiali e coprono hash diversi, cambiamenti successivi all'installazione, contesti e build errati. Questo non sostituisce il collaudo visivo di gioco o di client di terzi. La copia locale usata per i test contiene gli installer e i metadati, non tutto il payload binario: GitHub conserva il payload originale attraverso un aggiornamento basato sull'albero esistente.
