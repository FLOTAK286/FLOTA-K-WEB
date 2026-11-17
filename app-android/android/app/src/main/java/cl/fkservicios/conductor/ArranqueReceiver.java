package cl.fkservicios.conductor;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** Al encender el teléfono o actualizar la app, vuelve a enviar la ubicación si el conductor no ha cerrado sesión. */
public class ArranqueReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        String a = intent.getAction();
        if (!Intent.ACTION_BOOT_COMPLETED.equals(a) && !Intent.ACTION_MY_PACKAGE_REPLACED.equals(a)) return;
        if (!UbicacionService.activo(context)) return;
        try { UbicacionService.iniciar(context); } catch (Exception ignored) { /* se reintenta al abrir la app */ }
    }
}
