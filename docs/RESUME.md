# Riprendere il lavoro

Aggiornamento: 2026-11-01. Progetto: Spirax-M1/WoW-3.3.5a-Italiano.

Branch di lavoro: `maintenance/installer-validation`. La v1.0.1 è preparata per la pubblicazione su main e come release. Verificare lo stato della PR #1 e della release prima di proseguire.

L'utente vuole sistemare i progetti GitHub uno per uno e mantenere il lavoro accessibile da altri PC. Il progetto ML è già nella PR #1 di Spirax-M1/algorithmic-trading-ml e attende i CSV su un altro computer. Questa è la successiva revisione, dedicata agli installer della localizzazione WoW.

## Ripartenza

```sh
git clone --branch maintenance/installer-validation https://github.com/Spirax-M1/WoW-3.3.5a-Italiano.git
cd WoW-3.3.5a-Italiano
python -m unittest discover -s tests -v
```

Leggere README.md, docs/audit.md e docs/provenance.md. Controllare lo stato corrente della PR e della CI. Non eseguire installer sul client reale per verificare una modifica al codice: usare prima le fixture dei test.

## Stato

Controlli di percorso, checksum, backup e offset migliorati; documentazione riscritta; manifest storici spostati sotto docs/releases/v1.0.0. Payload e byte sostitutivi invariati. Compatibilità basata su PE x86, versione 3.3.5.12340 e contesti di tutte le sei regioni; nessun vincolo su provenienza o hash globale. Richiesti i tre archivi locale enUS elencati nel manifest. Ripristino chirurgico dell'eseguibile; altre patch conservate. Helper Windows condiviso: client-compatibility.ps1. Test locali: 14 superati e due test Windows da eseguire in CI. PowerShell 7 locale usato per parsing e confronto Python/PowerShell su quattro eseguibili reali, senza modificarli. La CI esegue il test Windows e il parsing degli script.

## Prossimi passi

1. Verificare tutti i controlli CI sul commit più recente.
2. Estendere collaudo Windows e casi negativi, verificare conflitti tra MPQ HD e traduzione.
3. Progettare rollback e recupero dopo interruzione, senza sovrascrivere la baseline originale.
4. Eseguire collaudo controllato su copie del client supportato, con installazione, refresh e ripristino.
5. Completare provenienza/licenze e preparare manifest di una nuova release solo dopo il collaudo.

L’utente ha autorizzato merge e pubblicazione della v1.0.1. La CI Windows e Linux è passata sul codice precedente alla preparazione della release; il workflow di pubblicazione riesegue i test prima di creare ZIP e checksum. Non dichiarare compatibilità di varianti non collaudate sulla base dei soli test artificiali.
