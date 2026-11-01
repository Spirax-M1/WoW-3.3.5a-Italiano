# Changelog

## 1.0.1 — 2026-11-01

- Riconoscimento dei client 3.3.5a basato su build e istruzioni richieste dalla mod, anziché su due soli hash globali. Accetta varianti standard e HD compatibili, indipendentemente dalla provenienza.
- Verifica esplicita dei tre archivi di lingua enUS richiesti.
- Ripristino delle sole sei regioni della patch italiana nell’eseguibile, conservando altre modifiche.
- Verifiche preventive di percorsi, checksum e backup; correzione dei codici di uscita CMD.
- Test Windows/Linux e documentazione aggiornata.
- Pacchetto ZIP e checksum prodotti automaticamente dopo i test.

Il payload della traduzione e i byte sostitutivi sono invariati. Il formato della baseline e il percorso `v1.0.0-baseline` restano compatibili con i backup esistenti.
