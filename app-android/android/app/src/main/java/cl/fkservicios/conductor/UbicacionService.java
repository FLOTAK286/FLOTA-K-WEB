package cl.fkservicios.conductor;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.ServiceInfo;
import android.location.Location;
import android.os.Build;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.IBinder;
import android.os.Looper;

import androidx.core.app.NotificationCompat;

import com.google.android.gms.location.FusedLocationProviderClient;
import com.google.android.gms.location.LocationCallback;
import com.google.android.gms.location.LocationRequest;
import com.google.android.gms.location.LocationResult;
import com.google.android.gms.location.LocationServices;
import com.google.android.gms.location.Priority;

import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.Locale;

import org.json.JSONArray;
import org.json.JSONObject;

/**
 * Envía la ubicación del conductor a Flota-K aunque la app esté cerrada.
 * Sigue funcionando hasta que el conductor cierre sesión (la llave del teléfono se anula y el servidor responde 0).
 * El servidor indica cada cuántos segundos enviar: 15 en servicio, 30 conectado, 60 desconectado.
 * En cada envío el servidor entrega los avisos pendientes (servicio nuevo, quitado, cancelado o modificado):
 * si la app no está a la vista, suenan como notificación aunque la app esté cerrada.
 */
public class UbicacionService extends Service {
    static final String PREFS = "flotak_ubicacion";
    static final String CANAL = "flotak_ubicacion";
    static final int NOTIF_ID = 4321;
    static final String CANAL_AVISOS = "flotak_servicios";
    static volatile boolean appVisible = false;

    private FusedLocationProviderClient cliente;
    private LocationCallback callback;
    private HandlerThread hilo;
    private Handler red;
    private volatile int cadaSeg = 30;
    private volatile long ultimoEnvio = 0;
    private volatile boolean enviando = false;

    static boolean activo(Context c) {
        return c.getSharedPreferences(PREFS, MODE_PRIVATE).getBoolean("activo", false);
    }

    static void iniciar(Context c) {
        Intent i = new Intent(c, UbicacionService.class);
        if (Build.VERSION.SDK_INT >= 26) c.startForegroundService(i); else c.startService(i);
    }

    @Override public IBinder onBind(Intent intent) { return null; }

    @Override
    public void onCreate() {
        super.onCreate();
        hilo = new HandlerThread("flotak-ubicacion");
        hilo.start();
        red = new Handler(hilo.getLooper());
        cliente = LocationServices.getFusedLocationProviderClient(this);
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (!activo(this)) { detenerTodo(); return START_NOT_STICKY; }
        Notification n = notificacion();
        try {
            if (Build.VERSION.SDK_INT >= 29) startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION);
            else startForeground(NOTIF_ID, n);
        } catch (Exception e) {
            // Sin permiso de ubicación (o Android no deja iniciar desde segundo plano): se intenta de nuevo al abrir la app
            stopSelf();
            return START_NOT_STICKY;
        }
        pedirUbicaciones();
        return START_STICKY; // si Android cierra el servicio, lo vuelve a abrir solo
    }

    @Override
    public void onTaskRemoved(Intent rootIntent) {
        // El conductor cerró la app desde "apps recientes": el servicio sigue enviando la ubicación
        super.onTaskRemoved(rootIntent);
    }

    private void pedirUbicaciones() {
        try {
            if (callback != null) cliente.removeLocationUpdates(callback);
            long ms = Math.max(10, Math.min(cadaSeg, 300)) * 1000L;
            LocationRequest req = new LocationRequest.Builder(cadaSeg <= 15 ? Priority.PRIORITY_HIGH_ACCURACY : Priority.PRIORITY_BALANCED_POWER_ACCURACY, ms)
                    .setMinUpdateIntervalMillis(Math.min(ms, 10000L))
                    .setMaxUpdateDelayMillis(ms)
                    .build();
            callback = new LocationCallback() {
                @Override public void onLocationResult(LocationResult r) {
                    Location l = r.getLastLocation();
                    if (l != null) enviar(l);
                }
            };
            cliente.requestLocationUpdates(req, callback, hilo.getLooper());
        } catch (SecurityException e) {
            stopSelf();
        }
    }

    private void enviar(final Location l) {
        long ahora = System.currentTimeMillis();
        if (enviando || ahora - ultimoEnvio < (cadaSeg * 1000L) - 3000L) return;
        enviando = true;
        red.post(() -> {
            int prox = -1;
            try {
                SharedPreferences p = getSharedPreferences(PREFS, MODE_PRIVATE);
                String url = p.getString("url", null), anon = p.getString("anon", null), llave = p.getString("llave", null);
                if (url == null || anon == null || llave == null) { detenerTodo(); return; }
                String cuerpo = String.format(Locale.US,
                        "{\"p_llave\":\"%s\",\"p_lat\":%.6f,\"p_lng\":%.6f,\"p_precision\":%d,\"p_rumbo\":%s,\"p_velocidad\":%s}",
                        llave.replaceAll("[^0-9a-f]", ""), l.getLatitude(), l.getLongitude(), Math.round(l.getAccuracy()),
                        l.hasBearing() ? String.valueOf(Math.round(l.getBearing())) : "null",
                        l.hasSpeed() ? String.valueOf(Math.round(l.getSpeed() * 3.6f)) : "null");
                HttpURLConnection c = (HttpURLConnection) new URL(url + "/rest/v1/rpc/conductor_latido").openConnection();
                c.setConnectTimeout(15000); c.setReadTimeout(15000);
                c.setRequestMethod("POST"); c.setDoOutput(true);
                c.setRequestProperty("Content-Type", "application/json");
                c.setRequestProperty("apikey", anon);
                c.setRequestProperty("Authorization", "Bearer " + anon);
                try (OutputStream os = c.getOutputStream()) { os.write(cuerpo.getBytes(StandardCharsets.UTF_8)); }
                int st = c.getResponseCode();
                if (st >= 200 && st < 300) {
                    try (InputStream is = c.getInputStream()) {
                        JSONObject r = new JSONObject(leer(is).trim());
                        prox = r.optInt("cada", cadaSeg);
                        JSONArray av = r.optJSONArray("avisos");
                        if (av != null) for (int i = Math.max(0, av.length() - 5); i < av.length(); i++) avisar(av.getJSONObject(i));
                    } catch (Exception ignored) { prox = cadaSeg; }
                    ultimoEnvio = System.currentTimeMillis();
                    p.edit().putLong("ultimo_envio", ultimoEnvio).apply();
                }
                c.disconnect();
            } catch (Exception ignored) {
                // sin señal: se reintenta con la próxima ubicación
            } finally {
                enviando = false;
            }
            if (prox == 0) { detenerTodo(); return; }   // cerró sesión o lo dieron de baja
            if (prox > 0 && prox != cadaSeg) {
                cadaSeg = prox;
                new Handler(Looper.getMainLooper()).post(this::pedirUbicaciones);
            }
        });
    }

    // Notificación con sonido y vibración (servicio nuevo, quitado, cancelado o modificado)
    private void avisar(JSONObject a) {
        if (appVisible) return; // la pantalla abierta ya avisa con su propio sonido
        NotificationManager nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
        if (nm == null) return;
        if (Build.VERSION.SDK_INT >= 26 && nm.getNotificationChannel(CANAL_AVISOS) == null) {
            NotificationChannel ch = new NotificationChannel(CANAL_AVISOS, "Servicios de la central", NotificationManager.IMPORTANCE_HIGH);
            ch.setDescription("Servicio nuevo, cancelado, cambiado o quitado, aunque la app esté cerrada.");
            ch.enableVibration(true);
            ch.setVibrationPattern(new long[]{0, 400, 200, 400, 200, 400});
            ch.setLockscreenVisibility(Notification.VISIBILITY_PUBLIC);
            nm.createNotificationChannel(ch);
        }
        Intent abrir = getPackageManager().getLaunchIntentForPackage(getPackageName());
        if (abrir != null) abrir.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        int id = 5000 + (int) (a.optLong("id", System.currentTimeMillis()) % 100000);
        PendingIntent pi = PendingIntent.getActivity(this, id, abrir, Build.VERSION.SDK_INT >= 23 ? PendingIntent.FLAG_IMMUTABLE : 0);
        String texto = a.optString("texto", "");
        Notification n = new NotificationCompat.Builder(this, CANAL_AVISOS)
                .setSmallIcon(R.drawable.ic_tracking)
                .setContentTitle(a.optString("titulo", "Flota-K"))
                .setContentText(texto)
                .setStyle(new NotificationCompat.BigTextStyle().bigText(texto))
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_MESSAGE)
                .setDefaults(NotificationCompat.DEFAULT_SOUND)
                .setVibrate(new long[]{0, 400, 200, 400, 200, 400})
                .setAutoCancel(true)
                .setContentIntent(pi)
                .build();
        try { nm.notify(id, n); } catch (Exception ignored) { /* sin permiso de notificaciones */ }
    }

    private static String leer(InputStream is) throws java.io.IOException {
        java.io.ByteArrayOutputStream b = new java.io.ByteArrayOutputStream();
        byte[] buf = new byte[512]; int n;
        while ((n = is.read(buf)) > 0) b.write(buf, 0, n);
        return new String(b.toByteArray(), StandardCharsets.UTF_8);
    }

    private void detenerTodo() {
        getSharedPreferences(PREFS, MODE_PRIVATE).edit().putBoolean("activo", false).remove("llave").apply();
        try { if (callback != null) cliente.removeLocationUpdates(callback); } catch (Exception ignored) {}
        try { if (Build.VERSION.SDK_INT >= 24) stopForeground(STOP_FOREGROUND_REMOVE); else stopForeground(true); } catch (Exception ignored) {}
        stopSelf();
    }

    private Notification notificacion() {
        NotificationManager nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
        if (Build.VERSION.SDK_INT >= 26 && nm.getNotificationChannel(CANAL) == null) {
            NotificationChannel ch = new NotificationChannel(CANAL, "Ubicación para la central", NotificationManager.IMPORTANCE_LOW);
            ch.setDescription("Flota-K comparte su ubicación con la central mientras tenga la sesión iniciada.");
            nm.createNotificationChannel(ch);
        }
        Intent abrir = getPackageManager().getLaunchIntentForPackage(getPackageName());
        PendingIntent pi = PendingIntent.getActivity(this, 0, abrir, Build.VERSION.SDK_INT >= 23 ? PendingIntent.FLAG_IMMUTABLE : 0);
        return new NotificationCompat.Builder(this, CANAL)
                .setSmallIcon(R.drawable.ic_tracking)
                .setContentTitle("Flota-K Conductor")
                .setContentText("Compartiendo su ubicación con la central. Para detenerlo, cierre sesión en la app.")
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setContentIntent(pi)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .build();
    }

    @Override
    public void onDestroy() {
        try { if (callback != null) cliente.removeLocationUpdates(callback); } catch (Exception ignored) {}
        if (hilo != null) hilo.quitSafely();
        super.onDestroy();
    }
}
