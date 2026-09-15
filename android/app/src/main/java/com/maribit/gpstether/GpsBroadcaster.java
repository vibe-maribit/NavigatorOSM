package com.maribit.gpstether;

import android.location.Location;
import android.util.Log;

import java.io.IOException;
import java.io.OutputStream;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicLong;

public class GpsBroadcaster {

    private static final String TAG = "GpsBroadcaster";

    private final int port;
    private final AtomicLong packetsSent = new AtomicLong(0);
    private final ExecutorService executor = Executors.newCachedThreadPool();

    private DatagramSocket udpSocket;
    private ServerSocket tcpServerSocket;
    private final List<Socket> connectedTcpClients = Collections.synchronizedList(new ArrayList<>());
    private volatile boolean isRunning = false;

    public GpsBroadcaster(int port) {
        this.port = port;
    }

    public synchronized void start() {
        if (isRunning) return;
        isRunning = true;

        // Inizializza Socket UDP Broadcast
        try {
            udpSocket = new DatagramSocket();
            udpSocket.setBroadcast(true);
            Log.i(TAG, "Socket UDP Broadcast avviato su porta " + port);
        } catch (Exception e) {
            Log.e(TAG, "Errore creazione socket UDP: " + e.getMessage());
        }

        // Inizializza Server TCP in background per clienti che richiedono stream TCP
        executor.execute(this::runTcpServer);
    }

    private void runTcpServer() {
        try {
            tcpServerSocket = new ServerSocket(port);
            Log.i(TAG, "Server TCP in ascolto su porta " + port);
            while (isRunning && !tcpServerSocket.isClosed()) {
                Socket client = tcpServerSocket.accept();
                Log.i(TAG, "Nuovo client TCP connesso da: " + client.getRemoteSocketAddress());
                connectedTcpClients.add(client);
            }
        } catch (Exception e) {
            if (isRunning) {
                Log.w(TAG, "Server TCP interrotto: " + e.getMessage());
            }
        }
    }

    public void broadcastLocation(Location loc) {
        if (!isRunning || loc == null) return;

        executor.execute(() -> {
            try {
                // 1. Prepara Payload JSON nativo
                String json = String.format(Locale.US,
                        "{\"lat\": %.6f, \"lon\": %.6f, \"speed\": %.2f, \"bearing\": %.1f, \"alt\": %.1f, \"acc\": %.1f, \"time\": %d}\n",
                        loc.getLatitude(), loc.getLongitude(),
                        loc.getSpeed(), loc.getBearing(),
                        loc.getAltitude(), loc.getAccuracy(),
                        loc.getTime());

                // 2. Prepara Sentenza NMEA standard
                String nmea = NmeaUtils.formatGPRMC(loc);

                byte[] jsonBytes = json.getBytes(StandardCharsets.UTF_8);
                byte[] nmeaBytes = nmea.getBytes(StandardCharsets.UTF_8);

                // 3. Invia via UDP Broadcast globale e subnet hotspot
                if (udpSocket != null && !udpSocket.isClosed()) {
                    InetAddress globalBroadcast = InetAddress.getByName("255.255.255.255");
                    udpSocket.send(new DatagramPacket(jsonBytes, jsonBytes.length, globalBroadcast, port));
                    udpSocket.send(new DatagramPacket(nmeaBytes, nmeaBytes.length, globalBroadcast, port));

                    // Invia anche a broadcast hotspot tipico Android (192.168.43.255)
                    try {
                        InetAddress hotspotBroadcast = InetAddress.getByName("192.168.43.255");
                        udpSocket.send(new DatagramPacket(jsonBytes, jsonBytes.length, hotspotBroadcast, port));
                    } catch (Exception ignored) {}
                }

                // 4. Invia ai client TCP connessi
                synchronized (connectedTcpClients) {
                    List<Socket> deadClients = new ArrayList<>();
                    for (Socket s : connectedTcpClients) {
                        try {
                            OutputStream os = s.getOutputStream();
                            os.write(jsonBytes);
                            os.write(nmeaBytes);
                            os.flush();
                        } catch (IOException e) {
                            deadClients.add(s);
                        }
                    }
                    connectedTcpClients.removeAll(deadClients);
                }

                packetsSent.incrementAndGet();

            } catch (Exception e) {
                Log.e(TAG, "Errore invio pacchetto GPS: " + e.getMessage());
            }
        });
    }

    public long getPacketsSent() {
        return packetsSent.get();
    }

    public synchronized void stop() {
        isRunning = false;
        if (udpSocket != null) {
            udpSocket.close();
            udpSocket = null;
        }
        if (tcpServerSocket != null) {
            try {
                tcpServerSocket.close();
            } catch (Exception ignored) {}
            tcpServerSocket = null;
        }
        synchronized (connectedTcpClients) {
            for (Socket s : connectedTcpClients) {
                try {
                    s.close();
                } catch (Exception ignored) {}
            }
            connectedTcpClients.clear();
        }
        executor.shutdownNow();
    }
}
