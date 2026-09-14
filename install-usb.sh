#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR"

OS_NAME="$(uname -s)"

echo "========================================================="
echo "  Installazione NavigatoreOSM su iPad Mini via USB"
echo "  Sistema rilevato: $OS_NAME"
echo "========================================================="

if [ ! -f "NavigatoreOSM.ipa" ]; then
    echo "Errore: NavigatoreOSM.ipa non trovato nella cartella."
    echo "Assicurati che il file .ipa sia presente in questa directory."
    exit 1
fi

# Verifica la presenza di ideviceinstaller
if ! command -v ideviceinstaller &> /dev/null; then
    echo ""
    echo "ATTENZIONE: 'ideviceinstaller' non risulta installato sul tuo sistema."
    if [ "$OS_NAME" = "Darwin" ]; then
        echo "Per installarlo su macOS con Homebrew, esegui semplicemente:"
        echo "  brew install ideviceinstaller libimobiledevice"
        echo ""
        echo "In alternativa su Mac puoi usare:"
        echo "- Sideloadly (gratuito con interfaccia grafica)"
        echo "- Apple Configurator (trascina l'IPA sul dispositivo)"
    else
        echo "Per installarlo su Ubuntu/Debian Linux, esegui:"
        echo "  sudo apt update && sudo apt install -y ideviceinstaller libimobiledevice-utils"
    fi
    exit 1
fi

echo "Verifico dispositivo collegato..."

DEVICE_NAME=$(ideviceinfo -k DeviceName 2>/dev/null || true)
if [ -z "$DEVICE_NAME" ]; then
    echo ""
    echo "ATTENZIONE: Nessun dispositivo iOS rilevato via USB."
    echo "1. Collega l'iPad Mini al computer con il cavo USB."
    echo "2. Se l'iPad chiede 'Vuoi autorizzare questo computer?', tocca 'Autorizza'."
    if [ "$OS_NAME" = "Linux" ]; then
        echo "   (Se necessario su Linux: sudo systemctl restart usbmuxd)"
    fi
    echo "3. Riesegui questo script."
    exit 1
fi

PRODUCT_TYPE=$(ideviceinfo -k ProductType 2>/dev/null || echo "Dispositivo iOS")
IOS_VERSION=$(ideviceinfo -k ProductVersion 2>/dev/null || echo "Sconosciuto")

echo "Dispositivo trovato: $DEVICE_NAME ($PRODUCT_TYPE) con iOS $IOS_VERSION"
echo ""

# Rileva sintassi corretta di ideviceinstaller (moderna con comandi vs legacy con flag -i)
if ideviceinstaller --help 2>&1 | grep -q "COMMANDS:"; then
    CMD_STR="ideviceinstaller install NavigatoreOSM.ipa"
    CMD_EXEC=(ideviceinstaller install NavigatoreOSM.ipa)
else
    CMD_STR="ideviceinstaller -i NavigatoreOSM.ipa"
    CMD_EXEC=(ideviceinstaller -i NavigatoreOSM.ipa)
fi

echo "Eseguo: $CMD_STR"
echo "Installazione in corso..."

set +e
"${CMD_EXEC[@]}"
INSTALL_STATUS=$?
set -e

if [ $INSTALL_STATUS -eq 0 ]; then
    echo ""
    echo "========================================================="
    echo "  Installazione completata con successo!"
    echo "  Troverai l'icona 'Navigatore' sulla schermata Home dell'iPad."
    echo "========================================================="
else
    echo ""
    echo "========================================================="
    echo "  ERRORE DURANTE L'INSTALLAZIONE (codice $INSTALL_STATUS)"
    echo "========================================================="
    echo "Se riscontri 'ApplicationVerificationFailed':"
    echo ""
    echo "1. SE L'IPAD E' JAILBROKEN (Phoenix / kok3shi9):"
    echo "   - Apri Cydia sull'iPad."
    echo "   - Aggiungi la sorgente: https://cydia.akemi.ai/"
    echo "   - Installa il tweak 'AppSync Unified'."
    echo "   - Se hai riavviato l'iPad di recente, riapri l'app Phoenix/kok3shi9"
    echo "     e tocca 'Kickstart Jailbreak' per riattivarlo."
    echo "   - Riesegui questo script."
    echo ""
    echo "2. SE L'IPAD E' ORIGINALE (NON JAILBROKEN):"
    echo "   - iOS originale blocca le app non firmate da Apple."
    echo "   - Usa Sideloadly (gratuito per macOS e Windows - https://sideloadly.io):"
    echo "     1. Avvia Sideloadly sul tuo computer con l'iPad collegato via USB."
    echo "     2. Trascina il file 'NavigatoreOSM.ipa' nell'interfaccia."
    echo "     3. Inserisci il tuo Apple ID per la firma automatica gratuita a 7 giorni."
    echo "     4. Clicca 'Start'. L'app verrà installata direttamente sull'iPad!"
    echo "========================================================="
    exit $INSTALL_STATUS
fi

