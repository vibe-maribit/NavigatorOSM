#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR"

echo "========================================================="
echo "  Compilazione GPSTether per Android"
echo "  Target: Android 5.0 - 14+ (APK Sideload)"
echo "========================================================="

JAVA_VER=$(java -version 2>&1 | head -n 1 | awk -F '"' '{print $2}' | cut -d'.' -f1)
if [ "$JAVA_VER" = "1" ]; then
    JAVA_VER=$(java -version 2>&1 | head -n 1 | awk -F '"' '{print $2}' | cut -d'.' -f2)
fi

if [ -f "./gradlew" ] && [ "$JAVA_VER" -ge 17 ] 2>/dev/null; then
    chmod +x ./gradlew
    ./gradlew assembleDebug
elif docker images ghcr.io/cirruslabs/android-sdk:34 -q 2>/dev/null | grep -q .; then
    echo "Utilizzo container Docker ghcr.io/cirruslabs/android-sdk:34..."
    docker run --rm -v "$DIR:/project" -w /project ghcr.io/cirruslabs/android-sdk:34 ./gradlew assembleDebug
elif command -v docker &> /dev/null; then
    echo "Utilizzo Docker Android Build Box..."
    docker run --rm -v "$DIR:/project" -w /project mingc/android-build-box bash -c "gradle assembleDebug"
elif command -v gradle &> /dev/null; then
    gradle assembleDebug
fi

OUTPUT_APK="$DIR/app/build/outputs/apk/debug/app-debug.apk"
if [ -f "$OUTPUT_APK" ]; then
    cp "$OUTPUT_APK" "$DIR/../GPSTether.apk"
    if [ -d "$DIR/../cydia_repo" ]; then
        cp "$OUTPUT_APK" "$DIR/../cydia_repo/GPSTether.apk"
    fi
    echo "========================================================="
    echo "  SUCCESS: GPSTether.apk generato con successo!"
    echo "  Posizione: $DIR/../GPSTether.apk"
    echo "========================================================="
    ls -lh "$DIR/../GPSTether.apk"
else
    echo "Compilazione terminata. Per aprire in Android Studio: apri la cartella android/"
fi
