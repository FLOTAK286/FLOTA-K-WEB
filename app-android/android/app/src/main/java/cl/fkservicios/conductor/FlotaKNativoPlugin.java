package cl.fkservicios.conductor;

import android.Manifest;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.PowerManager;
import android.provider.Settings;

import androidx.core.app.NotificationManagerCompat;
import androidx.core.content.ContextCompat;

import com.getcapacitor.JSObject;
import com.getcapacitor.PermissionState;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import com.getcapacitor.annotation.Permission;
import com.getcapacitor.annotation.PermissionCallback;

/**
 * Puente entre la página del conductor y Android:
 * iniciar/detener el envío de ubicación con la app cerrada, pedir "Permitir todo el tiempo",
 * batería sin restricciones y abrir el ajuste de "apps sin usar".
 */
@CapacitorPlugin(
    name = "FlotaKNativo",
    permissions = {
        @Permission(alias = "ubicacion", strings = { Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION }),
        @Permission(alias = "fondo", strings = { "android.permission.ACCESS_BACKGROUND_LOCATION" }),
        @Permission(alias = "avisos", strings = { "android.permission.POST_NOTIFICATIONS" })
    }
)
public class FlotaKNativoPlugin extends Plugin {

    // { url, anon, llave }: guarda la configuración y arranca el servicio (sigue aunque se cierre la app)
    @PluginMethod
    public void iniciarUbicacion(PluginCall call) {
        String url = call.getString("url"), anon = call.getString("anon"), llave = call.getString("llave");
        if (url == null || anon == null || llave == null || llave.length() != 64) { call.reject("Datos incompletos"); return; }
        Context c = getContext();
        c.getSharedPreferences(UbicacionService.PREFS, Context.MODE_PRIVATE).edit()
            .putString("url", url).putString("anon", anon).putString("llave", llave).putBoolean("activo", true).apply();
        if (!tieneUbicacion()) { call.reject("SIN_PERMISO"); return; }
        try { UbicacionService.iniciar(c); } catch (Exception e) { call.reject("No se pudo iniciar: " + e.getMessage()); return; }
        call.resolve(estadoObj());
    }

    // App Operaciones: { url, anon, llave } guarda la configuración y arranca los avisos con la app cerrada
    @PluginMethod
    public void iniciarAvisosEquipo(PluginCall call) {
        String url = call.getString("url"), anon = call.getString("anon"), llave = call.getString("llave");
        if (url == null || anon == null || llave == null || llave.length() != 64) { call.reject("Datos incompletos"); return; }
        Context c = getContext();
        c.getSharedPreferences(AvisosEquipoService.PREFS, Context.MODE_PRIVATE).edit()
            .putString("url", url).putString("anon", anon).putString("llave", llave).putBoolean("activo", true).apply();
        try { AvisosEquipoService.iniciar(c); } catch (Exception e) { call.reject("No se pudo iniciar: " + e.getMessage()); return; }
        call.resolve(estadoObj());
    }

    @PluginMethod
    public void detenerAvisosEquipo(PluginCall call) {
        Context c = getContext();
        c.getSharedPreferences(AvisosEquipoService.PREFS, Context.MODE_PRIVATE).edit().putBoolean("activo", false).remove("llave").apply();
        c.stopService(new Intent(c, AvisosEquipoService.class));
        call.resolve();
    }

    // Cerrar sesión: deja de enviar y borra la llave del teléfono
    @PluginMethod
    public void detenerUbicacion(PluginCall call) {
        Context c = getContext();
        c.getSharedPreferences(UbicacionService.PREFS, Context.MODE_PRIVATE).edit().putBoolean("activo", false).remove("llave").apply();
        c.stopService(new Intent(c, UbicacionService.class));
        call.resolve();
    }

    @PluginMethod
    public void estado(PluginCall call) { call.resolve(estadoObj()); }

    // 1) Ubicación "mientras se usa" y 2) "Permitir todo el tiempo" (Android lo pide en un segundo paso)
    @PluginMethod
    public void pedirUbicacion(PluginCall call) {
        if (!tieneUbicacion()) { requestPermissionForAlias("ubicacion", call, "trasUbicacion"); return; }
        pedirFondo(call);
    }

    @PermissionCallback
    private void trasUbicacion(PluginCall call) {
        if (!tieneUbicacion()) { call.resolve(estadoObj()); return; }
        pedirFondo(call);
    }

    private void pedirFondo(PluginCall call) {
        if (Build.VERSION.SDK_INT < 29 || tieneFondo()) { call.resolve(estadoObj()); return; }
        if (Build.VERSION.SDK_INT >= 30) {
            // Android 11 o más nuevo: "Permitir todo el tiempo" solo se elige en los ajustes de la app
            abrirAjustes();
            call.resolve(estadoObj());
            return;
        }
        requestPermissionForAlias("fondo", call, "trasFondo");
    }

    @PermissionCallback
    private void trasFondo(PluginCall call) { call.resolve(estadoObj()); }

    // Notificaciones (Android 13 o más nuevo las pide; si ya se negaron, se abren los ajustes)
    @PluginMethod
    public void pedirNotificaciones(PluginCall call) {
        if (notificaciones()) { call.resolve(estadoObj()); return; }
        if (Build.VERSION.SDK_INT >= 33 && getPermissionState("avisos") != PermissionState.DENIED) {
            requestPermissionForAlias("avisos", call, "trasAvisos");
            return;
        }
        try {
            Intent i = new Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, getContext().getPackageName());
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            getContext().startActivity(i);
        } catch (Exception e) { abrirAjustes(); }
        call.resolve(estadoObj());
    }

    @PermissionCallback
    private void trasAvisos(PluginCall call) {
        if (!notificaciones()) {
            try {
                Intent i = new Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, getContext().getPackageName());
                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                getContext().startActivity(i);
            } catch (Exception ignored) {}
        }
        call.resolve(estadoObj());
    }

    private boolean notificaciones() {
        try { return NotificationManagerCompat.from(getContext()).areNotificationsEnabled(); } catch (Exception e) { return true; }
    }

    // Batería sin restricciones (que Android no "duerma" la app)
    @PluginMethod
    public void pedirBateria(PluginCall call) {
        if (Build.VERSION.SDK_INT >= 23 && !bateriaLibre()) {
            try {
                Intent i = new Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:" + getContext().getPackageName()));
                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                getContext().startActivity(i);
            } catch (Exception e) {
                try {
                    Intent i = new Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS);
                    i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                    getContext().startActivity(i);
                } catch (Exception ignored) { abrirAjustes(); }
            }
        }
        call.resolve(estadoObj());
    }

    // "Administrar la app si no se usa": abre ese ajuste para desactivarlo
    @PluginMethod
    public void abrirAppsSinUsar(PluginCall call) {
        try {
            if (Build.VERSION.SDK_INT >= 30) {
                Intent i = new Intent(Intent.ACTION_AUTO_REVOKE_PERMISSIONS, Uri.parse("package:" + getContext().getPackageName()));
                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                getContext().startActivity(i);
            } else abrirAjustes();
        } catch (Exception e) { abrirAjustes(); }
        call.resolve(estadoObj());
    }

    @PluginMethod
    public void abrirAjustesApp(PluginCall call) { abrirAjustes(); call.resolve(); }

    private void abrirAjustes() {
        Intent i = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + getContext().getPackageName()));
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        getContext().startActivity(i);
    }

    private boolean tieneUbicacion() {
        return ContextCompat.checkSelfPermission(getContext(), Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
            || ContextCompat.checkSelfPermission(getContext(), Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED;
    }

    private boolean tieneFondo() {
        if (Build.VERSION.SDK_INT < 29) return tieneUbicacion();
        return ContextCompat.checkSelfPermission(getContext(), "android.permission.ACCESS_BACKGROUND_LOCATION") == PackageManager.PERMISSION_GRANTED;
    }

    private boolean bateriaLibre() {
        if (Build.VERSION.SDK_INT < 23) return true;
        PowerManager pm = (PowerManager) getContext().getSystemService(Context.POWER_SERVICE);
        return pm != null && pm.isIgnoringBatteryOptimizations(getContext().getPackageName());
    }

    private boolean appsSinUsarDesactivado() {
        if (Build.VERSION.SDK_INT < 30) return true;
        try { return getContext().getPackageManager().isAutoRevokeWhitelisted(); } catch (Exception e) { return false; }
    }

    private JSObject estadoObj() {
        JSObject o = new JSObject();
        o.put("activo", UbicacionService.activo(getContext()));
        o.put("ubicacion", tieneUbicacion());
        o.put("todoElTiempo", tieneFondo());
        o.put("bateriaLibre", bateriaLibre());
        o.put("notificaciones", notificaciones());
        o.put("appsSinUsarDesactivado", appsSinUsarDesactivado());
        o.put("ultimoEnvio", getContext().getSharedPreferences(UbicacionService.PREFS, Context.MODE_PRIVATE).getLong("ultimo_envio", 0));
        o.put("android", Build.VERSION.SDK_INT);
        o.put("equipoActivo", AvisosEquipoService.activo(getContext()));
        o.put("equipoUltimo", getContext().getSharedPreferences(AvisosEquipoService.PREFS, Context.MODE_PRIVATE).getLong("ultimo_envio", 0));
        return o;
    }
}
