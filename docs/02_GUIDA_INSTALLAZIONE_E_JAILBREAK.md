# 02 - Guida all'Installazione e al Jailbreak (iOS 9.3.5)

Questa guida spiega come preparare il tuo **iPad Mini 1 (MD528TY/A - iOS 9.3.5 Build 13G36)** e installare l'applicazione **`NavigatoreOSM.ipa`** direttamente dal tuo PC Linux tramite cavo USB, senza limiti di scadenza di 7 giorni.

---

## 1. Prerequisiti Hardware e Software

- **Dispositivo**: iPad Mini 1ª Generazione (modello A1432, Wi-Fi 16GB, Nero/Ardesia).
- **Versione di iOS**: 9.3.5 (13G36).
- **Cavo USB**: Cavo Lightning a USB collegato direttamente a una porta USB del PC Linux.
- **PC Linux**: Pacchetti `ideviceinstaller` e `libimobiledevice` (già installati e verificati sul tuo sistema).

---

## 2. Perché il Jailbreak è Consigliato per Questo Progetto

Sui dispositivi iOS non modificati ("stock"):
- Il sideloading con un account Apple gratuito richiede di risiglare e reinstallare l'applicazione ogni **7 giorni** (scadenza del certificato gratuito).
- Con un vecchio tablet destinato a restare in auto come navigatore fisso, dover ricollegare il tablet ogni settimana è poco pratico.

**Con il Jailbreak e il tweak AppSync Unified:**
- L'iPad accetta l'installazione di qualsiasi pacchetto `.ipa` ad-hoc o unsigned.
- L'app resta installata **per sempre**, non scade mai e si installa in 5 secondi via cavo USB con un solo comando da Linux!

---

## 3. Procedura di Jailbreak su iOS 9.3.5 (Operazione da 3 Minuti)

Per iOS 9.3.5 su chip A5 a 32-bit esistono due jailbreak semi-untethered collaudatissimi:
1. **kok3shi9** (Molto consigliato per stabilità, sviluppato da dora2ios).
2. **Phoenix** (Storico jailbreak per iOS 9.3.5 sviluppato da Siguza e tihmstar).

### Passaggi:
1. Scarica il file `.ipa` di **kok3shi9** (o Phoenix) dal sito ufficiale.
2. Installalo sull'iPad (tramite Sideloadly da PC o via Safari con Legacy iOS Kit).
3. Apri l'app sull'iPad, tocca **"Jailbreak"** e attendi il riavvio della SpringBoard (*respring*).
4. Sulla schermata Home comparirà l'icona marrone di **Cydia**.

---

## 4. Installazione del Tweak Essenziale: AppSync Unified

Una volta avviato Cydia:
1. Apri **Cydia** sull'iPad Mini.
2. Vai nella scheda in basso **Sorgenti** (o *Sources*).
3. Tocca **Modifica** in alto a destra, poi **Aggiungi** in alto a sinistra.
4. Digita l'indirizzo ufficiale della sviluppatrice Karen (*akemi*):
   ```
   https://cydia.akemi.ai/
   ```
5. Tocca **Aggiungi sorgente** e attendi il caricamento dei repository.
6. Cerca **AppSync Unified** e tocca **Installa** -> **Conferma**.
7. Al termine dell'installazione tocca **Riavvia SpringBoard**.

> [!TIP]
> Da questo momento in poi, il tuo iPad Mini accetterà qualsiasi installazione di pacchetti `.ipa` da cavo USB senza mai verificare certificati Apple o scadenze!

---

## 5. Installazione di NavigatoreOSM da Linux via USB

Sul tuo PC Linux abbiamo predisposto lo script automatizzato:

1. Collega l'iPad Mini con il cavo USB Lightning al PC Linux.
2. Se sullo schermo dell'iPad compare la richiesta:
   *"Vuoi autorizzare questo computer?"*, tocca **Autorizza** e inserisci il codice di sblocco dell'iPad.
3. Apri il terminale su Linux ed entra nella cartella del progetto:
   ```bash
   cd /home/nicola/Devel/retrofit/iOS/NavigatoreOSM
   ./install-usb.sh
   ```

### Cosa fa lo script `install-usb.sh`:
- Interroga il demone `usbmuxd` tramite `ideviceinfo` per verificare la presenza del tablet.
- Legge il modello e la versione del sistema operativo (`iPad2,5`, `iOS 9.3.5`).
- Invia il pacchetto `NavigatoreOSM.ipa` tramite `ideviceinstaller -i`.
- In circa 5 secondi, l'installazione è completa!

L'icona **Navigatore** apparirà istantaneamente sulla schermata Home dell'iPad.

---

## 6. Risoluzione dei Problemi Comuni USB su Linux

### Errore: `ERROR: No device found!`
1. Verifica che il cavo Lightning sia integro e non solo per la ricarica (deve supportare il passaggio dati).
2. Prova a scollegare e ricollegare il cavo in un'altra porta USB.
3. Riavvia il servizio di gestione dispositivi iOS su Linux:
   ```bash
   sudo systemctl restart usbmuxd
   ```
4. Esegui `ideviceinfo` per verificare che risponda correttamente con i dati dell'iPad.

### Errore: `Device is locked with a passcode`
Sblocca lo schermo dell'iPad Mini prima di lanciare `./install-usb.sh`.

### Errore: `ApplicationVerificationFailed`
Significa che l'iPad non ha ancora installato **AppSync Unified** da Cydia. Assicurati di aver seguito il punto 4 di questa guida.
