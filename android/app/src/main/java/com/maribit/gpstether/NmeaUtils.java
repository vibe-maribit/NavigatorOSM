package com.maribit.gpstether;

import android.location.Location;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.TimeZone;

public class NmeaUtils {

    private static final SimpleDateFormat TIME_FMT = new SimpleDateFormat("HHmmss.SS", Locale.US);
    private static final SimpleDateFormat DATE_FMT = new SimpleDateFormat("ddMMyy", Locale.US);

    static {
        TIME_FMT.setTimeZone(TimeZone.getTimeZone("UTC"));
        DATE_FMT.setTimeZone(TimeZone.getTimeZone("UTC"));
    }

    public static String formatGPRMC(Location loc) {
        Date now = new Date(loc.getTime());
        String timeStr = TIME_FMT.format(now);
        String dateStr = DATE_FMT.format(now);

        double lat = loc.getLatitude();
        String latDir = lat >= 0 ? "N" : "S";
        lat = Math.abs(lat);
        int latDeg = (int) lat;
        double latMin = (lat - latDeg) * 60.0;
        String latStr = String.format(Locale.US, "%02d%07.4f", latDeg, latMin);

        double lon = loc.getLongitude();
        String lonDir = lon >= 0 ? "E" : "W";
        lon = Math.abs(lon);
        int lonDeg = (int) lon;
        double lonMin = (lon - lonDeg) * 60.0;
        String lonStr = String.format(Locale.US, "%03d%07.4f", lonDeg, lonMin);

        double speedKnots = loc.getSpeed() * 1.943844; // m/s to knots
        double bearing = loc.getBearing();

        String raw = String.format(Locale.US, "GPRMC,%s,A,%s,%s,%s,%s,%.2f,%.2f,%s,,,A",
                timeStr, latStr, latDir, lonStr, lonDir, speedKnots, bearing, dateStr);

        int checksum = calculateChecksum(raw);
        return "$" + raw + "*" + String.format(Locale.US, "%02X", checksum) + "\r\n";
    }

    private static int calculateChecksum(String sentence) {
        int checksum = 0;
        for (int i = 0; i < sentence.length(); i++) {
            checksum ^= sentence.charAt(i);
        }
        return checksum;
    }
}
