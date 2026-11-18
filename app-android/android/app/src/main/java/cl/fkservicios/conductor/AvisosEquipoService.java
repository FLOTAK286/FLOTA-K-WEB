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
import android.os.Build;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.IBinder;
import android.os.PowerManager;

import androidx.core.app.NotificationCompat;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;

/**
 * App Flota-K Operaciones: avisa con sonido aunque la app esté cerrada cuando otra persona agenda una reserva,
 * un cliente cancela, un conductor no puede o un conductor toma una reserva publicada.
 * Pregunta a la central cada 60 s con la llave del teléfono, hasta que la persona cierre sesión (el servidor responde 0).
 */
public class AvisosEquipoService extends Service {
    static final String PREFS = "flotak_equipo";
    static final String CANAL_FIJO = "flotak_equipo_fijo";
    static final String CANAL_AVISOS = "flotak_equipo_avisos";
    static final int NOTIF_ID = 4322;

    private HandlerThread hilo;
    private Handler red;
    private PowerManager.WakeLock wl;
    private volatile int cadaSeg = 60;
    private boolean corriendo = false;

    static boolean activo(Context c) {
        return c.getSharedPreferences(PREFS, MODE_PRIVATE).getBoolean("activo", false);
    }

    static void iniciar(Context c) {
        Intent i = new Intent(c, AvisosEquipoService.class);
        if (Build.VERSION.SDK_INT >= 26) c.startForegroundService(i); else c.startService(i);
    }

    @Override public IBinder onBind(Intent intent) { return null; }

    @Override
    public void onCreate() {
        super.onCreate();
        hilo = new HandlerThread("flotak-equipo");
        hilo.start();
        red = new Handler(hilo.getLooper());
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (!activo(this)) { detenerTodo(); return START_NOT_STICKY; }
        try {
            if (Build.VERSION.SDK_INT >= 34) startForeground(NOTIF_ID, notificacionFija(), ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);
            else startForeground(NOTIF_ID, notificacionFija());
        } catch (Exception e) {
            stopSelf();
            return START_NOT_STICKY;
        }
        // Mantiene el procesador despierto lo justo para preguntar cada minuto (requiere "batería sin restricciones")
        try {
            if (wl == null) {
                PowerManager pm = (PowerManager) getSystemService(POWER_SERVICE);
                wl = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "flotak:avisos-equipo");
                wl.setReferenceCounted(false);
                wl.acquire();
            }
        } catch (Exception ignored) {}
        if (!corriendo) { corriendo = true; red.post(this::latido); }
        return START_STICKY;
    }

    private void latido() {
        if (!corriendo) return;
        int prox = -1;
        try {
            SharedPreferences p = getSharedPreferences(PREFS, MODE_PRIVATE);
            String url = p.getString("url", null), anon = p.getString("anon", null), llave = p.getString("llave", null);
            if (url == null || anon == null || llave == null) { detenerTodo(); return; }
            String cuerpo = "{\"p_llave\":\"" + llave.replaceAll("[^0-9a-f]", "") + "\"}";
            HttpURLConnection c = (HttpURLConnection) new URL(url + "/rest/v1/rpc/equipo_latido").openConnection();
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
                }
                p.edit().putLong("ultimo_envio", System.currentTimeMillis()).apply();
            }
            c.disconnect();
        } catch (Exception ignored) {
            // sin señal: se reintenta en el próximo latido
        }
        if (prox == 0) { detenerTodo(); return; }
        if (prox > 0) cadaSeg = Math.max(30, Math.min(prox, 300));
        if (corriendo) red.postDelayed(this::latido, cadaSeg * 1000L);
    }

    private void avisar(JSONObject a) {
        if (UbicacionService.appVisible) return; // la pantalla abierta ya avisa
        NotificationManager nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
        if (nm == null) return;
        if (Build.VERSION.SDK_INT >= 26 && nm.getNotificationChannel(CANAL_AVISOS) == null) {
            NotificationChannel ch = new NotificationChannel(CANAL_AVISOS, "Reservas y conductores", NotificationManager.IMPORTANCE_HIGH);
            ch.setDescription("Reserva nueva, cancelada por el cliente, conductor que no puede o que tomó una reserva.");
            ch.enableVibration(true);
            ch.setVibrationPattern(new long[]{0, 400, 200, 400, 200, 400});
            ch.setLockscreenVisibility(Notification.VISIBILITY_PUBLIC);
            nm.createNotificationChannel(ch);
        }
        Intent abrir = getPackageManager().getLaunchIntentForPackage(getPackageName());
        if (abrir != null) abrir.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        int id = 7000 + (int) (a.optLong("id", System.currentTimeMillis()) % 100000);
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
        try { nm.notify(id, n); } catch (Exception ignored) {}
    }

    private static String leer(InputStream is) throws java.io.IOException {
        java.io.ByteArrayOutputStream b = new java.io.ByteArrayOutputStream();
        byte[] buf = new byte[512]; int n;
        while ((n = is.read(buf)) > 0) b.write(buf, 0, n);
        return new String(b.toByteArray(), StandardCharsets.UTF_8);
    }

    private void detenerTodo() {
        corriendo = false;
        getSharedPreferences(PREFS, MODE_PRIVATE).edit().putBoolean("activo", false).remove("llave").apply();
        try { if (wl != null && wl.isHeld()) wl.release(); } catch (Exception ignored) {}
        try { if (Build.VERSION.SDK_INT >= 24) stopForeground(STOP_FOREGROUND_REMOVE); else stopForeground(true); } catch (Exception ignored) {}
        stopSelf();
    }

    private Notification notificacionFija() {
        NotificationManager nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
        if (Build.VERSION.SDK_INT >= 26 && nm.getNotificationChannel(CANAL_FIJO) == null) {
            NotificationChannel ch = new NotificationChannel(CANAL_FIJO, "Avisos activos", NotificationManager.IMPORTANCE_LOW);
            ch.setDescription("Indica que Flota-K Operaciones sigue recibiendo avisos con la app cerrada.");
            nm.createNotificationChannel(ch);
        }
        Intent abrir = getPackageManager().getLaunchIntentForPackage(getPackageName());
        PendingIntent pi = PendingIntent.getActivity(this, 0, abrir, Build.VERSION.SDK_INT >= 23 ? PendingIntent.FLAG_IMMUTABLE : 0);
        return new NotificationCompat.Builder(this, CANAL_FIJO)
                .setSmallIcon(R.drawable.ic_tracking)
                .setContentTitle("Flota-K Operaciones")
                .setContentText("Recibiendo avisos de reservas. Para detenerlo, cierre sesión en la app.")
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setContentIntent(pi)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .build();
    }

    @Override
    public void onDestroy() {
        corriendo = false;
        try { if (wl != null && wl.isHeld()) wl.release(); } catch (Exception ignored) {}
        if (hilo != null) hilo.quitSafely();
        super.onDestroy();
    }
}
