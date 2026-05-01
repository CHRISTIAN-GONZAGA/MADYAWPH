package com.gloretto.hotelhms;

import android.os.Bundle;
import android.webkit.CookieManager;
import android.webkit.WebView;

import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        CookieManager cookieManager = CookieManager.getInstance();
        cookieManager.setAcceptCookie(true);

        WebView webView = this.bridge != null ? this.bridge.getWebView() : null;
        if (webView != null) {
            cookieManager.setAcceptThirdPartyCookies(webView, true);
        }
    }
}
