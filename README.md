# NavigatoreOSM per iPad Mini 1 (MD528TY/A - iOS 9.3.5)

Applicazione **100% NATIVA iOS** (Objective-C + MapKit + UIKit) per riutilizzare l'iPad Mini 1ª Generazione come navigatore GPS per auto con **OpenStreetMap**, routing **OSRM** e **guida vocale italiana offline**.

Zero WebKit, zero browser: sfrutta l'accelerazione hardware della GPU Apple e consuma meno di 25 MB di RAM, garantendo 60 FPS stabili anche sul processore Apple A5 a 32-bit.

---

## File Principali

- `NavigatoreOSM.ipa`: Pacchetto finale pronto da installare sull'iPad.
- `package-ipa.sh`: Ricompila l'app e ricrea il file `.ipa` usando il container Docker Theos.
- `install-usb.sh`: Installa direttamente l'app sull'iPad Mini collegato via cavo USB.
- `android-gps-forwarder.py`: Invia le coordinate GPS dal computer o da un telefono Android via UDP all'iPad (utile per il modello solo Wi-Fi).

---

## Come Installare sull'iPad Mini

### Prerequisito: Jailbreak & AppSync Unified (Consigliato)
Per installare app senza limiti di tempo e senza bisogno di un account sviluppatore:
1. Effettua il jailbreak dell'iPad Mini 1 (iOS 9.3.5) usando ad esempio **Phoenix** o **kok3shi9** (operazione di 2 minuti).
2. Apri Cydia, aggiungi la sorgente `https://cydia.akemi.ai/` e installa **AppSync Unified**.

### Installazione con un solo comando via USB:
1. Collega l'iPad Mini 1 con il cavo USB Lightning al PC Linux.
2. Esegui dal terminale:
   ```bash
   cd /home/nicola/Devel/retrofit/iOS/NavigatoreOSM
   ./install-usb.sh
   ```
   *oppure manualmente:*
   ```bash
   ideviceinstaller -i NavigatoreOSM.ipa
   ```
3. L'icona **Navigatore** comparirà sulla schermata Home dell'iPad.

---

## Caratteristiche dell'App

1. **OpenStreetMap a 60 FPS**: Mappe caricate tramite `MKTileOverlay` nativo con supporto a temi Giorno e Notte.
2. **Cache Disco Offline**: Ogni tassello visualizzato viene salvato in `Library/Caches/OSMTiles` e rimane disponibile senza internet.
3. **Schermo Sempre Attivo**: `UIApplication.idleTimerDisabled = YES` impedisce lo spegnimento dello schermo durante la marcia.
4. **Guida Vocale Italiana**: Sintesi vocale turn-by-turn nativa `AVSpeechSynthesizer` ("Tra 200 metri svolta a destra in Via Roma").
5. **Ricerca Destinazioni**: Ricerca integrata con l'API Nominatim OpenStreetMap.
6. **Supporto GPS Wi-Fi / Hotspot**:
   - Con **iPhone Hotspot**: Funziona in automatico (iOS passa il GPS dell'iPhone all'iPad).
   - Con **Android Hotspot o PC**: Il modulo `NetworkGPSReceiver` integrato ascolta su porta UDP 8888 e riceve coordinate in tempo reale inviate da `android-gps-forwarder.py` o app GPS forwarder Android.
