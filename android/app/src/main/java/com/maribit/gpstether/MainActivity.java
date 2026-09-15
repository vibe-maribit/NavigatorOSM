package com.maribit.gpstether;

import android.Manifest;
import android.content.BroadcastReceiver;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.ServiceConnection;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.location.Location;
import android.os.Build;
import android.os.Bundle;
import android.os.IBinder;
import android.widget.Button;
import android.widget.EditText;
import android.widget.TextView;
import android.widget.Toast;

import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;

import java.util.Locale;

public class MainActivity extends AppCompatActivity implements GpsTetherService.TetherListener {

    private static final int PERMISSION_REQUEST_CODE = 100;

    private TextView tvStatus;
    private TextView tvCoordinates;
    private TextView tvSpeed;
    private TextView tvAccuracy;
    private TextView tvPackets;
    private EditText etPort;
    private Button btnToggle;

    private GpsTetherService tetherService;
    private boolean isBound = false;

    private final ServiceConnection serviceConnection = new ServiceConnection() {
        @Override
        public void onServiceConnected(ComponentName name, IBinder service) {
            GpsTetherService.LocalBinder binder = (GpsTetherService.LocalBinder) service;
            tetherService = binder.getService();
            isBound = true;
            tetherService.setListener(MainActivity.this);
            updateUIState(tetherService.isRunning());
            if (tetherService.getLastLocation() != null) {
                onLocationUpdated(tetherService.getLastLocation(), tetherService.getPacketsSent());
            }
        }

        @Override
        public void onServiceDisconnected(ComponentName name) {
            if (tetherService != null) {
                tetherService.removeListener();
            }
            tetherService = null;
            isBound = false;
            updateUIState(false);
        }
    };

    private final BroadcastReceiver locationReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            if (intent != null && GpsTetherService.ACTION_LOCATION_UPDATE.equals(intent.getAction())) {
                double lat = intent.getDoubleExtra(GpsTetherService.EXTRA_LAT, 0.0);
                double lon = intent.getDoubleExtra(GpsTetherService.EXTRA_LON, 0.0);
                float speed = intent.getFloatExtra(GpsTetherService.EXTRA_SPEED, 0.0f);
                float acc = intent.getFloatExtra(GpsTetherService.EXTRA_ACCURACY, 0.0f);
                long packets = intent.getLongExtra(GpsTetherService.EXTRA_PACKETS, 0);

                applyLocationToUI(lat, lon, speed, acc, packets);
            }
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        tvStatus = findViewById(R.id.tv_status);
        tvCoordinates = findViewById(R.id.tv_coordinates);
        tvSpeed = findViewById(R.id.tv_speed);
        tvAccuracy = findViewById(R.id.tv_accuracy);
        tvPackets = findViewById(R.id.tv_packets);
        etPort = findViewById(R.id.et_port);
        btnToggle = findViewById(R.id.btn_toggle);

        btnToggle.setOnClickListener(v -> onToggleClicked());

        checkAndRequestPermissions();
    }

    @Override
    protected void onStart() {
        super.onStart();
        Intent intent = new Intent(this, GpsTetherService.class);
        bindService(intent, serviceConnection, Context.BIND_AUTO_CREATE);

        IntentFilter filter = new IntentFilter(GpsTetherService.ACTION_LOCATION_UPDATE);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(locationReceiver, filter, Context.RECEIVER_NOT_EXPORTED);
        } else {
            registerReceiver(locationReceiver, filter);
        }
    }

    @Override
    protected void onStop() {
        super.onStop();
        try {
            unregisterReceiver(locationReceiver);
        } catch (Exception ignored) {}

        if (isBound) {
            if (tetherService != null) {
                tetherService.removeListener();
            }
            unbindService(serviceConnection);
            isBound = false;
        }
    }

    private void onToggleClicked() {
        boolean currentlyRunning = (tetherService != null && tetherService.isRunning());

        if (currentlyRunning) {
            // Arresta immediatamente
            btnToggle.setEnabled(false);
            btnToggle.setText("⏳ ARRESTO IN CORSO...");
            if (tetherService != null) {
                tetherService.stopTethering();
            }
            Intent intent = new Intent(this, GpsTetherService.class);
            stopService(intent);
            updateUIState(false);
        } else {
            // Avvia immediatamente
            if (!hasPermissions()) {
                checkAndRequestPermissions();
                return;
            }

            int port = 8888;
            try {
                port = Integer.parseInt(etPort.getText().toString().trim());
            } catch (Exception ignored) {}

            btnToggle.setEnabled(false);
            btnToggle.setText("⏳ AVVIO IN CORSO...");

            Intent intent = new Intent(this, GpsTetherService.class);
            intent.putExtra("port", port);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent);
            } else {
                startService(intent);
            }

            // Se il servizio è già bound, avvialo anche direttamente
            if (tetherService != null) {
                tetherService.startTethering(port);
            }

            updateUIState(true);
        }
    }

    @Override
    public void onStateChanged(boolean running) {
        runOnUiThread(() -> updateUIState(running));
    }

    @Override
    public void onLocationUpdated(Location location, long packetsSent) {
        if (location == null) return;
        runOnUiThread(() -> applyLocationToUI(
                location.getLatitude(),
                location.getLongitude(),
                location.getSpeed(),
                location.getAccuracy(),
                packetsSent
        ));
    }

    private void applyLocationToUI(double lat, double lon, float speed, float acc, long packets) {
        tvCoordinates.setText(String.format(Locale.US, "%.5f, %.5f", lat, lon));
        tvSpeed.setText(String.format(Locale.US, "%.0f km/h", speed * 3.6f));
        tvAccuracy.setText(acc > 0 ? String.format(Locale.US, "±%.1f m", acc) : "±-- m");
        tvPackets.setText(String.valueOf(packets));
    }

    private void updateUIState(boolean isRunning) {
        btnToggle.setEnabled(true);
        if (isRunning) {
            String portStr = etPort.getText().toString().trim();
            tvStatus.setText("🟢 TRASMISSIONE ATTIVA\n(UDP Broadcast porta " + portStr + " + Server TCP)");
            tvStatus.setTextColor(Color.parseColor("#00E676"));
            btnToggle.setText("⏹ ARRESTA TRASMISSIONE");
            btnToggle.setBackgroundColor(Color.parseColor("#D50000"));
            etPort.setEnabled(false);
        } else {
            tvStatus.setText("⚪ TRASMISSIONE FERMA\nAttiva Hotspot e premi AVVIA");
            tvStatus.setTextColor(Color.parseColor("#B0BEC5"));
            btnToggle.setText("▶ AVVIA TRASMISSIONE");
            btnToggle.setBackgroundColor(Color.parseColor("#00C853"));
            etPort.setEnabled(true);
        }
    }

    private boolean hasPermissions() {
        boolean fineLoc = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED;
        boolean coarseLoc = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED;
        return fineLoc || coarseLoc;
    }

    private void checkAndRequestPermissions() {
        if (!hasPermissions()) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                ActivityCompat.requestPermissions(this,
                        new String[]{
                                Manifest.permission.ACCESS_FINE_LOCATION,
                                Manifest.permission.ACCESS_COARSE_LOCATION,
                                Manifest.permission.POST_NOTIFICATIONS
                        },
                        PERMISSION_REQUEST_CODE);
            } else {
                ActivityCompat.requestPermissions(this,
                        new String[]{
                                Manifest.permission.ACCESS_FINE_LOCATION,
                                Manifest.permission.ACCESS_COARSE_LOCATION
                        },
                        PERMISSION_REQUEST_CODE);
            }
        }
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, @NonNull String[] permissions, @NonNull int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == PERMISSION_REQUEST_CODE) {
            if (grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                Toast.makeText(this, "Permessi GPS concessi!", Toast.LENGTH_SHORT).show();
            } else if (hasPermissions()) {
                Toast.makeText(this, "Posizione approssimativa concessa.", Toast.LENGTH_SHORT).show();
            } else {
                Toast.makeText(this, "Permesso GPS necessario per il tethering!", Toast.LENGTH_LONG).show();
            }
        }
    }
}
