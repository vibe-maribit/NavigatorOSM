#!/usr/bin/env bash
# ==============================================================================
# OpenCode Autonomous CI Runner per NavigatorOSM
# Supporta esecuzione modulare:
#   runner.sh plan   -> Fase 1: Plan, State Tracking & Dedup
#   runner.sh build  -> Fase 2: Build & Review Loop
#   runner.sh [all]  -> Fase 1 + Fase 2 complete
# ==============================================================================
set -euo pipefail

MODE="${1:-all}"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-develop}"
PLAN_KEY="${PLAN_KEY:-${BRANCH_NAME:-plan}}"
CHOSEN_MODEL="${INPUT_MODEL:-${CHOSEN_MODEL:-${DEFAULT_MODEL:-opencode/big-pickle}}}"

# Rilevamento immagini per supporto visuale autonomo
FULL_TEXT="${ISSUE_BODY:-} ${ISSUE_TITLE:-} ${CLEAN_PROMPT:-}"
if [ -z "${INPUT_MODEL:-}" ] && echo "$FULL_TEXT" | grep -Eq '(!\[[^]]*\]\([^)]+\)|<img[[:space:]]|user-attachments|\.(png|jpe?g|gif|webp|bmp))'; then
  VISUAL_MODEL="${INPUT_VISUAL_MODEL:-${VISUAL_MODEL:-opencode/space-bunny-free}}"
  echo "🖼️ Immagini rilevate nel testo dell'issue: utilizzo del modello visivo $VISUAL_MODEL"
  CHOSEN_MODEL="$VISUAL_MODEL"
fi

if [[ "$CHOSEN_MODEL" != *"/"* ]]; then
  CHOSEN_MODEL="opencode/$CHOSEN_MODEL"
fi
MAX_ITERATIONS="${MAX_ITERATIONS:-4}"
PLAN_FILE="issue_plans/${PLAN_KEY}.md"

mkdir -p issue_plans /tmp
touch /tmp/runner_output.env

echo "=========================================================="
echo "🚀 OpenCode Autonomous Runner per NavigatorOSM (Modo: $MODE)"
echo "Modello: $CHOSEN_MODEL | Max Iterazioni: $MAX_ITERATIONS"
echo "Branch: ${BRANCH_NAME:-$DEFAULT_BRANCH} | Plan Key: $PLAN_KEY"
echo "=========================================================="

# ── HELPER: Salva Output per Workflow e Ambiente ─────────────────────────────
save_output() {
  local key="$1"
  local val="$2"
  # Salva nel file locale /tmp/runner_output.env
  sed -i "/^${key}=/d" /tmp/runner_output.env 2>/dev/null || true
  echo "${key}=${val}" >> /tmp/runner_output.env
  # Salva in GITHUB_OUTPUT se definito
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    # In GitHub Actions usiamo chiavi minuscole o originali
    local lower_key
    lower_key=$(echo "$key" | tr '[:upper:]' '[:lower:]')
    echo "${lower_key}=${val}" >> "$GITHUB_OUTPUT"
    echo "${key}=${val}" >> "$GITHUB_OUTPUT"
  fi
}

# ── FASE 1: PLAN, STATE TRACKING & DEDUP ─────────────────────────────────────
run_plan() {
  echo "::group::Fase 1 — PLAN & STATO AVANZAMENTO ($CHOSEN_MODEL)"
  CLEAN_PROMPT=$(cat /tmp/clean_prompt.txt 2>/dev/null || echo "Nessun prompt")
  CONTEXT=$(cat /tmp/context.txt 2>/dev/null || echo "")
  RECENT_ISSUES=$(cat /tmp/recent_issues.txt 2>/dev/null || echo "")

  IS_RELEASE_REQUEST=false
  if echo "$CLEAN_PROMPT $CONTEXT ${ISSUE_TITLE:-} ${ISSUE_BODY:-}" | grep -Eiq '(procedi.*(pubblica|rilasci|release)|rilascia|pubblica|chiudi|conferma.*release)'; then
    echo "📣 Rilevata richiesta esplicita di rilascio/pubblicazione."
    IS_RELEASE_REQUEST=true
  fi

  if [ -s "$PLAN_FILE" ]; then
    echo "📋 Piano esistente trovato in $PLAN_FILE: valutazione stato di avanzamento e dedup..."
    EXISTING_PLAN=$(cat "$PLAN_FILE")
    PLAN_PROMPT="Sei in modalità PLAN / STATE MACHINE (SOLA LETTURA) per NavigatorOSM.
Esamina il codice ATTUALE del branch rispetto al piano esistente.

=== PIANO ESISTENTE ===
$EXISTING_PLAN

=== RICHIESTA / COMMENTO ATTUALE ===
$CLEAN_PROMPT
Contesto: ${ISSUE_TITLE:-} - ${ISSUE_BODY:-}
$CONTEXT

Istruzioni:
1. Ispeziona i file di NavigatorOSM per ciascun Acceptance Criterion.
2. Aggiorna i criteri soddisfatti con '- [x]'. Mantieni con '- [ ]' quelli non ancora soddisfatti.
3. Se TUTTI i criteri sono soddisfatti o se l'utente ha chiesto di pubblicare/rilasciare e non ci sono errori, imposta PLAN_STATUS: ALL_COMPLETED.
4. Se ci sono ancora modifiche da fare, imposta PLAN_STATUS: IN_PROGRESS.
5. Se si tratta di un duplicato evidente, imposta PLAN_STATUS: DUPLICATE.
6. Restituisci il piano Markdown aggiornato."

    if ! opencode run --agent planner --model "$CHOSEN_MODEL" "$PLAN_PROMPT" > /tmp/plan_eval.md; then
      if [ "$CHOSEN_MODEL" != "opencode/big-pickle" ]; then
        echo "⚠️ Fallimento con $CHOSEN_MODEL nel planner. Fallback a opencode/big-pickle..."
        CHOSEN_MODEL="opencode/big-pickle"
        opencode run --agent planner --model "$CHOSEN_MODEL" "$PLAN_PROMPT" > /tmp/plan_eval.md || true
      fi
    fi
    if [ -s /tmp/plan_eval.md ]; then
      cp /tmp/plan_eval.md "$PLAN_FILE"
    fi
  else
    echo "📝 Generazione nuovo piano con OpenCode (agente planner)..."
    PLAN_PROMPT="Analizza la richiesta e crea il piano di lavoro per NavigatorOSM (iOS 9.3.5 armv7 / Android GPSTether).
Richiesta: $CLEAN_PROMPT
Contesto: ${ISSUE_TITLE:-} - ${ISSUE_BODY:-}
$CONTEXT

Elenco Issue Recenti del Repository (per deduplicazione):
$RECENT_ISSUES

Se la richiesta risulta già implementata o duplicata, segnalalo con PLAN_STATUS: ALREADY_DONE o DUPLICATE.
Altrimenti includi Task, Acceptance Criteria ('- [ ]') e Verifica."

    if ! opencode run --agent planner --model "$CHOSEN_MODEL" "$PLAN_PROMPT" > /tmp/plan_gen.md; then
      if [ "$CHOSEN_MODEL" != "opencode/big-pickle" ]; then
        echo "⚠️ Fallimento con $CHOSEN_MODEL. Fallback a opencode/big-pickle..."
        CHOSEN_MODEL="opencode/big-pickle"
        opencode run --agent planner --model "$CHOSEN_MODEL" "$PLAN_PROMPT" > /tmp/plan_gen.md || true
      fi
    fi
    if [ -s /tmp/plan_gen.md ]; then
      cp /tmp/plan_gen.md "$PLAN_FILE"
    fi
  fi

  cp "$PLAN_FILE" /tmp/plan.md

  # Determina PLAN_STATUS
  PLAN_STATUS="IN_PROGRESS"
  if grep -Eq 'PLAN_STATUS:[[:space:]]*ALL_COMPLETED' "$PLAN_FILE"; then
    PLAN_STATUS="ALL_COMPLETED"
  elif grep -Eq 'PLAN_STATUS:[[:space:]]*DUPLICATE' "$PLAN_FILE"; then
    PLAN_STATUS="DUPLICATE"
  elif grep -Eq 'PLAN_STATUS:[[:space:]]*ALREADY_DONE' "$PLAN_FILE"; then
    PLAN_STATUS="ALREADY_DONE"
  elif ! grep -q '^- \[ \]' "$PLAN_FILE" && grep -q '^- \[x\]' "$PLAN_FILE"; then
    echo "Tutti gli Acceptance Criteria risultano spuntati (- [x])."
    PLAN_STATUS="ALL_COMPLETED"
  elif [ "$IS_RELEASE_REQUEST" = "true" ]; then
    echo "Richiesta esplicita di rilascio dall'utente con criteri già verificati."
    PLAN_STATUS="ALL_COMPLETED"
  fi

  VERDICT="FAIL"
  if [ "$PLAN_STATUS" = "ALL_COMPLETED" ]; then
    echo "🔍 Verifica finale compilazione Theos per conferma rilascio..."
    if docker run --rm -v "$PWD:/project" -w /project cauan/theos make all DEBUG=0 messages=no; then
      echo "✅ Compilazione Theos superata con successo: confermato ALL_COMPLETED."
      VERDICT="PASS"
      echo "VERDICT: PASS" > /tmp/review.txt
    else
      echo "⚠️ Compilazione Theos fallita: permangono errori, impostato IN_PROGRESS."
      PLAN_STATUS="IN_PROGRESS"
      VERDICT="FAIL"
    fi
  elif [ "$PLAN_STATUS" = "DUPLICATE" ]; then
    VERDICT="DUPLICATE"
    cp "$PLAN_FILE" /tmp/triage_reason.txt
  elif [ "$PLAN_STATUS" = "ALREADY_DONE" ]; then
    VERDICT="ALREADY_DONE"
    cp "$PLAN_FILE" /tmp/triage_reason.txt
  fi

  # Checkpoint commit e push del piano aggiornato
  git add "$PLAN_FILE"
  git commit -m "OpenCode: piano e stato avanzamento ($PLAN_STATUS)" || echo "Nessun cambiamento al piano da committare."
  if [ -n "${BRANCH_NAME:-}" ]; then
    git push origin "$BRANCH_NAME" || true
  fi

  echo "::endgroup::"
  echo "📊 Esito Fase Plan: PLAN_STATUS=$PLAN_STATUS, VERDICT=$VERDICT"

  save_output "PLAN_STATUS" "$PLAN_STATUS"
  save_output "VERDICT" "$VERDICT"
}

# ── FASE 2: BUILD & REVIEW LOOP ──────────────────────────────────────────────
run_build() {
  PLAN=""; [ -f /tmp/plan.md ] && PLAN="$(cat /tmp/plan.md)"
  CLEAN_PROMPT=$(cat /tmp/clean_prompt.txt 2>/dev/null || echo "")
  CONTEXT=$(cat /tmp/context.txt 2>/dev/null || echo "")
  REVIEW_FEEDBACK="(prima iterazione: nessun feedback)"
  VERDICT="FAIL"

  for i in $(seq 1 "$MAX_ITERATIONS"); do
    echo "::group::Iterazione $i — BUILD ($CHOSEN_MODEL)"
    BUILD_PROMPT="Sei in modalità BUILD per NavigatorOSM. Implementa il piano completando TUTTI i task non ancora spuntati e soddisfacendo TUTTI gli Acceptance Criteria.
Applica le modifiche ai file.
Ricorda i vincoli: iOS 9.3.5 32-bit armv7, memoria limitata a 512 MB (Apple A5), nessuna API iOS 10+.

=== PIANO ===
${PLAN:-Richiesta: $CLEAN_PROMPT}

=== CONTESTO ===
$CONTEXT

=== FEEDBACK REVIEW PRECEDENTE ===
$REVIEW_FEEDBACK"

    if ! opencode run --agent build --auto --model "$CHOSEN_MODEL" "$BUILD_PROMPT"; then
      if [ "$CHOSEN_MODEL" != "opencode/big-pickle" ]; then
        echo "⚠️ Fallimento con $CHOSEN_MODEL. Fallback a opencode/big-pickle..."
        CHOSEN_MODEL="opencode/big-pickle"
        opencode run --agent build --auto --model "$CHOSEN_MODEL" "$BUILD_PROMPT" || true
      fi
    fi
    echo "::endgroup::"

    # Checkpoint commit & push dopo la build
    git add .
    git commit -m "OpenCode ($CHOSEN_MODEL): build progress (iterazione $i)" || true
    if [ -n "${BRANCH_NAME:-}" ]; then
      git push origin "$BRANCH_NAME" || true
    fi

    echo "::group::Iterazione $i — REVIEW ($CHOSEN_MODEL)"
    REVIEW_PROMPT="Verifica sul codice ATTUALE se OGNI Acceptance Criterion del piano è soddisfatto.
Esegui la compilazione Theos per verificare che non ci siano errori:
docker run --rm -v \"\$PWD:/project\" -w /project cauan/theos make all DEBUG=0 messages=no
(Se hai modificato file in android/, esegui anche: cd android && ./gradlew test assembleDebug --no-daemon)

NON modificare i file di codice.

=== PIANO ===
${PLAN:-Richiesta: $CLEAN_PROMPT}

Scrivi come ULTIMA riga ESATTAMENTE una di queste:
- 'VERDICT: PASS'  se tutti i criteri sono soddisfatti e il codice compila
- 'VERDICT: FAIL'  altrimenti, seguita da un elenco puntato dei criteri NON soddisfatti, errori di compilazione e di cosa manca."

    opencode run --agent reviewer --auto --model "$CHOSEN_MODEL" "$REVIEW_PROMPT" 2>&1 | tee /tmp/review.txt || true
    if grep -q "Unexpected server error" /tmp/review.txt || [ ! -s /tmp/review.txt ]; then
      if [ "$CHOSEN_MODEL" != "opencode/big-pickle" ]; then
        echo "⚠️ Fallimento con $CHOSEN_MODEL nella review. Fallback a opencode/big-pickle..."
        CHOSEN_MODEL="opencode/big-pickle"
        opencode run --agent reviewer --auto --model "$CHOSEN_MODEL" "$REVIEW_PROMPT" 2>&1 | tee /tmp/review.txt || true
      fi
    fi
    echo "::endgroup::"

    if grep -Eq 'VERDICT:[[:space:]]*PASS' /tmp/review.txt; then
      echo "✅ Acceptance criteria soddisfatti all'iterazione $i."
      VERDICT="PASS"
      # Aggiorna il file del piano marcando i criteri con - [x]
      if [ -s "$PLAN_FILE" ]; then
        sed -i 's/^- \[ \]/- [x]/g' "$PLAN_FILE"
        git add "$PLAN_FILE"
        git commit -m "OpenCode: acceptance criteria completati e verificati" || true
        [ -n "${BRANCH_NAME:-}" ] && git push origin "$BRANCH_NAME" || true
      fi
      break
    fi
    REVIEW_FEEDBACK="$(cat /tmp/review.txt)"
    echo "⚠️ Criteri non soddisfatti: procedo con iterazione $((i+1))."
  done

  save_output "VERDICT" "$VERDICT"
  echo "🏁 Ciclo Build & Review completato con esito: $VERDICT"
}

# ── ESECUZIONE ────────────────────────────────────────────────────────────────
case "$MODE" in
  plan)
    run_plan
    ;;
  build)
    run_build
    ;;
  all)
    run_plan
    CURRENT_STATUS=$(grep '^PLAN_STATUS=' /tmp/runner_output.env 2>/dev/null | cut -d'=' -f2 || echo "IN_PROGRESS")
    if [ "$CURRENT_STATUS" = "IN_PROGRESS" ]; then
      run_build
    else
      echo "⏭️ Fase Build & Review skippata perché PLAN_STATUS=$CURRENT_STATUS."
    fi
    ;;
  *)
    echo "Modo sconosciuto: $MODE. Usare plan, build o all."
    exit 1
    ;;
esac
