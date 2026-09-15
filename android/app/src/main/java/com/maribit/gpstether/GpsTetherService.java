package com.maribit.gpstether;

import android.annotation.SuppressLint;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.os.Binder;
import android.os.Build;
import android.os.Bundle;
import android.os.IBinder;
import android.os.PowerManager;
import android.util.Log;

import androidx.core.app.NotificationCompat;

public class GpsTetherService extends Service implements LocationListener {

    private static final String TAG = "GpsTetherService";
    private static final String CHANNEL_ID = "GpsTetherChannel";
    private static final int NOTIFICATION_ID = 2001;

    public static final String ACTION_LOCATION_UPDATE = "com.maribit.gpstether.LOCATION_UPDATE";
    public static final String EXTRA_LAT = "lat";
    public static final String EXTRA_LON = "lon";
    public static final String EXTRA_SPEED = "speed";
    public static final String EXTRA_ACCURACY = "accuracy";
    public static final String EXTRA_BEARING = "bearing";
    public static final String EXTRA_PACKETS = "packets";

    private final IBinder binder = new LocalBinder();
    private LocationManager locationManager;
    private PowerManager.WakeLock wakeLock;
    private GpsBroadcaster broadcaster;
    private boolean isRunning = false;
    private Location lastLocation = null;

    public class LocalBinder extends Binder {
        public GpsTetherService getService() {
            return GpsTetherService.this;
        }
    }

    @Override
    public void onCreate() {
        super.onCreate();
        locationManager = (LocationManager) getSystemService(Context.LOCATION_SERVICE);
        PowerManager pm = (PowerManager) getSystemService(Context.POWER_SERVICE);
        if (pm != null) {
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "GPSTether::WakeLock");
            wakeLock.setReferenceCounted(false);
        }
        createNotificationChannel();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        int port = (intent != null) ? intent.getIntExtra("port", 8888) : 8888;
        startTethering(port);
        return START_STICKY;
    }

    @SuppressLint("MissingPermission")
    public void startTethering(int port) {
        if (isRunning) return;
        isRunning = true;

        if (wakeLock != null && !wakeLock.isHeld()) {
            wakeLock.acquire(12 * 60 * 60 * 1000L); // Fino a 12 ore continuo in auto
        }

        broadcaster = new GpsBroadcaster(port);
        broadcaster.start();

        startForeground(NOTIFICATION_ID, buildNotification("In attesa di segnale GPS satellitare..."));

        try {
            // Richiedi posizione GPS ad alta frequenza (500 ms)
            if (locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                locationManager.requestLocationUpdates(LocationManager.GPS_PROVIDER, 500, 0.0f, this);
            }
            // Fallback su provider di rete per avvio immediato
            if (locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                locationManager.requestLocationUpdates(LocationManager.NETWORK_PROVIDER, 1000, 0.0f, this);
            }
            Log.i(TAG, "LocationListener registrato con successo");
        } catch (Exception e) {
            Log.e(TAG, "Errore registrazione LocationManager: " + e.getMessage());
        }
    }

    public void stopTethering() {
        isRunning = false;
        try {
            locationManager.removeUpdates(this);
        } catch (Exception ignored) {}

        if (broadcaster != null) {
            broadcaster.stop();
            broadcaster = null;
        }

        if (wakeLock != null && wakeLock.isHeld()) {
            wakeLock.release();
        }

        stopForeground(true);
        stopSelf();
        Log.i(TAG, "GpsTetherService arrestato");
    }

    @Override
    public void onLocationChanged(Location loc) {
        if (loc == null) return;
        lastLocation = loc;

        if (broadcaster != null) {
            broadcaster.broadcastLocation(loc);
        }

        // Aggiorna notifica persistente
        double speedKmh = loc.getSpeed() * 3.6;
        String statusText = String.format("Velocità: %.0f km/h • Trasmessi: %d pacchetti",
                speedKmh, broadcaster != null ? broadcaster.getPacketsSent() : 0);
        NotificationManager nm = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm != null) {
            nm.notify(NOTIFICATION_ID, buildNotification(statusText));
        }

        // Trasmetti broadcast locale per aggiornare MainActivity
        Intent intent = new Intent(ACTION_LOCATION_UPDATE);
        intent.putExtra(EXTRA_LAT, loc.getLatitude());
        intent.putExtra(EXTRA_LON, loc.getLongitude());
        intent.putExtra(EXTRA_SPEED, loc.getSpeed());
        intent.putExtra(EXTRA_ACCURACY, loc.getAccuracy());
        intent.putExtra(EXTRA_BEARING, loc.getBearing());
        intent.putExtra(EXTRA_PACKETS, broadcaster != null ? broadcaster.getPacketsSent() : 0);
        sendBroadcast(intent);
    }

    @Override public void onStatusChanged(String provider, int status, Bundle extras) {}
    @Override public void onProviderEnabled(String provider) {}
    @Override public void onProviderDisabled(String provider) {}

    private Notification buildNotification(String contentText) {
        Intent notificationIntent = new Intent(this, MainActivity.class);
        PendingIntent pendingIntent = PendingIntent.getActivity(
                this, 0, notificationIntent,
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.M ? PendingIntent.FLAG_IMMUTABLE : 0);

        return new NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("🛰️ GPS Tethering Attivo")
                .setContentText(contentText)
                .setSmallIcon(android.R.drawable.ic_menu_compass)
                .setContentIntent(pendingIntent)
                .setOngoing(true)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .build();
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(
                    CHANNEL_ID,
                    "GPS Tether Service Channel",
                    NotificationManager.IMPORTANCE_LOW);
            channel.setDescription("Mantiene attiva la trasmissione GPS verso l'iPad");
            NotificationManager manager = getSystemService(NotificationManager.class);
            if (manager != null) {
                manager.createNotificationChannel(channel);
            }
        }
    }

    public boolean isRunning() {
        return isRunning;
    }

    public Location getLastLocation() {
        return lastLocation;
    }

    public long getPacketsSent() {
        return broadcaster != null ? broadcaster.getPacketsSent() : 0;
    }

    @Override
    public IBinder onBind(Intent intent) {
        return binder;
    }

    @Override
    public void onDestroy() {
        stopTethering();
        super.onDestroy();
    }
}
