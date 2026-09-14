#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR"

if [ ! -f "NavigatoreOSM.ipa" ]; then
    echo "Errore: NavigatoreOSM.ipa non trovato. Esegui prima ./package-ipa.sh"
    exit 1
fi

echo "========================================================="
echo "  Installazione NavigatoreOSM su iPad Mini via USB"
echo "========================================================="
echo "Verifico dispositivo collegato..."

DEVICE_NAME=$(ideviceinfo -k DeviceName 2>/dev/null || true)
if [ -z "$DEVICE_NAME" ]; then
    echo ""
    echo "ATTENZIONE: Nessun dispositivo iOS rilevato via USB."
    echo "1. Collega l'iPad Mini al PC con il cavo USB."
    echo "2. Se l'iPad chiede 'Vuoi autorizzare questo computer?', tocca 'Autorizza'."
    echo "3. Riesegui questo script."
    exit 1
fi

PRODUCT_TYPE=$(ideviceinfo -k ProductType 2>/dev/null || echo "Sconosciuto")
IOS_VERSION=$(ideviceinfo -k ProductVersion 2>/dev/null || echo "Sconosciuto")

echo "Dispositivo trovato: $DEVICE_NAME ($PRODUCT_TYPE) con iOS $IOS_VERSION"
echo ""
echo "Installazione in corso..."
ideviceinstaller -i NavigatoreOSM.ipa

echo ""
echo "========================================================="
echo "  Installazione completata con successo!"
echo "  Troverai l'icona 'Navigatore' sulla schermata Home dell'iPad."
echo "========================================================="
