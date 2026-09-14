#!/usr/bin/env python3
"""
Simulatore / Forwarder GPS per iPad Mini 1 (Wi-Fi Only)
Invia coordinate GPS via pacchetti UDP sulla porta 8888 verso l'iPad.

Uso:
  python3 android-gps-forwarder.py <IP_DELL_IPAD> [--simulate]
"""

import sys
import time
import json
import socket
import argparse

def main():
    parser = argparse.ArgumentParser(description="Forwarder / Simulatore GPS UDP per NavigatoreOSM")
    parser.add_argument("ip", help="Indirizzo IP dell'iPad Mini nella rete locale / hotspot")
    parser.add_argument("--port", type=int, default=8888, help="Porta UDP (default: 8888)")
    parser.add_argument("--simulate", action="store_true", help="Simula un tragitto in auto a Milano")
    args = parser.parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    print(f"[*] Inizio invio pacchetti GPS a {args.ip}:{args.port}")

    if args.simulate:
        print("[*] Modalità simulazione attiva (tragitto virtuale)...")
        # Tragitto di prova (Milano: Duomo -> Parco Sempione)
        lat = 45.4642
        lon = 9.1900
        speed_kmh = 45.0
        bearing = 315.0

        try:
            while True:
                payload = json.dumps({
                    "lat": lat,
                    "lon": lon,
                    "speed": speed_kmh / 3.6, # m/s
                    "bearing": bearing
                }).encode("utf-8")

                sock.sendto(payload, (args.ip, args.port))
                print(f"[+] Inviato: lat={lat:.5f}, lon={lon:.5f}, speed={speed_kmh} km/h, bearing={bearing}°")

                # Spostamento virtuale
                lat += 0.0001
                lon -= 0.0001
                time.sleep(1.0)
        except KeyboardInterrupt:
            print("\n[*] Interrotto dall'utente.")
    else:
        print("[*] Per simulare un movimento, aggiungi l'opzione --simulate")

if __name__ == "__main__":
    main()
