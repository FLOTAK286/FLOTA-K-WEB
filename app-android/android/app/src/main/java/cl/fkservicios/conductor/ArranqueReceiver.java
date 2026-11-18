package cl.fkservicios.conductor;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** Al encender el teléfono o actualizar la app, vuelve a enviar la ubicación (conductor) o a recibir avisos (operaciones) si no se ha cerrado sesión. */
public class ArranqueReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        String a = intent.getAction();
        if (!Intent.ACTION_BOOT_COMPLETED.equals(a) && !Intent.ACTION_MY_PACKAGE_REPLACED.equals(a)) return;
        if (UbicacionService.activo(context)) {
            try { UbicacionService.iniciar(context); } catch (Exception ignored) { /* se reintenta al abrir la app */ }
        }
        if (AvisosEquipoService.activo(context)) {
            try { AvisosEquipoService.iniciar(context); } catch (Exception ignored) { /* se reintenta al abrir la app */ }
        }
    }
}
