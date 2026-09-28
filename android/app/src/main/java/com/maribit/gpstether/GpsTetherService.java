package com.maribit.gpstether;

import android.annotation.SuppressLint;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.hardware.GeomagneticField;
import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorEventListener;
import android.hardware.SensorManager;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.os.Binder;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.PowerManager;
import android.util.Log;

import androidx.core.app.NotificationCompat;

import java.util.List;
import java.util.Locale;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

public class GpsTetherService extends Service implements LocationListener, SensorEventListener {

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
    public static final String EXTRA_AZIMUTH = "azimuth";
    public static final String EXTRA_AZIMUTH_ACC = "azimuth_acc";

    private static final long BROADCAST_INTERVAL_MS = 200; // 5 Hz

    public interface TetherListener {
        void onStateChanged(boolean running);
        void onLocationUpdated(Location location, long packetsSent);
        void onAzimuthUpdated(float azimuth, float azimuthAcc);
    }

    private final IBinder binder = new LocalBinder();
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private LocationManager locationManager;
    private SensorManager sensorManager;
    private Sensor rotationSensor;
    private ScheduledExecutorService tickerExecutor;
    private PowerManager.WakeLock wakeLock;
    private GpsBroadcaster broadcaster;
    private volatile boolean isRunning = false;
    private Location lastLocation = null;
    private TetherListener listener = null;

    private volatile float currentAzimuth = -1.0f;
    private volatile float currentAzimuthAccuracy = -1.0f;
    private volatile float currentDeclination = 0.0f;
    private volatile boolean hasDeclination = false;

    public class LocalBinder extends Binder {
        public GpsTetherService getService() {
            return GpsTetherService.this;
        }
    }

    public void setListener(TetherListener listener) {
        this.listener = listener;
        if (listener != null) {
            listener.onStateChanged(isRunning);
            if (lastLocation != null) {
                listener.onLocationUpdated(lastLocation, getPacketsSent());
            }
            if (currentAzimuth >= 0.0f) {
                listener.onAzimuthUpdated(currentAzimuth, currentAzimuthAccuracy);
            }
        }
    }

    public void removeListener() {
        this.listener = null;
    }

    @Override
    public void onCreate() {
        super.onCreate();
        locationManager = (LocationManager) getSystemService(Context.LOCATION_SERVICE);
        sensorManager = (SensorManager) getSystemService(Context.SENSOR_SERVICE);
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
    public synchronized void startTethering(int port) {
        if (isRunning) return;
        isRunning = true;

        if (wakeLock != null && !wakeLock.isHeld()) {
            wakeLock.acquire(12 * 60 * 60 * 1000L); // Fino a 12 ore continuo in auto
        }

        broadcaster = new GpsBroadcaster(port);
        broadcaster.start();

        Notification notification = buildNotification("In attesa di segnale GPS satellitare...");
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION);
        } else {
            startForeground(NOTIFICATION_ID, notification);
        }

        // 1. Registra sensore di rotazione per bussola compensata da tilt
        registerSensorListener();

        // 2. Controlla subito se c'è un'ultima posizione nota nella cache di sistema
        queryAndEmitLastKnownLocation();

        // 3. Registra tutti i provider disponibili per massima reattività
        registerLocationListeners();

        // 4. Avvia ticker di trasmissione a 5 Hz (trasmette azimut anche da fermi riusando l'ultimo fix)
        startBroadcastTicker();

        // Notifica listener dello stato attivo
        notifyStateChanged(true);

        Log.i(TAG, "GpsTetherService avviato su porta " + port);
    }

    private void registerSensorListener() {
        if (sensorManager == null) return;
        rotationSensor = sensorManager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR);
        if (rotationSensor == null) {
            rotationSensor = sensorManager.getDefaultSensor(Sensor.TYPE_GEOMAGNETIC_ROTATION_VECTOR);
        }
        if (rotationSensor != null) {
            sensorManager.registerListener(this, rotationSensor, SensorManager.SENSOR_DELAY_UI);
            Log.i(TAG, "Sensore rotazione registrato: " + rotationSensor.getName());
        } else {
            Log.w(TAG, "Nessun sensore di rotazione disponibile sul dispositivo");
        }
    }

    private void unregisterSensorListener() {
        if (sensorManager != null) {
            try {
                sensorManager.unregisterListener(this);
            } catch (Exception ignored) {}
        }
    }

    private synchronized void startBroadcastTicker() {
        stopBroadcastTicker();
        tickerExecutor = Executors.newSingleThreadScheduledExecutor();
        tickerExecutor.scheduleAtFixedRate(this::broadcastTick, 0, BROADCAST_INTERVAL_MS, TimeUnit.MILLISECONDS);
    }

    private synchronized void stopBroadcastTicker() {
        if (tickerExecutor != null) {
            tickerExecutor.shutdownNow();
            tickerExecutor = null;
        }
    }

    private void broadcastTick() {
        if (!isRunning) return;
        Location loc = lastLocation;
        if (loc == null || broadcaster == null) return;

        broadcaster.broadcastLocation(loc, currentAzimuth, currentAzimuthAccuracy);
    }

    @Override
    public void onSensorChanged(SensorEvent event) {
        if (event == null || event.values == null) return;
        int type = event.sensor.getType();
        if (type == Sensor.TYPE_ROTATION_VECTOR || type == Sensor.TYPE_GEOMAGNETIC_ROTATION_VECTOR) {
            float[] rotationMatrix = new float[9];
            SensorManager.getRotationMatrixFromVector(rotationMatrix, event.values);

            float[] orientationValues = new float[3];
            SensorManager.getOrientation(rotationMatrix, orientationValues);

            // orientationValues[0] è l'azimut in radianti [-PI, PI] (0 = Nord, PI/2 = Est)
            double azDeg = Math.toDegrees(orientationValues[0]);
            azDeg = (azDeg + 360.0) % 360.0;

            // Correzione Nord Vero con declinazione magnetica se la posizione GPS è nota
            if (hasDeclination) {
                azDeg = (azDeg + currentDeclination + 360.0) % 360.0;
            }

            float accuracyDeg = -1.0f;
            if (event.values.length > 4 && event.values[4] > 0) {
                accuracyDeg = (float) Math.toDegrees(event.values[4]);
            } else {
                switch (event.accuracy) {
                    case SensorManager.SENSOR_STATUS_ACCURACY_HIGH:
                        accuracyDeg = 5.0f;
                        break;
                    case SensorManager.SENSOR_STATUS_ACCURACY_MEDIUM:
                        accuracyDeg = 10.0f;
                        break;
                    case SensorManager.SENSOR_STATUS_ACCURACY_LOW:
                        accuracyDeg = 25.0f;
                        break;
                    case SensorManager.SENSOR_STATUS_UNRELIABLE:
                    default:
                        accuracyDeg = -1.0f;
                        break;
                }
            }

            currentAzimuth = (float) azDeg;
            currentAzimuthAccuracy = accuracyDeg;

            if (listener != null) {
                final float finalAz = currentAzimuth;
                final float finalAcc = currentAzimuthAccuracy;
                mainHandler.post(() -> {
                    if (listener != null) {
                        listener.onAzimuthUpdated(finalAz, finalAcc);
                    }
                });
            }
        }
    }

    @Override
    public void onAccuracyChanged(Sensor sensor, int accuracy) {}

    private void updateDeclination(Location loc) {
        if (loc == null) return;
        try {
            GeomagneticField field = new GeomagneticField(
                    (float) loc.getLatitude(),
                    (float) loc.getLongitude(),
                    (float) loc.getAltitude(),
                    loc.getTime() > 0 ? loc.getTime() : System.currentTimeMillis()
            );
            currentDeclination = field.getDeclination();
            hasDeclination = true;
            Log.d(TAG, "Declinazione magnetica aggiornata: " + currentDeclination + "°");
        } catch (Exception e) {
            Log.w(TAG, "Errore calcolo GeomagneticField: " + e.getMessage());
        }
    }

    @SuppressLint("MissingPermission")
    private void queryAndEmitLastKnownLocation() {
        if (locationManager == null) return;
        try {
            Location best = null;
            List<String> providers = locationManager.getAllProviders();
            for (String provider : providers) {
                try {
                    Location l = locationManager.getLastKnownLocation(provider);
                    if (l != null) {
                        if (best == null || l.getTime() > best.getTime() || (l.hasAccuracy() && l.getAccuracy() < best.getAccuracy())) {
                            best = l;
                        }
                    }
                } catch (Exception ignored) {}
            }
            if (best != null) {
                Log.i(TAG, "Trovata ultima posizione nota (" + best.getProvider() + "): " + best.getLatitude() + ", " + best.getLongitude());
                onLocationChanged(best);
            }
        } catch (Exception e) {
            Log.w(TAG, "Errore recupero lastKnownLocation: " + e.getMessage());
        }
    }

    @SuppressLint("MissingPermission")
    private void registerLocationListeners() {
        if (locationManager == null) return;
        try {
            // GPS Provider (satellitare di precisione - unico provider affidabile per navigazione auto)
            if (locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                locationManager.requestLocationUpdates(LocationManager.GPS_PROVIDER, 500, 0.0f, this);
            }
            // Fused Provider su Android 12+ (API 31+) se disponibile
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (locationManager.getAllProviders().contains("fused")) {
                    locationManager.requestLocationUpdates("fused", 500, 0.0f, this);
                }
            }
            Log.i(TAG, "LocationListeners registrati (solo GPS satellitare ad alta precisione)");
        } catch (Exception e) {
            Log.e(TAG, "Errore registrazione LocationManager: " + e.getMessage());
        }
    }

    public synchronized void stopTethering() {
        if (!isRunning) return;
        isRunning = false;

        stopBroadcastTicker();
        unregisterSensorListener();

        try {
            if (locationManager != null) {
                locationManager.removeUpdates(this);
            }
        } catch (Exception ignored) {}

        if (broadcaster != null) {
            broadcaster.stop();
            broadcaster = null;
        }

        if (wakeLock != null && wakeLock.isHeld()) {
            wakeLock.release();
        }

        currentAzimuth = -1.0f;
        currentAzimuthAccuracy = -1.0f;

        stopForeground(true);
        notifyStateChanged(false);
        stopSelf();
        Log.i(TAG, "GpsTetherService arrestato");
    }

    @Override
    public void onLocationChanged(Location loc) {
        if (loc == null) return;

        // FILTRO ANTI-CELLE E ANTI-SPIKE:
        // 1. Scarta categoricamente posizioni da celle telefoniche/Wi-Fi che generano salti di 500-1000m
        if (LocationManager.NETWORK_PROVIDER.equals(loc.getProvider())) {
            return;
        }
        // 2. Scarta fix con accuratezza peggiore di 30 metri o coordinate non valide
        if (loc.hasAccuracy() && loc.getAccuracy() > 30.0f) {
            return;
        }
        if (loc.getLatitude() == 0.0 && loc.getLongitude() == 0.0) {
            return;
        }

        lastLocation = loc;
        updateDeclination(loc);

        long packets = broadcaster != null ? broadcaster.getPacketsSent() : 0;

        // Aggiorna notifica persistente
        double speedKmh = loc.getSpeed() * 3.6;
        String statusText;
        if (currentAzimuth >= 0.0f) {
            statusText = String.format(Locale.US, "Velocità: %.0f km/h • Bussola: %.0f° • Trasmessi: %d", speedKmh, currentAzimuth, packets);
        } else {
            statusText = String.format(Locale.US, "Velocità: %.0f km/h • Trasmessi: %d pacchetti", speedKmh, packets);
        }
        NotificationManager nm = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm != null && isRunning) {
            nm.notify(NOTIFICATION_ID, buildNotification(statusText));
        }

        // 1. Notifica diretta al listener (MainActivity) sul Main Thread
        if (listener != null) {
            mainHandler.post(() -> {
                if (listener != null) {
                    listener.onLocationUpdated(loc, packets);
                }
            });
        }

        // 2. Broadcast esplicito di backup (con setPackage per Android 14+)
        Intent intent = new Intent(ACTION_LOCATION_UPDATE);
        intent.setPackage(getPackageName());
        intent.putExtra(EXTRA_LAT, loc.getLatitude());
        intent.putExtra(EXTRA_LON, loc.getLongitude());
        intent.putExtra(EXTRA_SPEED, loc.getSpeed());
        intent.putExtra(EXTRA_ACCURACY, loc.getAccuracy());
        intent.putExtra(EXTRA_BEARING, loc.getBearing());
        intent.putExtra(EXTRA_PACKETS, packets);
        intent.putExtra(EXTRA_AZIMUTH, currentAzimuth);
        intent.putExtra(EXTRA_AZIMUTH_ACC, currentAzimuthAccuracy);
        sendBroadcast(intent);
    }

    private void notifyStateChanged(boolean running) {
        if (listener != null) {
            mainHandler.post(() -> {
                if (listener != null) {
                    listener.onStateChanged(running);
                }
            });
        }
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
                .setContentTitle("🛰️ GPS Tether v1.3.9 Attivo")
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
