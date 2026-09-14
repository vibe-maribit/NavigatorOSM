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
echo "Installazione in corso di NavigatoreOSM.ipa..."
ideviceinstaller -i NavigatoreOSM.ipa

echo ""
echo "========================================================="
echo "  Installazione completata con successo!"
echo "  Troverai l'icona 'Navigatore' sulla schermata Home dell'iPad."
echo "========================================================="
