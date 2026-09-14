# NavigatoreOSM per iPad Mini 1 (MD528TY/A - iOS 9.3.5)

Applicazione **100% NATIVA iOS** (Objective-C + MapKit + UIKit) per trasformare l'iPad Mini 1ª Generazione (architettura 32-bit `armv7`, 512 MB RAM) in un navigatore GPS per auto con **OpenStreetMap**, **itinerari alternativi**, **traffico in tempo reale**, **ricerca rapida POI** e **guida vocale italiana offline**.

Zero WebKit, zero browser: l'app consuma meno di 25 MB di RAM e sfrutta la GPU Apple per un rendering a **60 FPS stabili**.

---

## Nuove Funzionalità Avanzate

### 1. Itinerari Alternativi & Scelta Percorso
- Quando cerchi una destinazione, il motore OSRM calcola fino a **3 itinerari alternativi**.
- Un selettore grafico ad alto contrasto in basso a schermo (`RouteSelectorView`) mostra:
  - **Tempo stimato e differenza** (es. `18 min • Più veloce` vs `24 min • +6 min`).
  - **Distanza chilometrica** (es. `14.2 km`).
  - **Sintesi vie principali** (es. `via A4 / Viale Certosa`).
  - **Stato del traffico previsto** (`Scorrevole 🟢`, `Rallentamenti 🟡`, `Traffico intenso 🔴`).
- Puoi toccare direttamente le linee dei percorsi sulla mappa (la rotta attiva è in blu brillante `#007AFF`, le alternative in viola `#5856D6`) o i pulsanti del selettore, per poi avviare la navigazione con il pulsante verde `▶ Avvia Navigazione`.

### 2. Flusso Traffico in Tempo Reale
- **Layer Traffico Dedicato** (`TrafficTileOverlay`): integrabile con API TomTom Flow / HERE Raster Flow tramite il pulsante `🚦` in basso a destra.
- **Analisi di Congestione OSRM**: valutazione automatica della velocità stimata per ciascun segmento di strada, con indicatore di traffico nel riepilogo rotta.

### 3. Ricalcolo Automatico Fuori Rotta (Auto-Rerouting)
- Se durante la guida imbocchi una strada diversa o sbagli un'uscita (scostamento > 70 metri per 4 rilevamenti consecutivi):
- La voce guida annuncia: *"Ricalcolo del percorso in corso..."*.
- Il sistema aggiorna automaticamente il tracciato e le manovre dalla tua posizione GPS attuale alla destinazione, senza distrarre il guidatore.

### 4. Ricerca Rapida POI (Punti di Interesse)
- Con il pulsante `📍 POI` in alto a destra, compare una barra rapida per trovare con un tocco:
  - `⛽ Benzina` (Distributori carburante vicini)
  - `🅿️ Parcheggi`
  - `☕ Bar / Ristoro`
  - `💊 Farmacie`
- I punti trovati vengono visualizzati con spille personalizzate sulla mappa; toccando una spilla puoi visualizzare i dettagli e impostarla subito come nuova destinazione.

### 5. Tachimetro Intelligente con Allerta Limiti di Velocità
- Tachimetro digitale in km/h con design HUD scuro.
- Toccando il tachimetro puoi impostare la soglia del limite (`50`, `70`, `90`, `110`, `130 km/h` o `Off`).
- Se superi il limite, il riquadro si illumina di **rosso brillante** con bordo giallo e ti avvisa del superamento!

### 6. Orario di Arrivo Reale (ETA) & Schermo Sempre Attivo
- L'HUD superiore calcola dinamicamente l'ora esatta di arrivo (`Arrivo: 18:45 • 14 km • 22 min`).
- `UIApplication.idleTimerDisabled = YES` garantisce che lo schermo resti sempre acceso senza mai andare in standby.

---

## File Principali del Progetto

- `NavigatoreOSM.ipa`: Pacchetto finale pronto da installare sull'iPad.
- `package-ipa.sh`: Compila e genera l'IPA tramite container Docker Theos.
- `install-usb.sh`: Installa l'app via USB con un solo comando.
- `android-gps-forwarder.py`: Invia le coordinate GPS dal computer o da un telefono Android via UDP all'iPad (utile per il modello solo Wi-Fi).

---

## Installazione Rapida via USB

Collega l'iPad Mini 1 al PC Linux con il cavo USB Lightning ed esegui:
```bash
cd /home/nicola/Devel/retrofit/iOS/NavigatoreOSM
./install-usb.sh
```
*(Se preferisci il comando diretto: `ideviceinstaller -i NavigatoreOSM.ipa`)*.
