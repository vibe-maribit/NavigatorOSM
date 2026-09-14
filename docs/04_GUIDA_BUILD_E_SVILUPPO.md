# 04 - Guida di Compilazione, Sviluppo e Git su Linux

Questa guida spiega come è configurato l'ambiente di build per compilare il codice nativo Objective-C per iOS 9.3.5 (32-bit `armv7`) direttamente sul tuo computer Linux tramite Docker, senza bisogno di un computer macOS.

---

## 1. Come Funziona la Toolchain di Build su Linux

Apple ha rimosso il supporto per l'architettura a 32-bit (`armv7`) a partire da Xcode 14, impedendo la compilazione per i dispositivi A5 (come iPad Mini 1 e iPhone 4S) sugli ambienti cloud e Mac moderni.

Sul tuo PC Linux, la compilazione viene eseguita all'interno del container Docker `cauan/theos`:
- **Cross-Compiler Clang**: `armv7-apple-darwin11-clang` (versione LLVM con target Mach-O Darwin per iOS).
- **SDK di Sistema Apple**: `iPhoneOS9.3.sdk` (contenente tutti gli header e le definizioni dei framework nativi `UIKit`, `MapKit`, `CoreLocation`, `AVFoundation`).
- **Linker e Signer Mach-O**: `armv7-apple-darwin11-ld`, `ldid` per la firma ad-hoc del binario e `strip` per rimuovere i simboli di debug e ridurre il peso dell'eseguibile a pochi kilobyte.

---

## 2. Compilare il Pacchetto IPA con un Solo Comando

Per ricompilare l'intera applicazione e produrre il file `NavigatoreOSM.ipa`, apri il terminale su Linux ed esegui:

```bash
cd /home/nicola/Devel/retrofit/iOS/NavigatoreOSM
./package-ipa.sh
```

### Cosa fa lo script `package-ipa.sh`:
1. Esegue il container Docker montando la cartella corrente in `/project`:
   ```bash
   docker run --rm -v "$PWD:/project" -w /project cauan/theos make clean all DEBUG=0 messages=no
   ```
2. Compila tutti i file sorgente `.m` con ottimizzazione `-O2` e architettura `armv7`.
3. Crea la cartella standard di packaging iOS `Payload/NavigatoreOSM.app`.
4. Copia il binario compilato, le icone grafiche e il file `Info.plist`.
5. Comprime il tutto nell'archivio standard `NavigatoreOSM.ipa`.

---

## 3. Modificare o Aggiungere Codice al Progetto

Tutti i file sorgente si trovano in `/home/nicola/Devel/retrofit/iOS/NavigatoreOSM/NavigatoreOSM/`:
- Puoi modificare qualsiasi file `.h` e `.m` con il tuo editor di testo preferito (VS Code, Neovim, Sublime, etc.).
- Se aggiungi una nuova classe Objective-C (ad esempio `NuovaVista.m`), ricordati di aggiungere il suo percorso all'interno della variabile `NavigatoreOSM_FILES` nel file **`Makefile`**:

```makefile
NavigatoreOSM_FILES = NavigatoreOSM/main.m \
                      NavigatoreOSM/AppDelegate.m \
                      NavigatoreOSM/Controllers/NavigationViewController.m \
                      ... \
                      NavigatoreOSM/Views/NuovaVista.m
```

Dopo aver salvato, lancia nuovamente `./package-ipa.sh` per aggiornare il file `.ipa`.

---

## 4. Comandi Git Utili per lo Sviluppo

Il repository è configurato con controllo di versione Git:

### Verificare lo stato delle modifiche:
```bash
git status
```

### Registrare le modifiche (Commit):
```bash
git add .
git commit -m "feat: descrizione delle modifiche apportate"
```

### Visualizzare la cronologia dei commit:
```bash
git log --oneline --graph
```

### Collegamento a un repository remoto (GitHub / GitLab):
Se desideri salvare il progetto sul tuo account GitHub personale:
```bash
git remote add origin git@github.com:tuo-username/NavigatoreOSM-iPadMini.git
git branch -M main
git push -u origin main
```
