# Piano

## Obiettivo

Riparare i bug segnalati relativi ai distributori di carburante in NavigatorOSM:

1. **Problema grafico**: Il tasto in alto a destra per visualizzare i distributori di benzina è sovrapposto alla bussola.
2. **Problema logico sui marker**: I segnaposto dei distributori mostrano sempre il tipo di carburante selezionato nel filtro (ad esempio mostrano GPL anche quando il distributore non lo vende).
3. **Supporto mancante**: Mancano le opzioni/marker per Metano (CNG) e Elettrico (colonnine di ricarica).

Il fix deve mantenere la piena compatibilità con i vincoli architetturali di NavigatorOSM (iOS 9.3.5 armv7, Objective-C + Theos, Android GPSTether, memoria 512 MB).

## Task

### 1. Analisi del layout UI iOS (bussola e pulsante distributori)
- [ ] **1.1 Esplorazione UI**: Analizzare il codice relativo alla barra superiore, alla bussola e al pulsante "Distributori/Benzinai".
- **File coinvolti (da verificare):** `MapViewController.m`, `MapViewController.h`, eventuali file XIB/Storyboard in `Resources/`, file di layout personalizzato (`*.m`/`*.h` relativi a toolbar/top bar).
- **Azione**: Identificare come sono posizionati (frame, autolayout legacy, offsets) il pulsante in alto a destra e la bussola, e perché risultano sovrapposti.

### 2. Correzione sovrapposizione grafica (iOS)
- [ ] **2.1 Ripristino spaziatura corretta**: Modificare il posizionamento per garantire che bussola e pulsante distributori siano visibili entrambi (adeguare margini, ridurre dimensioni, riorganizzare l'ordine delle view o spostare il pulsante in un'area diversa evitando collisioni).
- **File coinvolti**: `MapViewController.m` (e relativi header). Eventuali `UIBarButtonItem`, `UIButton` o custom views per bussola/toolbar.
- **Vincolo**: Usare SOLO API iOS 9.3.5 (nessuna UIViewPropertyAnimator, UIStackView moderno se introduce comportamenti iOS>=10, ecc.). Preferire gestione frame/manuale o layout compatibile.

### 3. Analisi logica marker distributori di carburante (iOS)
- [ ] **3.1 Individuare rendering marker**: Trovare il codice che crea le annotazioni/marker per le stazioni di rifornimento (fuel stations) sulla mappa.
- **File coinvolti (candidati):** `MapViewController.m`, classi di annotazione (`*Annotation*.m/h`), renderer di POI, codice di parsing Overpass/OSM per fuel (ad es. `POI*`, `OSM*`, `Overpass*`, `MapMarker*`).
- **3.2 Analizzare gestione filtro carburante**: Verificare come viene applicato il filtro (tipo selezionato: Benzina/Diesel/GPL etc.) e come questo influisce sull'icona/visualizzazione del marker. Identificare se l'icona viene forzata al tipo selezionato anziché riflettere la disponibilità reale del distributore.
- **3.3 Verificare mappatura tag OSM**: Analizzare parsing dei tag OSM (`fuel:petrol`, `fuel:diesel`, `fuel:lpg`/`fuel:autogas`, `fuel:cng`/`compressed_natural_gas`, `fuel:octane_95`, `fuel:electricity`/`amenity=charging_station`). Capire struttura dati usata per memorizzare i tipi disponibili per ogni stazione.

### 4. Correzione logica marker - disponibilità reale (iOS)
- [ ] **4.1 Separare concetti filtro vs. visualizzazione**: Correggere la logica in modo che:
  - Il filtro selezionato continui a filtrare quali distributori mostrare (solo quelli che vendono il tipo scelto), **MA**
  - L'icona/marker del singolo distributore rappresenti i tipi di carburante **effettivamente disponibili** in quella stazione (multi-carburante), non il tipo correntemente selezionato nel filtro.
- **File coinvolti**: codice marker/annotation per fuel (stesso ambito task 3).
- **Approccio**: Basarsi sui tag OSM presenti per ciascuna stazione (array/set di fuel types disponibili) per decidere l'icona/label da mostrare.

### 5. Aggiungere supporto Metano (CNG) ed Elettrico (iOS)
- [ ] **5.1 Estendere enum/tipi carburante**: Aggiungere Metano (`fuel:cng`, `compressed_natural_gas`, `cng`) ed Elettrico (`fuel:electricity`, `amenity=charging_station`/`fuel:electric`).
- **File coinvolti**: definizioni tipi (header), parsing OSM/Overpass, logica di filtro.
- [ ] **5.2 Aggiungere icone/risorse**: Verificare presenza e aggiungere (se mancanti) icone per Metano ed Elettrico. Usare risorse esistenti coerenti con stile app.
- **File coinvolti**: cartella `Resources/`, eventuali `Images.xcassets` o PNG.
- [ ] **5.3 Aggiornare UI filtri**: Aggiornare interfaccia di selezione filtro carburante per includere Metano ed Elettrico (menu/pulsanti esistenti, mantenendo compatibilità iOS 9).
- **File coinvolti**: `MapViewController.m`, eventuali view di filtro.

### 6. Verifica e allineamento Android (GPSTether)
- [ ] **6.1 Analisi Android**: Esaminare `android/` (Java/Kotlin, Gradle) per verificare se presenta gli stessi bug: sovrapposizione UI (bussola/tasto distributori), logica marker fuel
# Piano

## Obiettivo

Riparare i bug segnalati relativi ai distributori di carburante in NavigatorOSM:

1. **Problema grafico (iOS)**: Il tasto in alto a destra per visualizzare i distributori di benzina è sovrapposto alla bussola.
2. **Problema logico sui marker (iOS/Android)**: I segnaposto dei distributori mostrano sempre il tipo di carburante selezionato nel filtro (ad es. mostrano GPL anche quando il distributore non lo vende/fornisce quel tipo).
3. **Supporto mancante**: Aggiungere Metano (CNG) ed Elettrico (colonnine di ricarica) sia nella logica di parsing, sia nei filtri, sia nelle icone/marker.

Il fix deve rispettare pienamente i vincoli architetturali di NavigatorOSM: iOS 9.3.5 armv7 (Objective-C + Theos), Android GPSTether (Java/Kotlin + Gradle), footprint contenuto (< 25 MB), compatibilità API iOS 9.3 (nessuna API >= iOS 10).

## Task

### 1. Analisi del layout UI iOS (bussola e pulsante distributori)
- [ ] **1.1 Esplorazione UI**: Analizzare la barra superiore/top bar, la bussola e il pulsante per attivare/mostrare i distributori di benzina.
- **File coinvolti**: `NavigatorOSM/MapViewController.m`, `NavigatorOSM/MapViewController.h`
- **Azione**: Individuare come sono creati e posizionati (frame, bounds, origin, spacing, margini, eventuali subview) il pulsante in alto a destra e la view/indicatore della bussola. Identificare la causa esatta della sovrapposizione.

- [ ] **1.2 Verifica risorse/layout aggiuntivi**: Controllare eventuali XIB/Storyboard, custom view o configurazioni di toolbar/UIBarButtonItem.
- **File coinvolti**: `Resources/*` (XIB, plist, immagini), eventuali file `*Compass*`, `*TopBar*`, `*Toolbar*` in `NavigatorOSM/`
- **Azione**: Verificare se il posizionamento dipende da costanti hardcoded (offset) o da calcoli dinamici (safe area legacy, status bar, orientamento).

### 2. Correzione sovrapposizione grafica (iOS)
- [ ] **2.1 Ripristino spaziatura corretta**: Correggere il layout per garantire che bussola e pulsante distributori siano entrambi visibili e non sovrapposti, senza compromettere usabilità su schermi piccoli (dispositivi iOS 9.3 32-bit).
- **File coinvolti**: `NavigatorOSM/MapViewController.m` (area di setup toolbar/top bar, posizionamento view)
- **Azione**: Adeguare margini, spaziatura tra elementi, ordine delle view, eventuale ridimensionamento controllato o spostamento del pulsante in area non in collisione. Preferire gestione esplicita dei `frame` (compatibile iOS 9) rispetto a soluzioni che richiedano API moderne.
- **Vincolo**: Solo API iOS 9.3. Nessun uso di `UIViewPropertyAnimator`, `UIStackView` (se comporta requisiti iOS>=10), `NSLayoutConstraint` attivi con caratteristiche iOS10+ o `UITraitCollection` avanzati non necessari. Mantenere approccio legacy compatibile.

### 3. Analisi logica marker distributori di carburante (iOS)
- [ ] **3.1 Individuazione rendering marker/annotation**: Trovare il codice che crea, configura e renderizza le annotazioni/stazioni di rifornimento sulla mappa.
- **File coinvolti (da individuare/verificare)**: `NavigatorOSM/MapViewController.m`, classi `*Annotation*` (`Fuel*Annotation*`, `Station*Annotation*`, `POI*Annotation*`), `*Marker*`, `*Callout*`, eventuali renderer custom in `NavigatorOSM/`
- **Azione**: Localizzare dove viene deciso l'icone/visuale del marker per fuel stations.

- [ ] **3.2 Analisi filtro carburante vs. visualizzazione**: Studiare logica filtro (tipo selezionato: Benzina/Diesel/GPL etc.) e come questa impatta sull'icona del singolo marker.
- **File coinvolti**: `MapViewController.m`, eventuali `*FuelFilter*`, `*FuelType*`, `*Station*`
- **Azione**: Determinare se l'icona viene forzata al tipo di filtro attivo invece di rappresentare i tipi di carburante **disponibili** nella stazione.

- [ ] **3.3 Analisi parsing OSM per fuel**: Verificare parsing dei tag OSM relativi ai distributori (Overpass/OSM XML/JSON).
- **Tag da considerare**: `amenity=fuel`, `fuel:petrol`, `fuel:gasoline`, `fuel:diesel`, `fuel:lpg`, `fuel:autogas`, `fuel:cng`, `compressed_natural_gas`, `fuel:octane_95`, `fuel:octane_98`, `fuel:electricity`, `fuel:electric`, `amenity=charging_station`. Verificare anche sinonimi usati.
- **File coinvolti**: codice di download/parsing Overpass, `*Overpass*`, `*OSMParser*`, `*POI*`, `*Data*`, `MapViewController.m`
- **Azione**: Capire la struttura dati che memorizza i fuel types disponibili per ogni stazione (array/set/bitmap).

### 4. Correzione logica marker - disponibilità reale (iOS)
- [ ] **4.1 Separare filtro e rappresentazione del marker**: Correggere la logica in modo che:
  - Il filtro selezionato **continui a filtrare** quali distributori vengono mostrati (solo quelli che vendono il tipo scelto).
  - L'icona/marker di ciascun distributore rappresenti i **tipi di carburante effettivamente disponibili** in quella stazione (supporto a multi-carburante), **non** il tipo correntemente selezionato nel filtro.
- **File coinvolti**: logica di creazione/assegnazione icona marker/annotation (task 3.1), dati stazione.
- **Azione**: Basarsi esclusivamente sui tag OSM presenti per la stazione per decidere icona/visualizzazione (deterministic, non influenzata dallo stato del filtro UI).

- [ ] **4.2 Revisione aggiornamento marker al cambio filtro**: Garantire che il cambio filtro non ri-assegni erroneamente l'icona forzando il tipo selezionato.
- **File coinvolti**: `MapViewController.m`, gestione reload/refresh POI.

### 5. Aggiungere supporto Metano (CNG) ed Elettrico (iOS)
- [ ] **5.1 Estendere tipi/carburanti**: Aggiungere Metano (CNG) ed Elettrico al modello dei tipi di carburante.
- **File coinvolti**: definizioni enum/typedef, costanti, strutture dati fuel type (header + .m pertinenti: es. `*Fuel*`, `MapViewController.h/m`, eventuali `*Station*.h/m`).
- **Tag mapping**: Metano: `fuel:cng`, `compressed_natural_gas`, `cng`. Elettrico: `fuel:electricity`, `fuel:electric`, `amenity=charging_station` (trattare charging_station coerentemente con fuel stations ove rilevante).
- **Azione**: Estendere parsing per rilevare questi tag e popolare la lista dei tipi disponibili.

- [ ] **5.2 Aggiungere icone/risorse**: Verificare esistenza icone per Metano ed Elettrico. Aggiungerle se mancanti, mantenendo coerenza stilistica con le icone esistenti.
- **File coinvolti**: `Resources/` (PNG), eventuali `Images.xcassets` (se presenti). Verificare anche eventuali icone marker in bundle.
- **Azione**: Usare nomi coerenti con convenzione esistente, ottimizzati per retina/retina@2x compatibili (iOS 9). Evitare asset di grandi dimensioni inutili per rispettare < 25 MB totale.

- [ ] **5.3 Aggiornare UI filtri**: Estendere interfaccia di selezione filtro carburante per includere Metano (CNG) ed Elettrico.
- **File coinvolti**: `MapViewController.m`, eventuali view/controller di filtro, elementi UI (UIButton, UIPickerView, UITableView, action sheet) usati per selezione filtro. Usare solo componenti UI disponibili su iOS 9.
- **Azione**: Garantire aggiornamento corretto della lista filtri, stato selezionato e comportamento di filtro (mostra solo stazioni con quel tipo disponibile).

### 6. Verifica e allineamento Android (GPSTether)
- [ ] **6.1 Analisi Android**: Esaminare l'applicazione companion `android/` (struttura Gradle, Java/Kotlin).
- **File coinvolti**: `android/app/src/main/` (Activities/Fragments, Map UI, POI/Fuel), `android/app/build.gradle`, `android/build.gradle`, `android/settings.gradle`, risorse `res/`, manifest.
- **Azione**: Verificare presenza di UI con bussola e pulsante distributori, eventuale sovrapposizione layout, logica marker fuel (filtro vs disponibilità reale), supporto CNG/Elettrico.

- [ ] **6.2 Correzioni Android (se rilevate anomalie)**: Allineare comportamento Android a quanto corretto su iOS laddove applicabile (separazione filtro vs icona marker, aggiunta Metano/Elettrico, fix layout sovrapposizione).
- **File coinvolti**: layout XML (`res/layout/`), codice map/marker (OSMDroid/MapLibre/Google Maps a seconda implementazione), adapter/POI, risorse drawable.
- **Azione**: Applicare fix minimi e coerenti, senza introdurre dipendenze non necessarie. Verificare compatibilità con target SDK/Android supportati dal progetto.

- [ ] **6.3 Verifica build Android**: Preparazione per test/assemble (vedi sezione Verifica).

## Acceptance Criteria

### Generali
- [ ] Il pulsante in alto a destra per visualizzare i distributori di benzina **non** è più sovrapposto alla bussola su iOS (entrambi visibili, correttamente spaziati in orientamento portrait/landscape ove applicabile).
- [ ] I marker dei distributori mostrano l'icona basata sui **tipi di carburante effettivamente disponibili** nella singola stazione (non forzata al filtro selezionato). Il filtro continua a limitare quali stazioni vengono mostrate.
- [ ] Sono stati aggiunti **Metano (CNG)** ed **Elettrico**: presenti nel parsing OSM, nei filtri UI e nelle icone/marker (iOS). Allineamento Android ove presenti le stesse funzionalità.
- [ ] Nessuna regressione funzionale evidente sulla visualizzazione mappa/POI.
- [ ] Rispetto vincoli: solo API iOS 9.3.5, footprint contenuto (< 25 MB), nessun leak di memoria evidente, codice Objective-C coerente.

### Compilazione
- [ ] **Compilazione iOS Theos (produzione/controllo)**: `docker run --rm -v "$PWD:/project" -w /project cauan/theos make all DEBUG=0 messages=no` termina con successo (nessun errore di compilazione/linking). Il pacchetto `.deb`/output Theos generato è valido.
- [ ] **Compilazione Android** (se sono state apportate modifiche in `android/`): `cd android && ./gradlew test assembleDebug --no-daemon` termina con successo. Test unitari (se presenti) passano senza errori.

## Verifica

### Verifica iOS (manuale)
1. Avviare l'app su dispositivo/simulatore iOS 9.3.5 (target armv7). Verificare stato iniziale: bussola e pulsante distributori **entrambi visibili**, ben spaziati (nessuna sovrapposizione).
2. Aprire filtro distributori: verificare presenza di nuove opzioni **Metano (CNG)** ed **Elettrico**.
3. Selezionare un tipo di filtro (es. GPL). Verificare che vengano mostrate solo stazioni che vendono effettivamente quel tipo. **Contemporaneamente**, verificare su almeno 2-3 marker differenti che l'icona del marker non sia uniformemente "GPL" ma rifletta la reale disponibilità (marker multi-carburante mostrano icona coerente con disponibilità reale, non con filtro).
4. Cambiare filtro più volte (Benzina, Diesel, GPL, Metano, Elettrico). Confermare che l'icona dei singoli marker **non cambia** al variare del filtro (cambia solo il set di stazioni filtrate). Questo verifica la corretta separazione filtro vs visualizzazione.
5. Test rapido su orientamento (se supportato): verificare layout bussola+pulsante rimane corretto.

### Verifica Android (se modificato)
1. `cd android && ./gradlew --version` (verifica ambiente Gradle).
2. Build/test: `cd android && ./gradlew test assembleDebug --no-daemon`. Controllare output: BUILD SUCCESSFUL, test passati.
3. Verifica funzionale UI marker/filtro se modifiche rilevanti (layout bussola/tasto distributori, presenza CNG/Elettrico, logica marker).

### Verifica build Theos (comando richiesto)
Eseguire esattamente:
```bash
docker run --rm -v "$PWD:/project" -w /project cauan/theos make all DEBUG=0 messages=no
```
Verificare:
- Exit code 0
- Nessun warning/error critico
- Presenza output generato (deb/package) in percorso Theos previsto senza errori di linking.

### Verifica qualità generale
- [ ] Controllo rapido dimensioni binario/output (per confermare footprint < 25 MB).
- [ ] Verifica non siano state introdotte API iOS >= 10 (ispezione diff delle modifiche Objective-C: evitare classi/metodi introdotti da iOS 10 come `UIFeedbackGenerator`, `UNUserNotificationCenter`, `UIViewPropertyAnimator`, ecc.). Solo API disponibili su iOS 9.3.
- [ ] Nessun uso di `cd <dir> && ...` nei comandi (verrà rispettato in verifica). Usare workdir/path corretti.
