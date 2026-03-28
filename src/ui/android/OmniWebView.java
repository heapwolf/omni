
package com.omni;

import android.annotation.SuppressLint;
import android.content.Context;
import android.graphics.Bitmap;
import android.webkit.JavascriptInterface;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

public class OmniWebView extends WebView {

    // Mirrored in WebView+Android.swift.
    public static final int EVENT_TITLE    = 0;
    public static final int EVENT_STARTED  = 1;
    public static final int EVENT_FINISHED = 2;
    public static final int EVENT_ERROR    = 3;
    public static final int EVENT_MESSAGE  = 4;

    /// The Swift WebEventHandler as a pointer. Zero until setSwiftHandle runs.
    private long swiftHandle = 0;

    /// Returns true to cancel, matching NavigationPolicy.cancel.
    public static native boolean dispatchWebPolicy(long ptr, String url);
    public static native void dispatchWebEvent(long ptr, int kind, String value);
    public static native void dispatchWebState(long ptr, int progress, boolean canGoBack, boolean canGoForward);

    @SuppressLint("SetJavaScriptEnabled")
    public OmniWebView(Context context) {
        super(context);

        WebSettings settings = getSettings();
        settings.setJavaScriptEnabled(true);
        // Hosted payment and identity flows need it.
        settings.setDomStorageEnabled(true);
        settings.setLoadWithOverviewMode(true);
        settings.setUseWideViewPort(true);

        // window.omni.postMessage(value), the same call on every backend.
        addJavascriptInterface(new MessageBridge(), "omni");

        setWebViewClient(new Client());
        setWebChromeClient(new Chrome());
    }

    public void setSwiftHandle(long handle) {
        this.swiftHandle = handle;
    }

    /// evaluateJavascript takes a ValueCallback; passing null through raw JNI means
    /// a signature for a type the bridge never otherwise touches.
    public void evaluate(String source) {
        evaluateJavascript(source, null);
    }

    public void loadHTML(String html, String baseURL) {
        loadDataWithBaseURL(baseURL, html, "text/html", "utf-8", null);
    }

    private void reportState() {
        if (swiftHandle == 0) return;
        dispatchWebState(swiftHandle, getProgress(), canGoBack(), canGoForward());
    }

    private final class Client extends WebViewClient {
        @Override
        public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
            if (swiftHandle == 0) return false;
            return dispatchWebPolicy(swiftHandle, request.getUrl().toString());
        }

        @Override
        public void onPageStarted(WebView view, String url, Bitmap favicon) {
            if (swiftHandle == 0) return;
            dispatchWebEvent(swiftHandle, EVENT_STARTED, url);
            reportState();
        }

        @Override
        public void onPageFinished(WebView view, String url) {
            if (swiftHandle == 0) return;
            dispatchWebEvent(swiftHandle, EVENT_FINISHED, url);
            reportState();
        }

        /// Subresource failures arrive here too; only the main frame is a page failure.
        @Override
        public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
            if (swiftHandle == 0 || !request.isForMainFrame()) return;
            dispatchWebEvent(swiftHandle, EVENT_ERROR, String.valueOf(error.getDescription()));
        }
    }

    private final class Chrome extends WebChromeClient {
        @Override
        public void onReceivedTitle(WebView view, String title) {
            if (swiftHandle == 0) return;
            dispatchWebEvent(swiftHandle, EVENT_TITLE, title);
        }

        @Override
        public void onProgressChanged(WebView view, int newProgress) {
            reportState();
        }
    }

    private final class MessageBridge {
        @JavascriptInterface
        public void postMessage(final String value) {
            post(new Runnable() {
                @Override public void run() {
                    if (swiftHandle == 0) return;
                    dispatchWebEvent(swiftHandle, EVENT_MESSAGE, value);
                }
            });
        }
    }
}
