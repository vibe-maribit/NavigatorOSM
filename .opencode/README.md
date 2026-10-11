# 🤖 OpenCode Multi-Agent System

Questo modulo contiene gli agenti specializzati e gli script di orchestrazione per lo sviluppo autonomo di **NavigatorOSM** (iOS 9.3.5 armv7 Theos + Android companion).

---

## 📂 Struttura

```
.opencode/
├── README.md               # Questa documentazione
├── agents/
│   ├── triage.md           # Agente di triage, deduplicazione e controllo codice esistente (Read-Only)
│   ├── planner.md          # Agente pianificatore con vincoli Apple A5 e Theos (Read-Only)
│   └── reviewer.md         # Agente revisore con verifica compilazione Theos/Gradle (Read-Only)
└── ci/
    └── runner.sh           # Orchestratore del loop Triage ➔ Plan ➔ Build ➔ Review
```

---

## 🎭 Ruoli degli Agenti

### 1. `triage` ([`agents/triage.md`](file:///home/nicola/Devel/retrofit/iOS/NavigatoreOSM/.opencode/agents/triage.md))
- **Modalità**: Sola lettura (`read-only`).
- **Obiettivo**: Analizza la richiesta confrontandola con il codice attuale di `develop` e le issue recenti per prevenire doppio lavoro.
- **Output**:
  - `TRIAGE_STATUS: ALREADY_IMPLEMENTED` se la richiesta è già soddisfatta nel codice.
  - `TRIAGE_STATUS: DUPLICATE #X` se la richiesta duplica un'altra issue aperta/recente.
  - `TRIAGE_STATUS: PROCEED` se ci sono nuove modifiche effettive da pianificare.

### 2. `planner` ([`agents/planner.md`](file:///home/nicola/Devel/retrofit/iOS/NavigatoreOSM/.opencode/agents/planner.md))
- **Modalità**: Sola lettura (`read-only`).
- **Obiettivo**: Redige il piano in `issue_plans/<nome_branch>.md`.
- **Vincoli noti**:
  - Piattaforma: iOS 9.3.5 (armv7 32-bit), Theos Makefile.
  - Hardware: SoC Apple A5 (iPad Mini 1st Gen), 512 MB RAM (footprint basso, zero memory leak).
  - Divieto di API iOS 10+.

### 3. `build` (Agente builtin di OpenCode)
- **Modalità**: Scrittura codice (`write`).
- **Obiettivo**: Implementa i task del piano modificando i file sorgente (`NavigatoreOSM/`, `android/`).

### 4. `reviewer` ([`agents/reviewer.md`](file:///home/nicola/Devel/retrofit/iOS/NavigatoreOSM/.opencode/agents/reviewer.md))
- **Modalità**: Sola lettura (`read-only`).
- **Obiettivo**: Valuta l'aderenza ai criteri di accettazione e verifica la compilazione:
  ```bash
  docker run --rm -v "$PWD:/project" -w /project cauan/theos make all DEBUG=0 messages=no
  ```
- **Output**: `VERDICT: PASS` oppure `VERDICT: FAIL` con i punti mancanti.

---

## 🏃 Esecuzione Manuale del Runner

Per eseguire localmente il ciclo di orchestrazione:
```bash
export BRANCH_NAME="feature/tether-optimization"
export ISSUE_TITLE="Miglioramento sincronizzazione tethering"
export ISSUE_BODY="Descrizione del task..."
bash .opencode/ci/runner.sh
```
