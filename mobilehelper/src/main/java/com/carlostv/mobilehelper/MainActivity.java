package com.carlostv.mobilehelper;

import android.app.Activity;
import android.content.ComponentName;
import android.content.Intent;
import android.graphics.Color;
import android.os.Bundle;
import android.provider.Settings;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

public class MainActivity extends Activity {
    private TextView status;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(24), dp(28), dp(24), dp(24));
        root.setGravity(Gravity.TOP);
        root.setBackgroundColor(Color.WHITE);

        TextView title = new TextView(this);
        title.setText("Xuper Móvil");
        title.setTextSize(28);
        title.setTextColor(Color.BLACK);
        title.setPadding(0, 0, 0, dp(10));
        root.addView(title, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        TextView info = new TextView(this);
        info.setText("Mantiene tu Xuper original intacta y agrega un control táctil grande encima de la app. No modifica ni vuelve a firmar Xuper.");
        info.setTextSize(17);
        info.setTextColor(Color.DKGRAY);
        info.setPadding(0, 0, 0, dp(20));
        root.addView(info);

        status = new TextView(this);
        status.setTextSize(17);
        status.setPadding(0, 0, 0, dp(18));
        root.addView(status);

        Button enable = makeButton("1. Activar controles táctiles");
        enable.setOnClickListener(v -> startActivity(new Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)));
        root.addView(enable);

        Button launch = makeButton("2. Abrir Xuper");
        launch.setOnClickListener(v -> launchXuper());
        root.addView(launch);

        TextView tip = new TextView(this);
        tip.setText("Cuando Xuper esté abierta aparecerá un mando flotante con ↑ ↓ ← →, OK y Atrás. El mando se oculta automáticamente fuera de Xuper.");
        tip.setTextSize(15);
        tip.setTextColor(Color.GRAY);
        tip.setPadding(0, dp(18), 0, 0);
        root.addView(tip);

        setContentView(root);
    }

    @Override
    protected void onResume() {
        super.onResume();
        boolean enabled = isServiceEnabled();
        status.setText(enabled ? "Estado: controles ACTIVOS" : "Estado: falta activar el servicio de accesibilidad");
        status.setTextColor(enabled ? Color.rgb(0, 120, 70) : Color.rgb(180, 70, 0));
    }

    private Button makeButton(String text) {
        Button b = new Button(this);
        b.setText(text);
        b.setTextSize(18);
        b.setAllCaps(false);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(58));
        lp.bottomMargin = dp(12);
        b.setLayoutParams(lp);
        return b;
    }

    private void launchXuper() {
        Intent i = getPackageManager().getLaunchIntentForPackage("com.android.mgstv");
        if (i == null) {
            Toast.makeText(this, "No encontré Xuper (com.android.mgstv) instalada.", Toast.LENGTH_LONG).show();
            return;
        }
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        startActivity(i);
    }

    private boolean isServiceEnabled() {
        String enabled = Settings.Secure.getString(getContentResolver(), Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES);
        if (TextUtils.isEmpty(enabled)) return false;
        ComponentName target = new ComponentName(this, RemoteAccessibilityService.class);
        TextUtils.SimpleStringSplitter splitter = new TextUtils.SimpleStringSplitter(':');
        splitter.setString(enabled);
        while (splitter.hasNext()) {
            ComponentName cn = ComponentName.unflattenFromString(splitter.next());
            if (target.equals(cn)) return true;
        }
        return false;
    }

    private int dp(int v) {
        return Math.round(v * getResources().getDisplayMetrics().density);
    }
}
