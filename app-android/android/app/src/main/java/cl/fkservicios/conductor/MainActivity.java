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
}
