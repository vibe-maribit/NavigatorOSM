# NavigatoreOSM per iPad Mini 1 (MD528TY/A - iOS 9.3.5)

Applicazione **100% NATIVA iOS** (Objective-C + MapKit + UIKit) per trasformare un vecchio iPad Mini 1ª Generazione (architettura 32-bit `armv7`, 512 MB RAM, iOS 9.3.5) in un moderno navigatore GPS per auto in stile **Google Maps & Waze** con **OpenStreetMap**, **visuale prospettica 3D/2D commutabile**, **itinerari alternativi**, **traffico in tempo reale**, **ricerca rapida POI** e **guida vocale italiana offline**.

Zero WebKit, zero browser: l'app consuma meno di 25 MB di RAM e sfrutta la GPU Apple per un rendering a **60 FPS fluidi**.

---

## Indice della Documentazione Completa (`docs/`)

Per consultare ogni dettaglio del progetto, leggi le guide dedicate nella cartella [`docs/`](docs/):

| Documento | Argomento Trattato |
| :--- | :--- |
| 📖 [**`01_ARCHITETTURA_E_CODICE.md`**](docs/01_ARCHITETTURA_E_CODICE.md) | Architettura software, spiegazione approfondita di tutte le classi Objective-C, MapKit, OSRM, AVSpeech, socket UDP per tethering GPS. |
| 📲 [**`02_GUIDA_INSTALLAZIONE_E_JAILBREAK.md`**](docs/02_GUIDA_INSTALLAZIONE_E_JAILBREAK.md) | Guida passo-passo per il Jailbreak di iOS 9.3.5, installazione di AppSync Unified e flash via USB da Linux con `./install-usb.sh`. |
| 🚗 [**`03_MANUALE_USO_IN_AUTO.md`**](docs/03_MANUALE_USO_IN_AUTO.md) | Manuale completo per l'auto: alimentazione 2.1A, hotspot iPhone vs Android, visuale 3D/2D, itinerari, traffico, allerta limiti di velocità e POI rapidi. |
| 🛠️ [**`04_GUIDA_BUILD_E_SVILUPPO.md`**](docs/04_GUIDA_BUILD_E_SVILUPPO.md) | Come ricompilare il codice su Linux con il container Docker Theos, aggiungere file al `Makefile` e gestire la cronologia Git. |

---

## Installazione Immediata su iPad via Cavo USB (Linux)

Sul tuo PC Linux è tutto già configurato e pronto.

1. Collega l'iPad Mini 1 con il cavo USB Lightning al PC Linux.
2. Se l'iPad chiede *"Vuoi autorizzare questo computer?"*, tocca **Autorizza**.
3. Esegui dal terminale:
   ```bash
   cd /home/nicola/Devel/retrofit/iOS/NavigatoreOSM
   ./install-usb.sh
   ```

Lo script installerà il pacchetto `NavigatoreOSM.ipa` sul tablet in circa 5 secondi!

---

## File Principali del Progetto

- **`NavigatoreOSM.ipa`**: Il file di installazione finale pronto per iOS 9.3.5 (32-bit `armv7`).
- **`install-usb.sh`**: Script per installare l'app sull'iPad via cavo USB con un solo comando.
- **`package-ipa.sh`**: Script che avvia il container Docker Theos e ricompila l'app generando l'IPA.
- **`android-gps-forwarder.py`**: Script per inviare le coordinate GPS via Wi-Fi/UDP da smartphone Android o computer verso l'iPad Mini solo Wi-Fi (porta 8888).
- **`NavigatoreOSM/`**: Tutti i codici sorgente nativi Objective-C, controller, viste e asset.
- **`docs/`**: Cartella con la documentazione tecnica e le guide d'uso complete.

---

## Panoramica delle Funzionalità

- **Visuale 3D Prospettica / 2D Pianta Commutabile**: Pulsante `3D / 2D` per passare dalla visuale a volo d'uccello ortogonale (2D) alla prospettiva cockpit inclinata a 56° (3D) che segue la marcia con zoom dinamico alla velocità.
- **Design Moderno Stile Waze / Google Maps**: Scheda manovre verde smeraldo `#00875A` con anteprima della seconda svolta, barra di viaggio inferiore con orario di arrivo ETA esatto, e tachimetro circolare Waze con indicatore del limite e allarme visivo in caso di eccesso.
- **Itinerari Alternativi**: Calcolo di più rotte con OSRM e selezione tramite cassetto flottante con confronto tempi, km e traffico.
- **Layer Traffico in Tempo Reale**: Overlay trasparente del flusso di traffico stradale attivabile con il tasto `🚦`.
- **Ricerca Rapida POI**: Trova con un tocco distributori di benzina (`⛽`), parcheggi (`🅿️`), bar/ristoro (`☕`) e farmacie (`💊`) posizionando i pin sulla mappa.
- **Schermo Sempre Attivo**: `UIApplication.idleTimerDisabled = YES` impedisce lo spegnimento dello schermo durante la guida.
- **Guida Vocale Italiana Offline**: Sintesi vocale di sistema turn-by-turn fluida e naturale con `AVSpeechSynthesizer`.
- **Ricalcolo Automatico Fuori Rotta**: Se sbagli strada, l'app ricalcola la rotta all'istante senza distrarti.
