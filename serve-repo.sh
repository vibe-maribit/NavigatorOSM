#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
IP=$(hostname -I | awk '{print $1}')
PORT=8088

echo "========================================================="
echo "  Server Repository Cydia Locale (HTTP - Nessun Certificato SSL Richiesto)"
echo "========================================================="
echo "  IP del computer: $IP"
echo ""
echo "  Per installare/aggiornare NavigatoreOSM su iPad Mini:"
echo "  1. Assicurati che l'iPad sia connesso alla stessa rete Wi-Fi del computer."
echo "  2. Apri Cydia sull'iPad > Sorgenti > Modifica > Aggiungi."
echo "  3. Inserisci l'indirizzo HTTP:"
echo "     http://$IP:$PORT/"
echo "  4. Tocca 'Aggiungi sorgente': i pacchetti appariranno istantaneamente!"
echo "========================================================="
echo "In ascolto su 0.0.0.0:$PORT... (Premi CTRL+C per arrestare)"

python3 -m http.server $PORT --directory "$DIR/cydia_repo"
