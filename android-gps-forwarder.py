#!/usr/bin/env python3
"""
Simulatore / Forwarder GPS per iPad Mini 1 (Wi-Fi Only) e Meta Quest (flutterAR via Quest GPS Bridge)
Invia coordinate GPS e azimut bussola via pacchetti UDP sulla porta 8888.

Uso:
  python3 android-gps-forwarder.py <IP_DELL_IPAD_O_QUEST> [--simulate] [--azimuth AZIMUTH] [--rate HZ]
"""

import sys
import time
import json
import socket
import argparse

def main():
    parser = argparse.ArgumentParser(description="Forwarder / Simulatore GPS UDP per NavigatoreOSM e flutterAR")
    parser.add_argument("ip", help="Indirizzo IP del dispositivo target nella rete locale / hotspot")
    parser.add_argument("--port", type=int, default=8888, help="Porta UDP (default: 8888)")
    parser.add_argument("--simulate", action="store_true", help="Simula un tragitto o fix GPS a Milano")
    parser.add_argument("--azimuth", type=float, default=None, help="Azimut bussola in gradi [0, 360) da trasmettere")
    parser.add_argument("--rate", type=float, default=5.0, help="Frequenza invio in Hz (default: 5.0 Hz)")
    args = parser.parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    print(f"[*] Inizio invio pacchetti GPS a {args.ip}:{args.port} ({args.rate} Hz)")

    interval = 1.0 / max(args.rate, 0.1)

    if args.simulate:
        print("[*] Modalità simulazione attiva (tragitto virtuale a Milano con bussola)...")
        # Tragitto di prova (Milano: Duomo -> Parco Sempione)
        lat = 45.4642
        lon = 9.1900
        speed_kmh = 45.0
        bearing = 315.0
        azimuth = args.azimuth if args.azimuth is not None else 87.5

        try:
            step = 0
            while True:
                data = {
                    "lat": round(lat, 6),
                    "lon": round(lon, 6),
                    "speed": round(speed_kmh / 3.6, 2), # m/s
                    "bearing": round(bearing, 1),
                    "alt": 120.0,
                    "acc": 4.0,
                    "time": int(time.time() * 1000)
                }
                if azimuth is not None:
                    data["azimuth"] = round(azimuth, 1)
                    data["azimuthAcc"] = 10.0

                payload = (json.dumps(data) + "\n").encode("utf-8")
                sock.sendto(payload, (args.ip, args.port))

                az_str = f", azimuth={data.get('azimuth')}°" if "azimuth" in data else ""
                print(f"[+] Inviato: lat={lat:.5f}, lon={lon:.5f}, speed={speed_kmh} km/h, bearing={bearing}°{az_str}")

                step += 1
                if step % int(max(args.rate, 1.0)) == 0:
                    # Spostamento ogni secondo
                    lat += 0.0001
                    lon -= 0.0001
                time.sleep(interval)
        except KeyboardInterrupt:
            print("\n[*] Interrotto dall'utente.")
    else:
        print("[*] Per simulare un movimento, aggiungi l'opzione --simulate")

if __name__ == "__main__":
    main()
