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

Linux pre-calcola la patch e verifica il risultato prima di copiare il payload. Le prove coprono ripetizione dell'installazione, ripristino, patch inversa senza backup dell'eseguibile, file extra, backup mancanti/corrotti, hash sconosciuti e percorsi non validi.

## Lavoro ancora necessario

- Rendere installazione e ripristino transazionali, con journal recuperabile dopo crash e gestione di spazio esaurito/permessi. I controlli preliminari non risolvono gli errori di I/O durante la copia.
- Uniformare ulteriormente le verifiche Windows/Linux: Windows non pre-calcola ancora la patch inversa senza backup prima di ripristinare il payload, né valida completamente l'insieme dei file di una baseline esistente al refresh.
- Gestire concorrenza e cambiamenti dei file tra verifica e scrittura. I controlli sui link non costituiscono una protezione contro un processo ostile concorrente.
- Definire un comportamento per modifiche dell'utente successive all'installazione: il ripristino attuale torna alla baseline iniziale.
- Rigenerare manifest/checksum di distribuzione dopo il collaudo; quelli storici sono ora sotto docs/releases/v1.0.0.
- Verificare compatibilità del client reale, copertura linguistica, font, caratteri speciali, addon e disinstallazione su Windows/Linux/Bazzite.
- Documentare autori originali e permessi dei componenti prima di assegnare una licenza complessiva.

Il payload e il manifest binario della patch non sono stati cambiati. La copia locale usata per i test contiene gli installer e i metadati, non tutto il payload binario: GitHub conserva il payload originale attraverso un aggiornamento basato sull'albero esistente.
