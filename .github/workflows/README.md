# 🤖 CI/CD & Autonomous Development Workflows

Questa cartella contiene i workflow GitHub Actions per **NavigatorOSM**:
1. **`opencode.yml`**: Ciclo di sviluppo autonomo multi-agente con triage, dedup, planning, build e review (Theos Docker iOS 9.3.5 / armv7), auto-merge su `develop`, bump semantico e trigger del rilascio.
2. **`release.yml`**: Compilazione distribuibile completa (IPA iOS, pacchetto DEB Cydia, APK Android GPSTether) e pubblicazione su GitHub Releases e Cydia APT Repository (GitHub Pages).

---

## 🗺️ Architettura Generale del Ciclo Autonomo

```mermaid
flowchart TD
    Trigger["Nuova Issue o Commento con /oc"] --> Concurrency["Controllo Concorrenza (1 job per issue)"]
    Concurrency --> AuthCheck{"Autore Autorizzato?<br/>(Maintainer / Whitelist)"}
    AuthCheck -- No --> AbortAuth["Stop (Non autorizzato)"]
    AuthCheck -- Sì --> PreChecks{"Pre-Check Rapidi"}

    PreChecks -- "Issue già Closed (senza 'riapri')" --> AbortClosed["Stop (Issue già chiusa)"]
    PreChecks -- "Label duplicate / wontfix" --> AbortLabel["Stop (Issue sospesa)"]
    PreChecks -- "OK" --> React["Reazione 👀 (Issue + Commento)"]

    React --> Checkout["Checkout branch origin/develop"]
    Checkout --> SetupEnv["Pre-pull Docker cauan/theos & CLI"]
    SetupEnv --> TriagePhase["🔎 FASE 0: TRIAGE & DEDUP (Agente triage)"]

    TriagePhase --> TriageEval{"Esito Triage?"}
    TriageEval -- "ALREADY_IMPLEMENTED" --> TriageDone["Commento: Già implementato nel codice<br/>File e righe citati. Nessun commit. Stop"]
    TriageEval -- "DUPLICATE (#X)" --> TriageDup["Etichetta 'duplicate' + Commento riferimento. Stop"]
    TriageEval -- "PROCEED" --> PlanPhase["📝 FASE 1: PLAN (Agente planner)"]

    PlanPhase --> PlanFile["Genera e committa issue_plans/xxx.md"]
    PlanFile --> LoopBuildReview

    subgraph LoopBuildReview["Loop Build & Review (Max 4 Iterazioni)"]
        direction TB
        BuildAgent["🔨 FASE 2: BUILD (Agente build)<br/>Modifica codice ObjC / Android"] --> TheosDocker["⚙️ Verifica Build Theos Docker (armv7)<br/>docker run cauan/theos make all"]
        TheosDocker --> ReviewAgent["🔍 FASE 3: REVIEW (Agente reviewer)<br/>Valida Acceptance Criteria & iOS 9.3"]
        ReviewAgent --> VerdictCheck{"VERDICT?"}
        VerdictCheck -- "FAIL" --> FeedbackLoop["Passa feedback all'iterazione successiva"]
        FeedbackLoop --> BuildAgent
    end

    VerdictCheck -- "PASS" --> MergeStep["🔀 Squash-Merge automatico su develop"]
    MergeStep --> CloseIssue["Chiusura automatica dell'Issue"]
    CloseIssue --> SemanticBump["🏷️ Bump Versione Semantico (scripts/bump-version.py)"]
    
    SemanticBump --> BumpDecision{"Tipo di Richiesta?"}
    BumpDecision -- "Bug / Fix" --> BumpPatch["PATCH bump (es. 1.3.17 ➔ 1.3.18)"]
    BumpDecision -- "Feature / Enh" --> BumpMinor["MINOR bump (es. 1.3.17 ➔ 1.4.0)"]
    BumpDecision -- "Breaking / Major" --> BumpMajor["MAJOR bump (es. 1.3.17 ➔ 2.0.0)"]

    BumpPatch & BumpMinor & BumpMajor --> CommitTag["Commit [skip ci] & Push Git Tag vX.Y.Z"]
    CommitTag --> DispatchRelease["🚀 Trigger API workflow_dispatch verso release.yml"]
    DispatchRelease --> ReleaseWorkflow["📦 Pipeline release.yml (IPA, DEB Cydia, APK)"]
```

---

## 🛡️ Dettaglio Fasi e Meccanismi di Sicurezza

### 1. Pre-Check Rapidi & Concurrency
- **Concurrency Lock**: Tramite `concurrency: group: opencode-${{ issue.number }}`, commenti multipli o simultanei sulla stessa issue non creano conflitti git: le esecuzioni vengono accodate in modo ordinato.
- **Fast Exit**: Se un'issue è già etichettata `duplicate`, `invalid` o `wontfix`, o se è già `closed` (senza istruzione di riapertura), il workflow si arresta immediatamente senza sprecare minuti di runner.

### 2. Triage & Deduplicazione Intelligente
L'agente [`.opencode/agents/triage.md`](file:///home/nicola/Devel/retrofit/iOS/NavigatoreOSM/.opencode/agents/triage.md) analizza il codebase attuale su `develop` e le issue recenti:
- **`ALREADY_IMPLEMENTED`**: Rileva se il problema segnalato o la feature richiesta è **già presente** ed effettiva nel codice. Riporta i file e le righe a supporto, commenta sull'issue e termina senza toccare il codice né sporcare la git history.
- **`DUPLICATE`**: Se la segnalazione duplica un'altra issue aperta/recente, applica la label `duplicate`, cita l'issue originale e arresta l'elaborazione.
- **`PROCEED`**: Solo se c'è effettivo lavoro da svolgere, autorizza il passaggio alla pianificazione.

### 3. Pianificazione (Plan)
L'agente [`.opencode/agents/planner.md`](file:///home/nicola/Devel/retrofit/iOS/NavigatoreOSM/.opencode/agents/planner.md) produce un piano markdown in `issue_plans/` contenente:
- Obiettivo;
- Elenco task atomici con file coinvolti;
- Acceptance criteria oggettivi (inclusa compatibilità iOS 9.3.5 / chip Apple A5 512 MB RAM e divieto di API iOS 10+);
- Comandi di verifica build.

### 4. Build & Review Loop
- **Build**: Implementa le modifiche sui file di codice (Objective-C per iOS o Java/Kotlin per il companion Android `android/`).
- **Verifica Compilazione**: Lancia la compilazione Theos nativa a 32-bit:
  ```bash
  docker run --rm -v "$PWD:/project" -w /project cauan/theos make all DEBUG=0 messages=no
  ```
  *(e `./gradlew test assembleDebug` se viene modificata la cartella `android/`)*.
- **Review**: L'agente [`.opencode/agents/reviewer.md`](file:///home/nicola/Devel/retrofit/iOS/NavigatoreOSM/.opencode/agents/reviewer.md) verifica se ogni criterio è soddisfatto e se il binario compila pulito. Termina con `VERDICT: PASS` o `VERDICT: FAIL`.

### 5. Auto-Merge & Chiusura Issue
Se la review restituisce `VERDICT: PASS`:
1. Sincronizza ed esegue l'auto-merge via squash sul branch `develop`.
2. Chiude l'issue con `state_reason: completed`.

### 6. Bump Semantico & Trigger Release
Uno script unificato ([`scripts/bump-version.py`](file:///home/nicola/Devel/retrofit/iOS/NavigatoreOSM/scripts/bump-version.py)) aggiorna atomicamente:
- `control` (`Version: X.Y.Z`)
- `NavigatoreOSM/Info.plist` (`CFBundleShortVersionString` e `CFBundleVersion`)
- `android/app/build.gradle` (`versionName` e `versionCode + 1`)

Viene quindi generato e pushato il tag git `vX.Y.Z`, e tramite l'API di GitHub viene scatenato il workflow [`release.yml`](file:///home/nicola/Devel/retrofit/iOS/NavigatoreOSM/.github/workflows/release.yml) che compila IPA, DEB e APK rilasciandoli su GitHub Releases e sulla repo Cydia ufficiale.

---

## ⌨️ Come Attivare OpenCode

### 1. All'apertura di una nuova Issue
Usa i template interattivi:
- **Feature Request** (`.github/ISSUE_TEMPLATE/feature_request.yml`)
- **Bug Report** (`.github/ISSUE_TEMPLATE/bug_report.yml`)

Il comando precompilato in fondo avvia la action in automatico.

### 2. Tramite Commento
In qualsiasi Issue o Pull Request aperta:
```text
/oc correggi l'anomalia nel ricalcolo del percorso OSRM
```

Opzioni avanzate disponibili:
- **Modello specifico**:
  ```text
  /oc --model opencode/claude-3-7-sonnet ottimizza il consumo di memoria
  ```
- **Forzare il tipo di incremento semantico**:
  ```text
  /oc --bump minor aggiungi il selettore del tipo di carburante preferito
  ```
