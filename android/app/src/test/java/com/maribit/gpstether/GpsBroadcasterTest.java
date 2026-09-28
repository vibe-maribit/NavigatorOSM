package com.maribit.gpstether;

import org.json.JSONObject;
import org.junit.Test;

import static org.junit.Assert.*;

public class GpsBroadcasterTest {

    @Test
    public void testBuildJsonPayloadWithAzimuth() throws Exception {
        double lat = 45.464211;
        double lon = 9.189982;
        float speed = 0.0f;
        float bearing = -1.0f;
        double alt = 120.0;
        float acc = 4.0f;
        float azimuth = 87.5f;
        float azimuthAcc = 10.0f;
        long time = 1790000000000L;

        String json = GpsBroadcaster.buildJsonPayload(lat, lon, speed, bearing, alt, acc, azimuth, azimuthAcc, time);
        assertNotNull(json);
        assertTrue(json.endsWith("\n"));

        JSONObject obj = new JSONObject(json.trim());
        assertEquals(45.464211, obj.getDouble("lat"), 0.000001);
        assertEquals(9.189982, obj.getDouble("lon"), 0.000001);
        assertEquals(0.0, obj.getDouble("speed"), 0.01);
        assertEquals(-1.0, obj.getDouble("bearing"), 0.1);
        assertEquals(120.0, obj.getDouble("alt"), 0.1);
        assertEquals(4.0, obj.getDouble("acc"), 0.1);
        assertEquals(1790000000000L, obj.getLong("time"));
        assertTrue(obj.has("azimuth"));
        assertTrue(obj.has("azimuthAcc"));
        assertEquals(87.5, obj.getDouble("azimuth"), 0.1);
        assertEquals(10.0, obj.getDouble("azimuthAcc"), 0.1);
    }

    @Test
    public void testBuildJsonPayloadWithoutAzimuth() throws Exception {
        double lat = 45.464211;
        double lon = 9.189982;
        float speed = 13.5f;
        float bearing = 90.0f;
        double alt = 100.0;
        float acc = 3.5f;
        float azimuth = -1.0f;
        float azimuthAcc = -1.0f;
        long time = 1790000000000L;

        String json = GpsBroadcaster.buildJsonPayload(lat, lon, speed, bearing, alt, acc, azimuth, azimuthAcc, time);
        assertNotNull(json);

        JSONObject obj = new JSONObject(json.trim());
        assertEquals(45.464211, obj.getDouble("lat"), 0.000001);
        assertEquals(9.189982, obj.getDouble("lon"), 0.000001);
        assertEquals(13.5, obj.getDouble("speed"), 0.01);
        assertEquals(90.0, obj.getDouble("bearing"), 0.1);
        assertFalse(obj.has("azimuth"));
        assertFalse(obj.has("azimuthAcc"));
    }

    @Test
    public void testNullLocationReturnsNull() {
        assertNull(GpsBroadcaster.buildJsonPayload(null, 90.0f, 5.0f, System.currentTimeMillis()));
    }
}
