#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR"

echo "========================================================="
echo "  Compilazione GPSTether per Android"
echo "  Target: Android 5.0 - 14+ (APK Sideload)"
echo "========================================================="

if [ -f "./gradlew" ]; then
    chmod +x ./gradlew
    ./gradlew assembleDebug
elif command -v gradle &> /dev/null; then
    gradle assembleDebug
else
    echo "Gradle non trovato localmente. Utilizzo Docker Android Build Box..."
    docker run --rm -v "$DIR:/project" -w /project mingc/android-build-box bash -c "gradle assembleDebug"
fi

OUTPUT_APK="$DIR/app/build/outputs/apk/debug/app-debug.apk"
if [ -f "$OUTPUT_APK" ]; then
    cp "$OUTPUT_APK" "$DIR/../GPSTether.apk"
    echo "========================================================="
    echo "  SUCCESS: GPSTether.apk generato con successo!"
    echo "  Posizione: $DIR/../GPSTether.apk"
    echo "========================================================="
    ls -lh "$DIR/../GPSTether.apk"
else
    echo "Compilazione terminata. Per aprire in Android Studio: apri la cartella android/"
fi
