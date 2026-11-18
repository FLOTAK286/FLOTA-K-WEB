package cl.fkservicios.conductor;

import android.os.Bundle;

import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        // Puente propio: ubicación con la app cerrada, permisos "todo el tiempo", batería y apps sin usar
        registerPlugin(FlotaKNativoPlugin.class);
        super.onCreate(savedInstanceState);
    }

    // Con la app a la vista, los avisos los muestra la pantalla; cerrada o en segundo plano, el servicio
    @Override
    public void onResume() { super.onResume(); UbicacionService.appVisible = true; }

    @Override
    public void onPause() { UbicacionService.appVisible = false; super.onPause(); }
}
