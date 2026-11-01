# Riprendere il lavoro

Aggiornamento: 2026-11-01. Progetto: Spirax-M1/WoW-3.3.5a-Italiano.

Branch di lavoro: `maintenance/installer-validation`. Usare la PR in bozza collegata al branch; non main.

L'utente vuole sistemare i progetti GitHub uno per uno e mantenere il lavoro accessibile da altri PC. Il progetto ML è già nella PR #1 di Spirax-M1/algorithmic-trading-ml e attende i CSV su un altro computer. Questa è la successiva revisione, dedicata agli installer della localizzazione WoW.

## Ripartenza

```sh
git clone --branch maintenance/installer-validation https://github.com/Spirax-M1/WoW-3.3.5a-Italiano.git
cd WoW-3.3.5a-Italiano
python -m unittest discover -s tests -v
```

Leggere README.md, docs/audit.md e docs/provenance.md. Controllare lo stato corrente della PR e della CI. Non eseguire installer sul client reale per verificare una modifica al codice: usare prima le fixture dei test.

## Stato

Controlli di percorso, checksum, backup e offset migliorati; documentazione riscritta; manifest storici spostati sotto docs/releases/v1.0.0. Payload e patch binarie invariati. I test locali hanno superato 10 casi; il caso Windows è saltato localmente perché PowerShell non è disponibile. La CI esegue il test Windows e il parsing degli script.

## Prossimi passi

1. Verificare tutti i controlli CI sul commit più recente.
2. Completare la parità Windows/Linux elencata nell'audit, aggiungendo test negativi Windows.
3. Progettare rollback e recupero dopo interruzione, senza sovrascrivere la baseline originale.
4. Eseguire collaudo controllato su copie del client supportato, con installazione, refresh e ripristino.
5. Completare provenienza/licenze e preparare manifest di una nuova release solo dopo il collaudo.

Tenere la PR in bozza, aggiornare questo documento e caricare i progressi sullo stesso branch. Non pubblicare una nuova release né dichiarare compatibilità reale sulla base dei soli test artificiali.
