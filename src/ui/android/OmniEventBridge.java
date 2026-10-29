// src/lib/android/Events+Android.java
package com.omni;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.Dialog;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.provider.MediaStore;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import android.view.View;
import android.view.ViewOutlineProvider;
import android.view.GestureDetector;
import android.view.MotionEvent;
import android.view.VelocityTracker;
import android.view.ViewGroup;
import android.widget.HorizontalScrollView;
import android.widget.ScrollView;
import android.widget.ArrayAdapter;
import android.widget.AdapterView;
import android.widget.CompoundButton;
import android.widget.EditText;
import android.widget.SeekBar;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.Spinner;
import android.widget.TextView;
import android.content.Context;
import android.text.InputType;
import android.text.method.PasswordTransformationMethod;
import android.text.Editable;
import android.text.TextWatcher;
import android.graphics.drawable.GradientDrawable;
import android.graphics.Outline;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Typeface;
import java.io.File;
import java.util.HashMap;
import android.graphics.Path;
import android.util.Log;
import android.view.ViewGroup;
import android.transition.AutoTransition;
import android.transition.Slide;
import android.transition.TransitionSet;
import android.transition.Visibility;
import android.transition.Transition;
import android.transition.TransitionManager;
import android.view.Gravity;
import android.view.animation.AccelerateInterpolator;
import android.view.animation.AccelerateDecelerateInterpolator;
import android.view.animation.DecelerateInterpolator;
import android.view.animation.LinearInterpolator;

import java.util.ArrayList;
import java.util.List;

public class OmniEventBridge {

    // Nothing else drains libdispatch's main queue on Android.
    private static final Handler mainHandler = new Handler(Looper.getMainLooper());
    private static boolean pumpRunning = false;

    /// ~a frame.
    private static final long PUMP_INTERVAL_MS = 8;

    private static final Runnable pump = new Runnable() {
        @Override public void run() {
            drainMainQueue();
            mainHandler.postDelayed(this, PUMP_INTERVAL_MS);
        }
    };

    /// Called once from native init. Idempotent.
    public static void startMainQueuePump() {
        if (pumpRunning) return;
        pumpRunning = true;
        mainHandler.post(pump);
    }

    /// Runs whatever Swift has queued on the main actor. Main thread only; the
    /// Handler guarantees it.
    public static native void drainMainQueue();

    public static native void dispatchVoid(long ptr);
    public static native void dispatchBool(long ptr, boolean val);
    public static native void dispatchInt(long ptr, int val);
    public static native void dispatchFloat(long ptr, float val);
    public static native void dispatchString(long ptr, String val);
    public static native void dispatchFloat2(long ptr, float val1, float val2);

    public static native void dispatchDeepLink(String url);

    /// Called from MainActivity's onCreate and onNewIntent. An intent with no data
    /// is an ordinary launch.
    public static void deliverIntent(Intent intent) {
        if (intent == null || intent.getData() == null) return;
        dispatchDeepLink(intent.getData().toString());
    }

    /// AppLifecycle: MainActivity's onStart (true) and onStop (false).
    public static native void dispatchLifecycle(boolean foreground);
    /// Interactions' activity: MainActivity's dispatchTouchEvent, for each
    /// finger going down.
    public static native void dispatchActivity();
    /// Engine.safeArea: the status bar's and the navigation bar's heights, in dp.
    public static native void dispatchSafeArea(float top, float bottom);
    /// Appearance: the system's light or dark changed (MainActivity handles uiMode itself).
    public static native void dispatchAppearance();

    /// The system's dark mode, for Appearance when the app follows the system.
    /// The app's scheme (Appearance.current), which may differ from the system's.
    static boolean darkScheme;

    public static void setDarkScheme(boolean dark) {
        if (dark == darkScheme) return;
        darkScheme = dark;
        if (rootHost != null) rootHost.requestLayout();
    }

    public static boolean isNightMode(Context context) {
        int mode = context.getResources().getConfiguration().uiMode
            & android.content.res.Configuration.UI_MODE_NIGHT_MASK;
        return mode == android.content.res.Configuration.UI_MODE_NIGHT_YES;
    }

    /// Keyboard.dismiss: the keyboard goes, and the focused field loses focus.
    public static void dismissKeyboard() {
        if (hostActivity == null) return;
        View focused = hostActivity.getCurrentFocus();
        if (focused == null) return;
        android.view.inputmethod.InputMethodManager keyboard =
            (android.view.inputmethod.InputMethodManager) hostActivity
                .getSystemService(Context.INPUT_METHOD_SERVICE);
        if (keyboard != null) keyboard.hideSoftInputFromWindow(focused.getWindowToken(), 0);
        focused.clearFocus();
    }

    /// Keyboard.coversContent: the keyboard covers the root instead of the
    /// root's padding taking its height.
    private static boolean keyboardCovers = false;

    public static void setKeyboardCovers(boolean covers) {
        if (keyboardCovers == covers) return;
        keyboardCovers = covers;
        if (hostActivity != null) {
            hostActivity.getWindow().setSoftInputMode(covers
                ? android.view.WindowManager.LayoutParams.SOFT_INPUT_ADJUST_NOTHING
                : android.view.WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);
        }
        if (rootHost != null) rootHost.requestApplyInsets();
    }

    public static native void dispatchCameraPermissionResult(long ptr, boolean granted);
    public static native void dispatchCameraActivityResult(long ptr, boolean ok, String uri);

    public static void attachOnClick(View view, long ptr) {
        view.setOnClickListener(v -> dispatchVoid(ptr));
    }

    /// A press as Android's own buttons track one: down, out past the touch
    /// slop and back, up inside, or cancelled when a scrolling parent takes the
    /// touch. Sends 1 pressed, 0 not, 2 released inside. TalkBack's activate
    /// is a click, so that is a release inside too.
    public static void attachOnPress(View view, long ptr) {
        final int slop = android.view.ViewConfiguration.get(view.getContext()).getScaledTouchSlop();
        view.setClickable(true);
        view.setOnClickListener(v -> dispatchInt(ptr, 2));
        view.setOnTouchListener(new View.OnTouchListener() {
            private boolean inside;

            private boolean within(View v, MotionEvent e) {
                return e.getX() >= -slop && e.getY() >= -slop
                    && e.getX() <= v.getWidth() + slop && e.getY() <= v.getHeight() + slop;
            }

            @Override
            public boolean onTouch(View v, MotionEvent e) {
                switch (e.getActionMasked()) {
                    case MotionEvent.ACTION_DOWN:
                        inside = true;
                        dispatchInt(ptr, 1);
                        return true;
                    case MotionEvent.ACTION_MOVE: {
                        boolean now = within(v, e);
                        if (now != inside) {
                            inside = now;
                            dispatchInt(ptr, now ? 1 : 0);
                        }
                        return true;
                    }
                    case MotionEvent.ACTION_UP: {
                        boolean released = inside && within(v, e);
                        inside = false;
                        dispatchInt(ptr, released ? 2 : 0);
                        return true;
                    }
                    case MotionEvent.ACTION_CANCEL:
                        if (inside) {
                            inside = false;
                            dispatchInt(ptr, 0);
                        }
                        return true;
                    default:
                        return false;
                }
            }
        });
    }

    public static void attachOnChecked(CompoundButton view, long ptr) {
        view.setOnCheckedChangeListener((v, isChecked) -> dispatchBool(ptr, isChecked));
    }

    // Each field's watcher, so unmounting can take it off: the Swift handler it
    // points at is released then.
    private static final java.util.WeakHashMap<EditText, TextWatcher> WATCHERS = new java.util.WeakHashMap<>();

    public static void attachTextWatcher(EditText view, long ptr) {
        TextWatcher watcher = new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int start, int count, int after) {}
            @Override public void afterTextChanged(Editable s) {}
            @Override public void onTextChanged(CharSequence s, int start, int before, int count) {
                dispatchString(ptr, s.toString());
            }
        };
        view.addTextChangedListener(watcher);
        WATCHERS.put(view, watcher);
    }

    /// A field's focus, told to Swift as it comes and goes (its .focused binding).
    public static void attachFocusChange(View view, long ptr) {
        view.setOnFocusChangeListener((v, hasFocus) -> dispatchBool(ptr, hasFocus));
    }

    /// .focused set from Swift: the field takes focus and the keyboard, or gives both up.
    public static void focusField(final View view, boolean focus) {
        android.view.inputmethod.InputMethodManager keyboard =
            (android.view.inputmethod.InputMethodManager) view.getContext()
                .getSystemService(Context.INPUT_METHOD_SERVICE);
        if (focus) {
            view.post(() -> {
                view.requestFocus();
                if (keyboard != null) keyboard.showSoftInput(view, 0);
            });
        } else if (view.hasFocus()) {
            if (keyboard != null) keyboard.hideSoftInputFromWindow(view.getWindowToken(), 0);
            view.clearFocus();
        }
    }

    /// A finger down outside the focused field gives up its focus and the keyboard, as
    /// a tap away does on iOS. Not for a touch on another field, which takes the focus.
    static void blurOnTouchOutside(View root, MotionEvent e) {
        if (e.getActionMasked() != MotionEvent.ACTION_DOWN) return;
        View focused = root.findFocus();
        if (!(focused instanceof EditText)) return;
        android.graphics.Rect bounds = new android.graphics.Rect();
        focused.getGlobalVisibleRect(bounds);
        int x = (int) e.getRawX(), y = (int) e.getRawY();
        if (bounds.contains(x, y) || fieldAt(root, x, y)) return;
        focusField(focused, false);
    }

    private static boolean fieldAt(View view, int x, int y) {
        if (view.getVisibility() != View.VISIBLE) return false;
        android.graphics.Rect bounds = new android.graphics.Rect();
        if (!view.getGlobalVisibleRect(bounds) || !bounds.contains(x, y)) return false;
        if (view instanceof EditText) return true;
        if (view instanceof ViewGroup) {
            ViewGroup group = (ViewGroup) view;
            for (int i = 0; i < group.getChildCount(); i++) if (fieldAt(group.getChildAt(i), x, y)) return true;
        }
        return false;
    }

    /// A field leaving the screen: no more text reaches Swift, and if it had the
    /// keyboard, the keyboard goes. Otherwise it stays up, bound to a view that
    /// is gone, with that view's keyboard type.
    public static void detachTextField(EditText view) {
        TextWatcher watcher = WATCHERS.remove(view);
        if (watcher != null) view.removeTextChangedListener(watcher);
        if (view.hasFocus()) {
            android.view.inputmethod.InputMethodManager keyboard =
                (android.view.inputmethod.InputMethodManager) view.getContext()
                    .getSystemService(Context.INPUT_METHOD_SERVICE);
            if (keyboard != null) keyboard.hideSoftInputFromWindow(view.getWindowToken(), 0);
            view.clearFocus();
        }
    }

    public static void attachOnSeekBarChange(SeekBar view, long ptr) {
        view.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override public void onProgressChanged(SeekBar sb, int progress, boolean fromUser) {
                // Only on user drags, not programmatic updates.
                if (fromUser) dispatchFloat(ptr, (float) progress);
            }
            @Override public void onStartTrackingTouch(SeekBar sb) {}
            @Override public void onStopTrackingTouch(SeekBar sb) {}
        });
    }

    public static void attachOnItemSelected(AdapterView<?> view, long ptr) {
        view.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener() {
            @Override public void onItemSelected(AdapterView<?> parent, View v, int position, long id) {
                dispatchInt(ptr, position);
            }
            @Override public void onNothingSelected(AdapterView<?> parent) {}
        });
    }

    /// Pixels back to the dp Swift lays out in: sizes and positions go out as dp
    /// (JNIBridge's omni_jni_px), so the ones that come back must too.
    static float dp(View view, float px) {
        return px / view.getResources().getDisplayMetrics().density;
    }

    public static void attachOnScrollChange(View view, long ptr) {
        view.setOnScrollChangeListener((v, scrollX, scrollY, oldScrollX, oldScrollY) -> {
            dispatchFloat2(ptr, dp(v, scrollX), dp(v, scrollY));
        });
    }

    /// Presents `content` as a bottom sheet: full width, on the bottom edge, its
    /// top corners rounded. A plain Dialog floats in the middle at its content's
    /// width. Returns the dialog so Swift can dismiss it.
    ///
    /// `fraction` of the screen's height, or `heightDp` when it is positive. A
    /// large sheet stops short of the top, as on iOS.
    /// A sheet's surface: clipped to a rounded rectangle whose bottom corners lie
    /// below it, so only the top ones round (a path outline clipped poorly and a
    /// fringe showed at the corners), and dragged down to dismiss, as on iOS:
    /// a downward drag the content under the finger can't scroll moves the
    /// sheet; let go past a quarter of it, or flung, it goes.
    static final class SheetHost extends android.widget.FrameLayout {
        Dialog dialog;
        boolean isDismissable;
        private final float radius;
        private final int slop;
        private float downX, downY, lastY;
        private boolean dragging;
        private VelocityTracker tracker;

        SheetHost(Context context, float radius) {
            super(context);
            this.radius = radius;
            this.slop = android.view.ViewConfiguration.get(context).getScaledTouchSlop();
            setOutlineProvider(new ViewOutlineProvider() {
                @Override public void getOutline(View view, Outline outline) {
                    outline.setRoundRect(0, 0, view.getWidth(), view.getHeight() + Math.round(SheetHost.this.radius),
                                         SheetHost.this.radius);
                }
            });
            setClipToOutline(true);
        }

        /// The content's own background, found down its first views, for the strip under
        /// the navigation bar: the sheet's default colour there made a band of another shade
        /// below a screen that paints its own.
        private static Integer backgroundOf(View view, int depth) {
            if (view == null || depth > 12) return null;
            android.graphics.drawable.Drawable drawable = view.getBackground();
            if (drawable instanceof android.graphics.drawable.ColorDrawable) {
                int color = ((android.graphics.drawable.ColorDrawable) drawable).getColor();
                if (Color.alpha(color) == 255) return color;
            } else if (drawable instanceof GradientDrawable && ((GradientDrawable) drawable).getColor() != null) {
                int color = ((GradientDrawable) drawable).getColor().getDefaultColor();
                if (Color.alpha(color) == 255) return color;
            }
            if (view instanceof ViewGroup && ((ViewGroup) view).getChildCount() > 0) {
                return backgroundOf(((ViewGroup) view).getChildAt(0), depth + 1);
            }
            return null;
        }

        /// Debug builds: the sheet's tree too, a second after it settles (its window isn't the root's).
        private final Runnable settledDump = () -> {
            android.util.Log.i("OmniLayout", "sheet:");
            dumpTree(this);
        };

        @Override protected void onLayout(boolean changed, int l, int t, int r, int b) {
            super.onLayout(changed, l, t, r, b);
            removeCallbacks(settledDump);
            postDelayed(settledDump, 1000);
            Integer color = getChildCount() > 0 ? backgroundOf(getChildAt(0), 0) : null;
            if (color != null) {
                android.graphics.drawable.Drawable mine = getBackground();
                if (!(mine instanceof android.graphics.drawable.ColorDrawable)
                        || ((android.graphics.drawable.ColorDrawable) mine).getColor() != color) {
                    setBackgroundColor(color);
                }
            }
        }

        /// Whether something under (x, y) would scroll up, so the drag is its.
        private static boolean scrollsUp(View view, float x, float y) {
            if (x < view.getLeft() || x >= view.getRight() || y < view.getTop() || y >= view.getBottom()) return false;
            if (view.canScrollVertically(-1)) return true;
            if (view instanceof ViewGroup) {
                ViewGroup group = (ViewGroup) view;
                float cx = x - view.getLeft() + view.getScrollX(), cy = y - view.getTop() + view.getScrollY();
                for (int i = group.getChildCount() - 1; i >= 0; i--) {
                    if (scrollsUp(group.getChildAt(i), cx, cy)) return true;
                }
            }
            return false;
        }

        private void track(MotionEvent e) {
            if (e.getActionMasked() == MotionEvent.ACTION_DOWN) {
                if (tracker != null) tracker.recycle();
                tracker = VelocityTracker.obtain();
            }
            if (tracker != null) {
                MotionEvent raw = MotionEvent.obtain(e);
                raw.setLocation(e.getRawX(), e.getRawY());
                tracker.addMovement(raw);
                raw.recycle();
            }
        }

        @Override public boolean dispatchTouchEvent(MotionEvent e) {
            blurOnTouchOutside(this, e);
            return super.dispatchTouchEvent(e);
        }

        @Override public boolean onInterceptTouchEvent(MotionEvent e) {
            if (!isDismissable) return false;
            track(e);
            switch (e.getActionMasked()) {
                case MotionEvent.ACTION_DOWN:
                    downX = e.getRawX(); downY = e.getRawY(); lastY = downY; dragging = false;
                    return false;
                case MotionEvent.ACTION_MOVE:
                    float dy = e.getRawY() - downY, dx = e.getRawX() - downX;
                    if (dy > slop && dy > Math.abs(dx) * 1.5f && !scrollsUp(getChildAt(0), e.getX(), e.getY())) {
                        dragging = true;
                        lastY = e.getRawY();
                        return true;
                    }
                    return false;
                default:
                    return false;
            }
        }

        @Override public boolean onTouchEvent(MotionEvent e) {
            if (!isDismissable) return false;
            track(e);
            switch (e.getActionMasked()) {
                case MotionEvent.ACTION_DOWN:
                    downX = e.getRawX(); downY = e.getRawY(); lastY = downY;
                    return true;
                case MotionEvent.ACTION_MOVE:
                    if (!dragging && e.getRawY() - downY > slop) dragging = true;
                    if (dragging) setTranslationY(Math.max(0, getTranslationY() + e.getRawY() - lastY));
                    lastY = e.getRawY();
                    return true;
                case MotionEvent.ACTION_UP:
                case MotionEvent.ACTION_CANCEL:
                    float velocity = 0;
                    if (tracker != null) {
                        tracker.computeCurrentVelocity(1000);
                        velocity = tracker.getYVelocity();
                        tracker.recycle();
                        tracker = null;
                    }
                    float fling = 1000 * getResources().getDisplayMetrics().density;
                    boolean goes = dragging && (getTranslationY() > getHeight() * 0.25f || velocity > fling);
                    dragging = false;
                    if (goes) {
                        animate().translationY(getHeight()).setDuration(180).withEndAction(() -> {
                            if (dialog != null) dialog.dismiss();
                        }).start();
                    } else {
                        animate().translationY(0).setDuration(200).start();
                    }
                    return true;
                default:
                    return true;
            }
        }
    }

    /// A sheet's content replaced by `content`: its root's native changed (a screen
    /// pushed inside it). Without this the sheet kept the old view, detached, and
    /// showed nothing. The grab indicator stays on top.
    public static void setSheetContent(Dialog dialog, View content) {
        if (dialog == null || dialog.getWindow() == null) return;
        SheetHost host = findSheetHost(dialog.getWindow().getDecorView());
        if (host == null || (host.getChildCount() > 0 && host.getChildAt(0) == content)) return;
        Log.i("OmniLayout", "sheet content replaced");
        if (content.getParent() instanceof ViewGroup) ((ViewGroup) content.getParent()).removeView(content);
        if (host.getChildCount() > 0) host.removeViewAt(0);
        host.addView(content, 0, new android.widget.FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
    }

    private static SheetHost findSheetHost(View view) {
        if (view instanceof SheetHost) return (SheetHost) view;
        if (view instanceof ViewGroup) {
            ViewGroup group = (ViewGroup) view;
            for (int i = 0; i < group.getChildCount(); i++) {
                SheetHost found = findSheetHost(group.getChildAt(i));
                if (found != null) return found;
            }
        }
        return null;
    }

    public static Dialog presentSheet(View content, long onDismissPtr, float fraction,
                                      float heightDp, float cornerRadiusDp,
                                      boolean showsIndicator, boolean isDismissable, int surfaceColor) {
        Log.i("OmniLayout", "sheet presented");
        Context ctx = content.getContext();
        float density = ctx.getResources().getDisplayMetrics().density;
        int screen = ctx.getResources().getDisplayMetrics().heightPixels;

        Dialog dialog = new Dialog(ctx);
        dialog.requestWindowFeature(android.view.Window.FEATURE_NO_TITLE);

        float radius = cornerRadiusDp * density;
        // The scheme's sheet colour, from Swift: white behind dark content was the fringe.
        SheetHost host = new SheetHost(ctx, radius);
        host.setBackgroundColor(surfaceColor);
        host.dialog = dialog;
        host.isDismissable = isDismissable;
        // Clear of the navigation bar, and of the keyboard when it's up: the dialog's
        // window is edge to edge, so the sheet's last row (a keypad's 0) was under the bar.
        host.setOnApplyWindowInsetsListener((v, insets) -> {
            int bottom;
            if (android.os.Build.VERSION.SDK_INT >= 30) {
                bottom = insets.getInsets(android.view.WindowInsets.Type.systemBars()
                    | android.view.WindowInsets.Type.ime()).bottom;
            } else {
                bottom = insets.getSystemWindowInsetBottom();
            }
            v.setPadding(0, 0, 0, bottom);
            return insets;
        });
        host.addView(content, new android.widget.FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));

        if (showsIndicator) {
            // Over the content, as on iOS; the content leaves room for it.
            GradientDrawable pill = new GradientDrawable();
            pill.setColor(0x4D3C3C43);
            pill.setCornerRadius(2.5f * density);
            View indicator = new View(ctx);
            indicator.setBackground(pill);
            android.widget.FrameLayout.LayoutParams params = new android.widget.FrameLayout.LayoutParams(
                Math.round(36 * density), Math.round(5 * density),
                Gravity.TOP | Gravity.CENTER_HORIZONTAL);
            params.topMargin = Math.round(5 * density);
            host.addView(indicator, params);
        }

        dialog.setContentView(host);
        dialog.setCancelable(isDismissable);
        dialog.setCanceledOnTouchOutside(isDismissable);

        android.view.Window window = dialog.getWindow();
        if (window != null) {
            int height = heightDp > 0
                ? Math.round(heightDp * density)
                : Math.round(screen * Math.min(fraction, 0.94f));
            window.setBackgroundDrawable(new android.graphics.drawable.ColorDrawable(Color.TRANSPARENT));
            // Down behind the navigation bar, as iOS's sheet goes under the home indicator:
            // fitted to the bars, the sheet stopped above it and the screen showed in a gap.
            // Its host pads its content clear of the bar (the insets listener above).
            if (android.os.Build.VERSION.SDK_INT >= 30) {
                window.setDecorFitsSystemWindows(false);
                // The window itself, not only its content: a dialog's is placed clear of the
                // bars unless it fits none of them.
                android.view.WindowManager.LayoutParams attrs = window.getAttributes();
                attrs.setFitInsetsTypes(0);
                window.setAttributes(attrs);
            } else {
                window.addFlags(android.view.WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS);
            }
            window.addFlags(android.view.WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS);
            window.setNavigationBarColor(Color.TRANSPARENT);
            if (android.os.Build.VERSION.SDK_INT >= 29) window.setNavigationBarContrastEnforced(false);
            window.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, Math.min(height, screen));
            window.setGravity(Gravity.BOTTOM);
            window.setWindowAnimations(android.R.style.Animation_InputMethod);
            window.setSoftInputMode(android.view.WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);
        }

        if (onDismissPtr != 0) {
            dialog.setOnDismissListener(d -> dispatchVoid(onDismissPtr));
        }
        dialog.show();
        return dialog;
    }

    /// An alert as SwiftUI declares it: its message, and its buttons in order,
    /// a cancel button last (AlertAction.shown). titles are separated by U+001F;
    /// roles is a character a button: '0' none, '1' destructive, '2' cancel.
    /// Sends the chosen button's index, or -1 for a dismissal that chose none.
    /// The cancel button is the dialog's own; up to two more are its buttons,
    /// and more than that a list. Back and a tap outside count as cancel, and
    /// only when there is one: iOS has no other way out of an alert.
    public static Dialog presentAlert(View anchor, String title, String message, String titles,
                                      String roles, final long choicePtr) {
        final String[] names = titles.isEmpty() ? new String[0] : titles.split("\u001F", -1);
        int cancel = roles.indexOf('2');
        java.util.ArrayList<Integer> others = new java.util.ArrayList<>();
        for (int i = 0; i < names.length; i++) if (i != cancel) others.add(i);

        final boolean[] answered = { false };
        final java.util.function.IntConsumer choose = index -> {
            if (answered[0]) return;
            answered[0] = true;
            dispatchInt(choicePtr, index);
        };

        AlertDialog.Builder builder = new AlertDialog.Builder(anchor.getContext()).setTitle(title);
        if (others.size() > 2) {
            // A list has no room for a message beside it: the message goes first.
            if (message != null && !message.isEmpty()) builder.setTitle(title + "\n\n" + message);
            CharSequence[] items = new CharSequence[others.size()];
            for (int i = 0; i < items.length; i++) items[i] = names[others.get(i)];
            builder.setItems(items, (d, which) -> choose.accept(others.get(which)));
        } else {
            if (message != null && !message.isEmpty()) builder.setMessage(message);
            if (others.size() > 0) builder.setPositiveButton(names[others.get(0)], (d, w) -> choose.accept(others.get(0)));
            if (others.size() > 1) builder.setNeutralButton(names[others.get(1)], (d, w) -> choose.accept(others.get(1)));
        }
        final int cancelIndex = cancel;
        if (cancelIndex >= 0) builder.setNegativeButton(names[cancelIndex], (d, w) -> choose.accept(cancelIndex));

        AlertDialog dialog = builder.create();
        dialog.setCancelable(cancelIndex >= 0);
        dialog.setCanceledOnTouchOutside(cancelIndex >= 0);
        dialog.setOnCancelListener(d -> choose.accept(cancelIndex));
        dialog.setOnDismissListener(d -> choose.accept(-1));
        dialog.show();

        // A destructive button in red, as iOS draws it.
        int[] slots = { AlertDialog.BUTTON_POSITIVE, AlertDialog.BUTTON_NEUTRAL };
        for (int i = 0; i < Math.min(others.size(), 2) && others.size() <= 2; i++) {
            if (roles.charAt(others.get(i)) == '1') {
                android.widget.Button button = dialog.getButton(slots[i]);
                if (button != null) button.setTextColor(0xFFB3261E);
            }
        }
        return dialog;
    }

    public static void dismissDialog(Dialog dialog) {
        Log.i("OmniLayout", "dialog dismissed");
        if (dialog != null && dialog.isShowing()) {
            dialog.dismiss();
        }
    }

    public static void attachOnLayoutChange(View view, long ptr) {
        view.addOnLayoutChangeListener((v, left, top, right, bottom,
                                        oldLeft, oldTop, oldRight, oldBottom) -> {
            dispatchFloat2(ptr, dp(v, right - left), dp(v, bottom - top));
        });
    }

    public static void attachFrameGestures(View view, long tapPtr, long tapLocPtr, long dragPtr, long dragEndPtr, long scrollPtr) {
        final boolean[] dragging = {false};
        final VelocityTracker[] tracker = {null};
        final GestureDetector detector = new GestureDetector(view.getContext(), new GestureDetector.SimpleOnGestureListener() {
            @Override
            public boolean onSingleTapUp(MotionEvent e) {
                if (tapPtr != 0) dispatchVoid(tapPtr);
                if (tapLocPtr != 0) dispatchFloat2(tapLocPtr, dp(view, e.getX()), dp(view, e.getY()));
                return (tapPtr != 0 || tapLocPtr != 0);
            }

            @Override
            public boolean onScroll(MotionEvent e1, MotionEvent e2, float distanceX, float distanceY) {
                if (dragPtr != 0) {
                    // A sideways drag is this view's: a pager or scroll view holding it
                    // mustn't take it over partway.
                    if (!dragging[0] && Math.abs(distanceX) > Math.abs(distanceY) && view.getParent() != null) {
                        view.getParent().requestDisallowInterceptTouchEvent(true);
                    }
                    dragging[0] = true;
                    dispatchFloat2(dragPtr, dp(view, -distanceX), dp(view, -distanceY));
                    return true;
                }
                return false;
            }
        });

        view.setOnTouchListener((v, event) -> {
            if (dragPtr != 0) {
                if (event.getActionMasked() == MotionEvent.ACTION_DOWN) {
                    dragging[0] = false;
                    if (tracker[0] != null) tracker[0].recycle();
                    tracker[0] = VelocityTracker.obtain();
                }
                // Raw coordinates: the view may move under the finger as it's dragged.
                MotionEvent raw = MotionEvent.obtain(event);
                raw.setLocation(event.getRawX(), event.getRawY());
                if (tracker[0] != null) tracker[0].addMovement(raw);
                raw.recycle();
            }

            boolean handled = detector.onTouchEvent(event);

            int action = event.getActionMasked();
            if ((action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_CANCEL) && tracker[0] != null) {
                tracker[0].computeCurrentVelocity(1000);
                float vx = tracker[0].getXVelocity(), vy = tracker[0].getYVelocity();
                tracker[0].recycle();
                tracker[0] = null;
                if (dragging[0] && dragEndPtr != 0) dispatchFloat2(dragEndPtr, dp(view, vx), dp(view, vy));
                dragging[0] = false;
            }

            if (event.getAction() == MotionEvent.ACTION_SCROLL && scrollPtr != 0) {
                float hScroll = event.getAxisValue(MotionEvent.AXIS_HSCROLL);
                float vScroll = event.getAxisValue(MotionEvent.AXIS_VSCROLL);
                dispatchFloat2(scrollPtr, hScroll, vScroll);
                handled = true;
            }

            return handled || (tapPtr != 0 || tapLocPtr != 0 || dragPtr != 0 || scrollPtr != 0);
        });
    }

    /// A scroll view's paging, its stillness, and its sizes for Swift's
    /// onScrollGeometryChange. Paged, letting go settles on the nearest page,
    /// carried to the next by a fling, and tells `pagePtr` of it; `showPage`
    /// slides to one set from code.
    static final class Paging {
        final ViewGroup view;
        final boolean horizontal;
        long pagePtr, sizePtr, contentPtr;
        boolean paging, disabled;
        int shown = -1, pending = -1;
        VelocityTracker tracker;

        Paging(ViewGroup view, boolean horizontal) { this.view = view; this.horizontal = horizontal; }

        int length() { return horizontal ? view.getWidth() : view.getHeight(); }
        int offset() { return horizontal ? view.getScrollX() : view.getScrollY(); }

        int count() {
            int length = length();
            if (view.getChildCount() == 0 || length == 0) return 1;
            View content = view.getChildAt(0);
            int extent = horizontal ? content.getWidth() : content.getHeight();
            return Math.max(1, Math.round((float) extent / length));
        }

        void scroll(int page, boolean animated) {
            int to = page * length();
            // Content not yet as long as the page needs (its pages unsized on the first layout): the
            // scroll would clamp short of it, so it waits for a layout where it reaches.
            View content = view.getChildCount() > 0 ? view.getChildAt(0) : null;
            int extent = content == null ? 0 : horizontal ? content.getWidth() : content.getHeight();
            if (page > 0 && extent < to + length()) { pending = page; return; }
            int x = horizontal ? to : 0, y = horizontal ? 0 : to;
            if (!animated) { view.scrollTo(x, y); return; }
            if (horizontal) ((HorizontalScrollView) view).smoothScrollTo(x, y);
            else ((ScrollView) view).smoothScrollTo(x, y);
        }

        void show(int page) {
            if (length() == 0) { pending = page; return; }
            if (page == shown) return;
            boolean first = shown < 0;
            shown = page;
            scroll(page, !first);
        }

        /// Every event, before the scroll view or a child sees it.
        void track(MotionEvent e) {
            if (!paging) return;
            if (e.getActionMasked() == MotionEvent.ACTION_DOWN) {
                if (tracker != null) tracker.recycle();
                tracker = VelocityTracker.obtain();
            }
            if (tracker != null) tracker.addMovement(e);
        }

        /// The scroll view's own onTouchEvent; `superTouch` is its super's.
        /// True when it's handled here.
        boolean touch(MotionEvent e, java.util.function.Predicate<MotionEvent> superTouch) {
            if (disabled) return true;
            int action = e.getActionMasked();
            if (!paging || (action != MotionEvent.ACTION_UP && action != MotionEvent.ACTION_CANCEL)) {
                return superTouch.test(e);
            }
            float velocity = 0;
            if (tracker != null) {
                tracker.computeCurrentVelocity(1000);
                velocity = horizontal ? tracker.getXVelocity() : tracker.getYVelocity();
                tracker.recycle();
                tracker = null;
            }
            // The scroll view lets go without a fling of its own; this settles it.
            MotionEvent cancel = MotionEvent.obtain(e);
            cancel.setAction(MotionEvent.ACTION_CANCEL);
            superTouch.test(cancel);
            cancel.recycle();
            settle(velocity);
            return true;
        }

        void settle(float velocity) {
            int length = length();
            if (length == 0) return;
            float at = (float) offset() / length;
            int target = Math.round(at);
            float fling = 400 * view.getResources().getDisplayMetrics().density;
            if (Math.abs(velocity) > fling) {
                target = velocity < 0 ? (int) Math.floor(at) + 1 : (int) Math.ceil(at) - 1;
            }
            target = Math.max(0, Math.min(count() - 1, target));
            scroll(target, true);
            if (target != shown) {
                shown = target;
                if (pagePtr != 0) dispatchInt(pagePtr, target);
                Log.i("OmniLayout", "settled on page " + target + " at " + dp(view, offset()));
                dumpTree(view.getRootView());
            }
        }

        /// PageScrubber.move: the pages moved by `pages` of a page, at once.
        void scrub(float pages) {
            int length = length();
            if (length == 0 || view.getChildCount() == 0) return;
            View content = view.getChildAt(0);
            int farthest = Math.max((horizontal ? content.getWidth() : content.getHeight()) - length, 0);
            int next = Math.max(0, Math.min(farthest, Math.round(offset() + pages * length)));
            view.scrollTo(horizontal ? next : 0, horizontal ? 0 : next);
        }

        /// PageScrubber.release, at `velocity` pages a second: the nearest page a
        /// fifth of a second's travel on, slid to, and told once it's there, as iOS.
        void releaseScrub(float velocity) {
            int length = length();
            if (length == 0) return;
            float at = (float) offset() / length + velocity * 0.2f;
            go(Math.max(0, Math.min(count() - 1, Math.round(at))));
        }

        /// PageScrubber.go, and a release: slides to `page`, telling it once there.
        /// Told at once, the app's render for the new page held the slide's start.
        void go(final int page) {
            if (length() == 0) return;
            scroll(page, true);
            view.postDelayed(() -> {
                if (page != shown) {
                    shown = page;
                    if (pagePtr != 0) dispatchInt(pagePtr, page);
                }
            }, 280);
        }

        /// After a layout: a page asked for before there was a size, the page
        /// kept through a new size, and the sizes told to Swift.
        void laidOut(boolean resized) {
            if (length() == 0) return;
            if (pending >= 0) {
                int page = pending;
                pending = -1;
                shown = page;
                scroll(page, false);
            } else if (paging && resized && shown >= 0) {
                scroll(shown, false);
            }
            if (sizePtr != 0) dispatchFloat2(sizePtr, dp(view, view.getWidth()), dp(view, view.getHeight()));
            if (contentPtr != 0 && view.getChildCount() > 0) {
                View content = view.getChildAt(0);
                dispatchFloat2(contentPtr, dp(view, content.getWidth()), dp(view, content.getHeight()));
            }
        }
    }

    public static class OmniHorizontalScrollView extends HorizontalScrollView {
        final Paging paging = new Paging(this, true);
        public OmniHorizontalScrollView(Context context) { super(context); }

        @Override public boolean dispatchTouchEvent(MotionEvent e) { paging.track(e); return super.dispatchTouchEvent(e); }
        @Override public boolean onInterceptTouchEvent(MotionEvent e) { return !paging.disabled && super.onInterceptTouchEvent(e); }
        @Override public boolean onTouchEvent(MotionEvent e) { return paging.touch(e, super::onTouchEvent); }
        @Override protected void onLayout(boolean changed, int l, int t, int r, int b) {
            int before = getWidth();
            super.onLayout(changed, l, t, r, b);
            paging.laidOut(changed && before != r - l);
        }
    }

    public static class OmniVerticalScrollView extends ScrollView {
        final Paging paging = new Paging(this, false);
        public OmniVerticalScrollView(Context context) { super(context); }

        @Override public boolean dispatchTouchEvent(MotionEvent e) { paging.track(e); return super.dispatchTouchEvent(e); }
        @Override public boolean onInterceptTouchEvent(MotionEvent e) { return !paging.disabled && super.onInterceptTouchEvent(e); }
        @Override public boolean onTouchEvent(MotionEvent e) { return paging.touch(e, super::onTouchEvent); }
        @Override protected void onLayout(boolean changed, int l, int t, int r, int b) {
            int before = getHeight();
            super.onLayout(changed, l, t, r, b);
            paging.laidOut(changed && before != b - t);
        }
    }

    private static Paging paging(View view) {
        if (view instanceof OmniHorizontalScrollView) return ((OmniHorizontalScrollView) view).paging;
        if (view instanceof OmniVerticalScrollView) return ((OmniVerticalScrollView) view).paging;
        return null;
    }

    public static void setScrollBehavior(View view, boolean paged, boolean disabled, long pagePtr) {
        Paging paging = paging(view);
        if (paging == null) return;
        paging.paging = paged;
        paging.disabled = disabled;
        paging.pagePtr = pagePtr;
    }

    public static void scrubPages(View view, float pages) {
        Paging paging = paging(view);
        if (paging != null) paging.scrub(pages);
    }

    public static void releaseScrub(View view, float velocity) {
        Paging paging = paging(view);
        if (paging != null) paging.releaseScrub(velocity);
    }

    public static void goToPage(View view, int page) {
        Paging paging = paging(view);
        if (paging != null) paging.go(page);
    }

    public static void showPage(View view, int page) {
        Paging paging = paging(view);
        if (paging != null) paging.show(page);
    }

    /// The scroll view's size and its content's, in dp, after each layout.
    public static void attachScrollSizes(View view, long sizePtr, long contentPtr) {
        Paging paging = paging(view);
        if (paging == null) return;
        paging.sizePtr = sizePtr;
        paging.contentPtr = contentPtr;
    }


    private static final java.util.Map<String, String> SYMBOL_NAMES = new java.util.HashMap<>();
    static {
        SYMBOL_NAMES.put("star", "btn_star_big_off");
        SYMBOL_NAMES.put("star.fill", "btn_star_big_on");
        SYMBOL_NAMES.put("gear", "ic_menu_preferences");
        SYMBOL_NAMES.put("gearshape", "ic_menu_preferences");
        SYMBOL_NAMES.put("magnifyingglass", "ic_menu_search");
        SYMBOL_NAMES.put("person", "sym_contact_card");
        SYMBOL_NAMES.put("person.crop.circle", "sym_contact_card");
        SYMBOL_NAMES.put("envelope", "sym_action_email");
        SYMBOL_NAMES.put("square.and.pencil", "ic_menu_edit");
        SYMBOL_NAMES.put("trash", "ic_menu_delete");
        SYMBOL_NAMES.put("plus", "ic_menu_add");
        SYMBOL_NAMES.put("chevron.left", "ic_media_previous");
        SYMBOL_NAMES.put("chevron.right", "ic_media_next");
    }

    /// The edge a system icon is drawn at, in dp. An unbounded ImageView takes the
    /// drawable's intrinsic size and grows the row holding it.
    private static final int SYMBOL_SIZE_DP = 24;

    private static android.animation.TimeInterpolator interpolator(int curve) {
        if (curve >= 1000) return spring((curve - 1000) / 1000.0);
        switch (curve) {
            case 1:  return new AccelerateInterpolator();          // easeIn
            case 2:  return new DecelerateInterpolator();          // easeOut
            case 3:  return new AccelerateDecelerateInterpolator(); // easeInOut
            default: return new LinearInterpolator();
        }
    }

    /// A damped spring from rest, over its settling time: Animation.spring
    /// makes the duration six time constants (settlingTimeConstants), so
    /// damping alone fixes the shape. Divided by its value at the end, so it
    /// lands on 1 exactly rather than snapping the last of the way.
    private static android.animation.TimeInterpolator spring(final double damping) {
        final double zeta = Math.max(0.01, Math.min(damping, 1.0));
        final double constants = 6.0;
        final double end = springAt(1.0, zeta, constants);
        return fraction -> (float) (springAt(fraction, zeta, constants) / end);
    }

    private static double springAt(double fraction, double zeta, double constants) {
        double decay = constants * fraction;    // zeta * omega * t
        double envelope = Math.exp(-decay);
        if (zeta >= 0.999) return 1 - envelope * (1 + decay);
        double root = Math.sqrt(1 - zeta * zeta);
        double phase = decay / zeta * root;     // damped omega * t
        return 1 - envelope * (Math.cos(phase) + zeta / root * Math.sin(phase));
    }

    public static void beginTransition(ViewGroup root, long durationMs, int curve) {
        Transition transition = new AutoTransition();
        transition.setDuration(durationMs);
        transition.setInterpolator(interpolator(curve));
        TransitionManager.beginDelayedTransition(root, transition);
    }

    /// TransitionAnimator's counterpart: `arriving` has just replaced `leaving`
    /// in `parent`. The arriving view starts off by (inX, inY) of the parent's
    /// size, or transparent, and animates in. The leaving view is drawn in the
    /// parent's overlay, where a removed view stays visible, animates out by
    /// (outX, outY), and is let go. The root's AutoTransition would animate the
    /// same change its own way, so it is ended first.
    public static void animateReplacement(ViewGroup sceneRoot, ViewGroup parent, View arriving,
                                          final View leaving, long durationMs, int curve,
                                          float inX, float inY, boolean inFade,
                                          final float outX, final float outY, final boolean outFade) {
        int width = parent.getWidth();
        int height = parent.getHeight();
        if (width == 0 || height == 0) return;
        if (sceneRoot != null) TransitionManager.endTransitions(sceneRoot);
        android.animation.TimeInterpolator easing = interpolator(curve);

        if (arriving != null) {
            arriving.setTranslationX(inX * width);
            arriving.setTranslationY(inY * height);
            if (inFade) arriving.setAlpha(0f);
            arriving.animate().translationX(0f).translationY(0f).alpha(1f)
                .setDuration(durationMs).setInterpolator(easing).start();
        }

        if (leaving != null && leaving.getParent() == null) {
            final android.view.ViewGroupOverlay overlay = parent.getOverlay();
            overlay.add(leaving);
            leaving.animate().translationX(outX * width).translationY(outY * height)
                .alpha(outFade ? 0f : 1f)
                .setDuration(durationMs).setInterpolator(easing)
                .withEndAction(() -> {
                    overlay.remove(leaving);
                    leaving.setTranslationX(0f);
                    leaving.setTranslationY(0f);
                    leaving.setAlpha(1f);
                })
                .start();
        }
    }

    /// The push/pop counterpart of ZStack+Apple's CATransition.
    public static void beginNavigationTransition(ViewGroup root, boolean isPush, long durationMs) {
        // Two Slides: one Slide uses the same edge for both directions, so the
        // outgoing screen chases the incoming one off the same side.
        Slide arriving = new Slide();
        arriving.setMode(Visibility.MODE_IN);
        arriving.setSlideEdge(isPush ? Gravity.END : Gravity.START);

        Slide leaving = new Slide();
        leaving.setMode(Visibility.MODE_OUT);
        leaving.setSlideEdge(isPush ? Gravity.START : Gravity.END);

        TransitionSet set = new TransitionSet();
        set.setOrdering(TransitionSet.ORDERING_TOGETHER);
        set.addTransition(leaving);
        set.addTransition(arriving);
        set.setDuration(durationMs);
        set.setInterpolator(new AccelerateDecelerateInterpolator());

        TransitionManager.beginDelayedTransition(root, set);
    }

    /// One registered font file: where it came from, and what its tables say
    /// it is, read from the file itself so naming does not matter.
    private static final class FontFace {
        final File file;          // a file on disk, or
        final String asset;       // a path in the APK's assets
        final Typeface face;
        final boolean variable;   // has an 'fvar' table with a 'wght' axis
        final int weight;         // OS/2 usWeightClass
        final boolean italic;     // OS/2 fsSelection bit 0

        FontFace(File file, String asset, Typeface face, byte[] bytes) {
            this.file = file;
            this.asset = asset;
            this.face = face;
            this.variable = hasTable(bytes, "fvar");
            int os2 = tableOffset(bytes, "OS/2");
            this.weight = os2 >= 0 && bytes.length > os2 + 5 ? u16(bytes, os2 + 4) : 400;
            this.italic = os2 >= 0 && bytes.length > os2 + 63 && (u16(bytes, os2 + 62) & 1) != 0;
        }

        Typeface at(int wanted) {
            if (!variable) return face;
            Typeface.Builder builder = file != null ? new Typeface.Builder(file)
                                                    : new Typeface.Builder(assets, asset);
            Typeface built = builder.setFontVariationSettings("'wght' " + wanted)
                                    .setWeight(wanted).setItalic(italic).build();
            return built != null ? built : face;
        }

        private static int u16(byte[] b, int at) { return ((b[at] & 0xFF) << 8) | (b[at + 1] & 0xFF); }

        private static int tableOffset(byte[] b, String tag) {
            if (b.length < 12) return -1;
            int tables = u16(b, 4);
            for (int i = 0; i < tables; i++) {
                int record = 12 + i * 16;
                if (record + 16 > b.length) return -1;
                if (b[record] == tag.charAt(0) && b[record + 1] == tag.charAt(1)
                        && b[record + 2] == tag.charAt(2) && b[record + 3] == tag.charAt(3)) {
                    return ((b[record + 8] & 0xFF) << 24) | ((b[record + 9] & 0xFF) << 16)
                         | ((b[record + 10] & 0xFF) << 8) | (b[record + 11] & 0xFF);
                }
            }
            return -1;
        }

        private static boolean hasTable(byte[] b, String tag) { return tableOffset(b, tag) >= 0; }
    }

    // Registered family name to its faces. Android resolves a font from a
    // handle, not a name, so the app's own map is the registry.
    private static final HashMap<String, java.util.ArrayList<FontFace>> FONTS = new HashMap<>();
    // family|weight|italic to the face built for it: a variable face is a new
    // Typeface per weight, and a render sets typefaces on every text view.
    private static final HashMap<String, Typeface> RESOLVED = new HashMap<>();
    private static android.content.res.AssetManager assets;

    private static void addFace(String family, FontFace face) {
        java.util.ArrayList<FontFace> faces = FONTS.get(family);
        if (faces == null) { faces = new java.util.ArrayList<>(); FONTS.put(family, faces); }
        faces.add(face);
        RESOLVED.clear();
    }

    public static boolean registerFont(String family, String path) {
        try {
            File file = new File(path);
            if (!file.exists()) return false;
            Typeface face = Typeface.createFromFile(file);
            if (face == null) return false;
            byte[] bytes = java.nio.file.Files.readAllBytes(file.toPath());
            addFace(family, new FontFace(file, null, face, bytes));
            return true;
        } catch (Throwable t) {
            Log.e("Omni", "could not register font " + path, t);
            return false;
        }
    }

    /// The build's assets/Fonts/<Family>/*.ttf|otf, each under its folder's
    /// name. Called by the generated MainActivity before the engine starts.
    public static void registerBundledFonts(Context context) {
        if (context instanceof Activity) hostActivity = (Activity) context;
        assets = context.getAssets();
        try {
            String[] families = assets.list("Fonts");
            if (families == null) return;
            for (String family : families) {
                String[] files = assets.list("Fonts/" + family);
                if (files == null) continue;
                java.util.Arrays.sort(files);
                for (String name : files) {
                    String lowered = name.toLowerCase();
                    if (!lowered.endsWith(".ttf") && !lowered.endsWith(".otf")) continue;
                    String asset = "Fonts/" + family + "/" + name;
                    try (InputStream in = assets.open(asset)) {
                        ByteArrayOutputStream out = new ByteArrayOutputStream();
                        byte[] chunk = new byte[16384];
                        for (int n; (n = in.read(chunk)) > 0; ) out.write(chunk, 0, n);
                        Typeface face = Typeface.createFromAsset(assets, asset);
                        if (face != null) addFace(family, new FontFace(null, asset, face, out.toByteArray()));
                    } catch (Throwable t) {
                        Log.e("Omni", "could not register font " + asset, t);
                    }
                }
            }
        } catch (IOException e) {
            Log.e("Omni", "could not list bundled fonts", e);
        }
    }

    /// A registered family at a weight and slant: a variable face set to the
    /// weight exactly, else the nearest static face of the slant asked for.
    private static Typeface resolveFont(String family, int weight, boolean italic) {
        String key = family + "|" + weight + "|" + italic;
        Typeface cached = RESOLVED.get(key);
        if (cached != null) return cached;
        java.util.ArrayList<FontFace> faces = FONTS.get(family);
        FontFace best = null;
        for (FontFace face : faces) {
            if (best == null) { best = face; continue; }
            boolean slant = face.italic == italic, bestSlant = best.italic == italic;
            if (slant != bestSlant) { if (slant) best = face; continue; }
            if (face.variable != best.variable) { if (face.variable) best = face; continue; }
            if (Math.abs(face.weight - weight) < Math.abs(best.weight - weight)) best = face;
        }
        Typeface resolved = best.at(weight);
        // No face of that slant: Android slants the nearest one.
        if (best.italic != italic) resolved = Typeface.create(resolved, best.variable ? weight : best.weight, italic);
        RESOLVED.put(key, resolved);
        return resolved;
    }

    /// Family, weight and slant in one call: they are one Typeface on Android, so
    /// setting them separately means the last setter wins.
    public static void setTypeface(TextView view, String family, int weight,
                                   boolean italic, boolean monospaced) {
        if (!monospaced && family != null && FONTS.containsKey(family)) {
            // The registry chose the face for this weight; create() would
            // embolden it again.
            view.setTypeface(resolveFont(family, weight, italic));
            return;
        }
        Typeface base;
        if (monospaced) {
            // .monospaced() wins over a custom family: it is the more specific request.
            base = Typeface.MONOSPACE;
        } else if (family != null) {
            base = Typeface.create(family, Typeface.NORMAL);
        } else {
            base = Typeface.DEFAULT;
        }
        // Typeface.create(Typeface, int, boolean) takes a 1-1000 weight and
        // synthesises what the file does not provide. API 28+, which is minSdk.
        view.setTypeface(Typeface.create(base, weight, italic));
    }

    public static void setImage(ImageView view, String name, boolean isSystem) {
        Context ctx = view.getContext();

        int edge = Math.round(SYMBOL_SIZE_DP * ctx.getResources().getDisplayMetrics().density);
        OmniSymbol drawn = isSystem ? OmniSymbol.make(name, edge) : null;
        if (drawn != null) {
            view.setImageDrawable(drawn);
        } else {
            String pkg = isSystem ? "android" : ctx.getPackageName();
            String resName = name;
            if (isSystem) {
                String mapped = SYMBOL_NAMES.get(name);
                // Resource names cannot contain a dot, so an unmapped symbol would
                // never resolve as written.
                resName = (mapped != null) ? mapped : name.replace('.', '_');
            }

            int resId = ctx.getResources().getIdentifier(resName, "drawable", pkg);
            if (resId != 0) {
                view.setImageResource(resId);
            } else {
                Log.w("Omni", "no drawable for image '" + name + "'");
            }
        }

        if (isSystem) {
            view.setAdjustViewBounds(true);
            view.setMaxWidth(edge);
            view.setMaxHeight(edge);
            view.setScaleType(ImageView.ScaleType.FIT_CENTER);
        }
    }

    /// .textContentType: what the field holds, for autofill (API 26 and up).
    /// An empty hint clears it.
    public static void setAutofillHint(View view, String hint) {
        if (android.os.Build.VERSION.SDK_INT < 26) return;
        if (hint.isEmpty()) {
            view.setImportantForAutofill(View.IMPORTANT_FOR_AUTOFILL_AUTO);
            view.setAutofillHints((String[]) null);
        } else {
            view.setImportantForAutofill(View.IMPORTANT_FOR_AUTOFILL_YES);
            view.setAutofillHints(hint);
        }
    }

    /// .foregroundColor for the symbols under `view`. A photo or an asset keeps
    /// its own colors, as in SwiftUI.
    /// .offset (px) and .scaleEffect. Drawn moved, as on iOS, where nothing
    /// clips unless asked: a FrameLayout clips its children to its bounds, and
    /// one faded draws them into a layer its size, so an offset label past its
    /// wrapper vanished. Its ancestors stop doing either, up to a scroll view,
    /// whose content must stay inside it. Posted: on the first render the view
    /// isn't in its parent yet.
    public static void setTransform(final View view, float x, float y, float scale) {
        view.setTranslationX(x);
        view.setTranslationY(y);
        view.setScaleX(scale);
        view.setScaleY(scale);
        if (x == 0 && y == 0 && scale == 1) return;
        view.post(() -> {
            android.view.ViewParent parent = view.getParent();
            while (parent instanceof ViewGroup
                    && !(parent instanceof HorizontalScrollView) && !(parent instanceof ScrollView)) {
                ViewGroup group = (ViewGroup) parent;
                group.setClipChildren(false);
                group.forceHasOverlappingRendering(false);
                parent = group.getParent();
            }
        });
    }

    /// .shadow: elevation, the platform's drop shadow, on the content inside
    /// `container`. Not on the container: Android draws siblings by elevation,
    /// so a shadowed circle drew over the icon after it in a ZStack. The
    /// container stays flat, in its place among them; the content's own outline
    /// (a circle, a rounded card) shapes the shadow, which spills past the
    /// container and its parent as on iOS. Posted: the content isn't inserted yet.
    public static void setShadow(final View container, final float elevation, final int color) {
        container.setElevation(0);
        container.post(() -> {
            if (!(container instanceof ViewGroup) || ((ViewGroup) container).getChildCount() == 0) return;
            // Down the first children to the one with a shape: Android shadows an outline,
            // and the wrappers sizing the content (a frame) have none, so nothing was drawn.
            View content = ((ViewGroup) container).getChildAt(0), shaped = content;
            while (shaped != null && !hasOutline(shaped)) {
                shaped = shaped instanceof ViewGroup && ((ViewGroup) shaped).getChildCount() > 0
                    ? ((ViewGroup) shaped).getChildAt(0) : null;
            }
            lift(shaped != null ? shaped : content, Color.alpha(color) == 0 ? 0 : elevation, color, container);
        });
    }

    /// A drop shadow of `elevation` on `view`, its colour where the platform allows, and
    /// nothing up to the nearest scroll view clipping it off: it spills past them, as on
    /// iOS. Stopped a level above, the rows around it cut the shadow off in straight lines.
    static void lift(View view, float elevation, int color, View above) {
        view.setElevation(elevation);
        if (android.os.Build.VERSION.SDK_INT >= 28 && Color.alpha(color) != 0) {
            int opaque = color | 0xff000000;
            view.setOutlineAmbientShadowColor(opaque);
            view.setOutlineSpotShadowColor(opaque);
        }
        for (android.view.ViewParent p = view.getParent(); p instanceof ViewGroup
                && !(p instanceof HorizontalScrollView) && !(p instanceof ScrollView); p = p.getParent()) {
            ViewGroup group = (ViewGroup) p;
            group.setClipChildren(false);
            group.setClipToPadding(false);
            // A view drawn through a layer (an opacity) clips to its bounds whatever the above.
            group.forceHasOverlappingRendering(false);
        }
    }

    /// Whether Android has an outline to shadow: a background (a fill, a glass), or a clip's shape.
    private static boolean hasOutline(View view) {
        return view.getBackground() != null || view.getClipToOutline();
    }

    /// Image's .scaledToFill (crop to fill the view) or .scaledToFit (whole, centred).
    public static void setImageScale(ImageView view, boolean fill) {
        view.setScaleType(fill ? ImageView.ScaleType.CENTER_CROP : ImageView.ScaleType.FIT_CENTER);
        view.setAdjustViewBounds(false);
    }

    /// Spacer. Measured, it asks for no more than its minimum unless told an exact
    /// size, as SwiftUI's ideal size is its minLength: a plain View takes all it's
    /// offered, so in a wrapper sized to its content (a keypad's empty corner key)
    /// it took the whole row from the keys beside it. A stack's weight still gives
    /// it the surplus, measured exactly.
    public static class OmniSpacer extends View {
        public OmniSpacer(Context context) { super(context); }

        @Override protected void onMeasure(int widthSpec, int heightSpec) {
            setMeasuredDimension(size(widthSpec, getSuggestedMinimumWidth()),
                                 size(heightSpec, getSuggestedMinimumHeight()));
        }

        private static int size(int spec, int minimum) {
            return MeasureSpec.getMode(spec) == MeasureSpec.EXACTLY ? MeasureSpec.getSize(spec) : minimum;
        }
    }

    /// An HStack. A LinearLayout gives each child what it asks, in order, so a long
    /// text took the whole row and pushed what follows (a row's chevron) past its
    /// edge. As on iOS, the row fits: the widest child sized by its content gives
    /// up the overflow, and its text wraps or truncates.
    public static class OmniHStack extends LinearLayout {
        public OmniHStack(Context context) { super(context); setOrientation(HORIZONTAL); }

        @Override protected void onMeasure(int widthSpec, int heightSpec) {
            super.onMeasure(widthSpec, heightSpec);
            if (MeasureSpec.getMode(widthSpec) == MeasureSpec.UNSPECIFIED) return;
            int available = MeasureSpec.getSize(widthSpec) - getPaddingLeft() - getPaddingRight();
            int used = 0, shown = 0;
            View widest = null;
            for (int i = 0; i < getChildCount(); i++) {
                View child = getChildAt(i);
                if (child.getVisibility() == GONE) continue;
                LayoutParams lp = (LayoutParams) child.getLayoutParams();
                used += child.getMeasuredWidth() + lp.leftMargin + lp.rightMargin;
                shown++;
                if (child instanceof OmniSpacer || lp.width != LayoutParams.WRAP_CONTENT) continue;
                if (widest == null || child.getMeasuredWidth() > widest.getMeasuredWidth()) widest = child;
            }
            // The stack's spacing is a divider of that width (setLinearLayoutSpacing).
            android.graphics.drawable.Drawable divider = getDividerDrawable();
            if (divider != null && (getShowDividers() & SHOW_DIVIDER_MIDDLE) != 0 && shown > 1)
                used += divider.getIntrinsicWidth() * (shown - 1);
            int overflow = used - available;
            if (overflow <= 0 || widest == null) return;
            // Measured again with that child held to what's left; its own params are put back after.
            LayoutParams lp = (LayoutParams) widest.getLayoutParams();
            float weight = lp.weight;
            lp.width = Math.max(0, widest.getMeasuredWidth() - overflow);
            lp.weight = 0;
            super.onMeasure(widthSpec, heightSpec);
            lp.width = LayoutParams.WRAP_CONTENT;
            lp.weight = weight;
        }
    }

    /// A .foregroundColor: symbols, and text (labels and fields), as on iOS.
    public static void tintSymbols(View view, int argb) {
        if (view instanceof TextView) {
            ((TextView) view).setTextColor(argb);
        } else if (view instanceof ImageView) {
            ImageView image = (ImageView) view;
            if (image.getDrawable() instanceof OmniSymbol) {
                image.setColorFilter(argb, android.graphics.PorterDuff.Mode.SRC_IN);
            }
        } else if (view instanceof ViewGroup) {
            ViewGroup group = (ViewGroup) view;
            for (int i = 0; i < group.getChildCount(); i++) tintSymbols(group.getChildAt(i), argb);
        }
    }

    /// LinearGradient: `colors` evenly spaced from start to end, both in unit
    /// coordinates of the view, redrawn at each size.
    public static void setLinearGradient(View view, int[] colors, final float startX,
                                         final float startY, final float endX, final float endY) {
        if (colors.length == 0) {
            view.setBackground(null);
            return;
        }
        // A shader needs two colours; one is a flat fill.
        final int[] stops = colors.length == 1 ? new int[] { colors[0], colors[0] } : colors;
        android.graphics.drawable.ShapeDrawable drawable =
            new android.graphics.drawable.ShapeDrawable(new android.graphics.drawable.shapes.RectShape());
        drawable.setShaderFactory(new android.graphics.drawable.ShapeDrawable.ShaderFactory() {
            @Override
            public android.graphics.Shader resize(int width, int height) {
                return new android.graphics.LinearGradient(startX * width, startY * height,
                    endX * width, endY * height, stops, null, android.graphics.Shader.TileMode.CLAMP);
            }
        });
        view.setBackground(drawable);
    }

    // The window's content: haptics are played from a view, and settings read through its context.
    private static View contentView;
    // The activity, from its onCreate: there before any content is, so haptics,
    // the clipboard and settings work during the first render too.
    private static Activity hostActivity;

    /// Somewhere to play a haptic from, and a Context: the content once it is
    /// up, else the activity's own window.
    private static View anyView() {
        if (contentView != null) return contentView;
        if (hostActivity != null) return hostActivity.getWindow().getDecorView();
        return null;
    }

    /// What accessibility modifiers have said about a view. Each modifier sets
    /// only its own fields, so stacked ones (.accessibilityLabel then
    /// .accessibilityValue) merge rather than the last one winning.
    private static final class Spoken {
        String label, value, hint;
        int traits;
        boolean element;
    }

    private static final java.util.WeakHashMap<View, Spoken> SPOKEN = new java.util.WeakHashMap<>();

    /// accessibilityLabel, Value, Hint, Element and AddTraits. null leaves a
    /// field as an earlier modifier set it. Label and value are read together,
    /// as the content description. An element is a screen-reader stop, which
    /// TalkBack reads as one, its children's text joined. Traits: 1 button,
    /// 2 header, 4 selected, 8 link.
    public static void setAccessibility(View view, String label, String value, String hint,
                                        boolean element, int traits) {
        Spoken spoken = SPOKEN.get(view);
        if (spoken == null) {
            spoken = new Spoken();
            SPOKEN.put(view, spoken);
            final Spoken state = spoken;
            view.setAccessibilityDelegate(new View.AccessibilityDelegate() {
                @Override
                public void onInitializeAccessibilityNodeInfo(View host, android.view.accessibility.AccessibilityNodeInfo info) {
                    super.onInitializeAccessibilityNodeInfo(host, info);
                    if (state.hint != null) info.setHintText(state.hint);
                    if ((state.traits & 4) != 0) info.setSelected(true);
                    if ((state.traits & 1) != 0) {
                        info.setClassName("android.widget.Button");
                    } else if ((state.traits & 8) != 0) {
                        // How AndroidX sets a role description, without AndroidX.
                        info.getExtras().putCharSequence("AccessibilityNodeInfo.roleDescription", "link");
                    }
                }
            });
        }
        if (label != null) spoken.label = label;
        if (value != null) spoken.value = value;
        if (hint != null) spoken.hint = hint;
        spoken.traits |= traits;
        spoken.element |= element;

        if (spoken.label != null || spoken.value != null) {
            String text = spoken.label == null ? spoken.value
                : spoken.value == null ? spoken.label : spoken.label + ", " + spoken.value;
            view.setContentDescription(text);
        }
        // A stop for the screen reader only: setFocusable would change keyboard focus too.
        if (spoken.element) view.setScreenReaderFocusable(true);
        if ((spoken.traits & 2) != 0) view.setAccessibilityHeading(true);
    }

    /// openURL's system action: whichever app handles the link (the browser,
    /// the dialler, mail, the Play Store), as iOS's UIApplication.open does.
    public static void openURL(byte[] utf8) {
        if (hostActivity == null) return;
        String url = new String(utf8, java.nio.charset.StandardCharsets.UTF_8);
        try {
            hostActivity.startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(url)));
        } catch (android.content.ActivityNotFoundException e) {
            Log.w("Omni", "nothing handles " + url);
        }
    }

    /// WebAuthentication: the URL in a Custom Tab, the browser's own activity
    /// over this one. The session extra is what asks for a Custom Tab; it is
    /// the whole protocol androidx.browser wraps. A browser without them opens
    /// the URL as a page. The page finishes on the app's scheme, which
    /// deliverIntent passes on.
    public static void openCustomTab(byte[] utf8) {
        if (hostActivity == null) return;
        String url = new String(utf8, java.nio.charset.StandardCharsets.UTF_8);
        Intent intent = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
        android.os.Bundle extras = new android.os.Bundle();
        extras.putBinder("android.support.customtabs.extra.SESSION", null);
        intent.putExtras(extras);
        try {
            hostActivity.startActivity(intent);
        } catch (android.content.ActivityNotFoundException e) {
            Log.w("Omni", "no browser for " + url);
        }
    }

    /// ShareLink: the system's share sheet, with the text (or the link, as text).
    public static void share(byte[] utf8) {
        if (hostActivity == null) return;
        Intent send = new Intent(Intent.ACTION_SEND);
        send.setType("text/plain");
        send.putExtra(Intent.EXTRA_TEXT, new String(utf8, java.nio.charset.StandardCharsets.UTF_8));
        hostActivity.startActivity(Intent.createChooser(send, null));
    }

    /// Clipboard.copy. Android 13 and later show their own "Copied" confirmation.
    public static void copyText(byte[] utf8) {
        String text = new String(utf8, java.nio.charset.StandardCharsets.UTF_8);
        View view = anyView();
        if (view == null) return;
        android.content.ClipboardManager clipboard = (android.content.ClipboardManager)
            view.getContext().getSystemService(Context.CLIPBOARD_SERVICE);
        if (clipboard != null) clipboard.setPrimaryClip(android.content.ClipData.newPlainText("", text));
    }

    /// Clipboard.string: the first item as UTF-8, or null. Bytes, not a String:
    /// JNI's strings are Modified UTF-8, which splits emoji in two.
    public static byte[] pastedText() {
        View view = anyView();
        if (view == null) return null;
        android.content.ClipboardManager clipboard = (android.content.ClipboardManager)
            view.getContext().getSystemService(Context.CLIPBOARD_SERVICE);
        if (clipboard == null || !clipboard.hasPrimaryClip()) return null;
        android.content.ClipData clip = clipboard.getPrimaryClip();
        if (clip == null || clip.getItemCount() == 0) return null;
        CharSequence text = clip.getItemAt(0).coerceToText(view.getContext());
        return text == null ? null : text.toString().getBytes(java.nio.charset.StandardCharsets.UTF_8);
    }

    /// Developer options' or Accessibility's "Remove animations": the animator
    /// scale at zero.
    public static boolean reduceMotion() {
        View view = anyView();
        if (view == null) return false;
        float scale = android.provider.Settings.Global.getFloat(view.getContext().getContentResolver(),
            android.provider.Settings.Global.ANIMATOR_DURATION_SCALE, 1f);
        return scale == 0f;
    }

    /// SensoryFeedback.play(): 1 success, 2 warning or error, 3 selection,
    /// 4 heavy, 5 light, 6 medium. Honours the system's touch-feedback setting.
    public static void haptic(int kind) {
        View view = anyView();
        if (view == null) return;
        int constant;
        switch (kind) {
            case 1: constant = android.os.Build.VERSION.SDK_INT >= 30
                        ? android.view.HapticFeedbackConstants.CONFIRM
                        : android.view.HapticFeedbackConstants.VIRTUAL_KEY; break;
            case 2: constant = android.os.Build.VERSION.SDK_INT >= 30
                        ? android.view.HapticFeedbackConstants.REJECT
                        : android.view.HapticFeedbackConstants.LONG_PRESS; break;
            case 3: constant = android.view.HapticFeedbackConstants.CLOCK_TICK; break;
            case 4: constant = android.view.HapticFeedbackConstants.LONG_PRESS; break;
            case 5: constant = android.view.HapticFeedbackConstants.KEYBOARD_TAP; break;
            default: constant = android.view.HapticFeedbackConstants.VIRTUAL_KEY; break;
        }
        view.performHapticFeedback(constant);
    }

    /// The window's content: drawn edge to edge, under the status and navigation
    /// bars, with the app's own views padded clear of them (and of the keyboard,
    /// which edge to edge no longer resizes the window for). The strips the
    /// padding leaves take the colour of the screen at that edge, as the safe
    /// area shows the background on iOS; a view marked .ignoresSafeArea() draws
    /// over them (BleedLayout).
    // The window's one host, and what it shows: installRoot is called again
    // whenever the app's root changes, and only swaps the content.
    private static RootHost rootHost;
    private static View rootContent;

    public static void installRoot(Activity activity, View content) {
        hostActivity = activity;
        // A new activity for the same process (Android recreated it in the background):
        // the old host went with the old window, and the new one showed nothing. The
        // app's views move to a new host in the new window.
        if (rootHost != null && rootHost.getContext() != activity) {
            rootHost.removeAllViews();
            rootHost = null;
            rootContent = null;
        }
        if (rootHost != null) {
            if (content == rootContent) return;
            ViewGroup parent = (ViewGroup) content.getParent();
            if (parent != null) parent.removeView(content);
            rootHost.removeAllViews();
            rootHost.addView(content, new android.widget.FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
            rootContent = content;
            rootHost.requestApplyInsets();
            return;
        }

        android.view.Window window = activity.getWindow();
        // The bars' colours are the window's only with this flag, and without the translucent
        // ones; else the theme's stayed (DeviceDefault.Light's: a white navigation bar).
        window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS
            | android.view.WindowManager.LayoutParams.FLAG_TRANSLUCENT_NAVIGATION);
        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS);
        window.setStatusBarColor(Color.TRANSPARENT);
        window.setNavigationBarColor(Color.TRANSPARENT);
        if (android.os.Build.VERSION.SDK_INT >= 29) {
            window.setStatusBarContrastEnforced(false);
            window.setNavigationBarContrastEnforced(false);
        }
        window.setSoftInputMode(android.view.WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);
        if (android.os.Build.VERSION.SDK_INT >= 30) {
            window.setDecorFitsSystemWindows(false);
        } else {
            View decor = window.getDecorView();
            decor.setSystemUiVisibility(decor.getSystemUiVisibility()
                | View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION);
        }

        final RootHost host = new RootHost(activity);
        host.addView(content, new android.widget.FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        host.setOnApplyWindowInsetsListener((v, insets) -> {
            int left, top, right, bottom;
            if (android.os.Build.VERSION.SDK_INT >= 30) {
                android.graphics.Insets bars = insets.getInsets(
                    android.view.WindowInsets.Type.systemBars() | android.view.WindowInsets.Type.displayCutout());
                android.graphics.Insets keyboard = insets.getInsets(android.view.WindowInsets.Type.ime());
                left = bars.left; top = bars.top; right = bars.right;
                bottom = keyboardCovers ? bars.bottom : Math.max(bars.bottom, keyboard.bottom);
            } else {
                // Includes the keyboard, under adjustResize; the stable inset leaves it out.
                left = insets.getSystemWindowInsetLeft();
                top = insets.getSystemWindowInsetTop();
                right = insets.getSystemWindowInsetRight();
                bottom = keyboardCovers ? insets.getStableInsetBottom() : insets.getSystemWindowInsetBottom();
            }
            v.setPadding(left, top, right, bottom);
            // What the content under the bars (.ignoresSafeArea) must keep clear
            // of; the keyboard isn't part of it, as on iOS.
            int barsBottom = keyboardCovers || android.os.Build.VERSION.SDK_INT < 30 ? bottom
                : insets.getInsets(android.view.WindowInsets.Type.systemBars()).bottom;
            dispatchSafeArea(dp(v, top), dp(v, barsBottom));
            return insets;
        });
        activity.setContentView(host);
        // Again after setContentView: installing the decor reads the theme's contrast
        // setting, which undid the one above, and a white scrim stayed behind the
        // navigation bar's buttons.
        if (android.os.Build.VERSION.SDK_INT >= 29) {
            window.setStatusBarContrastEnforced(false);
            window.setNavigationBarContrastEnforced(false);
        }
        rootHost = host;
        rootContent = content;
        contentView = host;
        host.requestApplyInsets();
        // One listener for the window's life, reading whatever the host shows now.
        // Debug builds log the tree a second after each layout settles, so a screen that
        // looks wrong can be read from logcat (OmniLayout) without a gesture.
        final Runnable settledDump = () -> dumpTree(host);
        host.getViewTreeObserver().addOnGlobalLayoutListener(() -> {
            if (rootContent != null) host.refresh(activity, rootContent);
            host.removeCallbacks(settledDump);
            host.postDelayed(settledDump, 1000);
        });
    }

    public static final class RootHost extends android.widget.FrameLayout {
        private final Paint band = new Paint();
        private int topColor = Color.WHITE;
        private int bottomColor = Color.WHITE;

        public RootHost(Context context) {
            super(context);
            setWillNotDraw(false);
            // A BleedLayout's child reaches into the padding.
            setClipToPadding(false);
            setClipChildren(false);
        }

        /// Dark mode switched in the system's settings: the app re-renders in it if it
        /// follows the system. Reached because the manifest takes uiMode changes itself.
        @Override protected void onConfigurationChanged(android.content.res.Configuration config) {
            super.onConfigurationChanged(config);
            dispatchAppearance();
        }

        /// A third finger down logs the view tree (debug builds; see dumpTree).
        @Override public boolean dispatchTouchEvent(MotionEvent e) {
            blurOnTouchOutside(this, e);
            if (e.getActionMasked() == MotionEvent.ACTION_POINTER_DOWN && e.getPointerCount() == 3) {
                dumpTree(this);
            }
            return super.dispatchTouchEvent(e);
        }

        void refresh(Activity activity, View content) {
            if (content.getWidth() == 0 || content.getHeight() == 0) return;
            int top = colorAt(content, content.getWidth() / 2, 0);
            int bottom = colorAt(content, content.getWidth() / 2, content.getHeight() - 1);
            // Nothing opaque at that edge: the scheme's background, not always white,
            // which put a white strip behind the navigation bar in dark mode.
            int fallback = darkScheme ? Color.BLACK : Color.WHITE;
            if (top == 0) top = fallback;
            if (bottom == 0) bottom = fallback;
            if (top != topColor || bottom != bottomColor) {
                topColor = top;
                bottomColor = bottom;
                invalidate();
            }
            appearance(activity.getWindow(), top, bottom);
        }

        @Override
        protected void onDraw(Canvas canvas) {
            super.onDraw(canvas);
            int w = getWidth(), h = getHeight();
            band.setColor(topColor);
            canvas.drawRect(0, 0, w, getPaddingTop(), band);
            canvas.drawRect(0, 0, getPaddingLeft(), h, band);
            canvas.drawRect(w - getPaddingRight(), 0, w, h, band);
            band.setColor(bottomColor);
            canvas.drawRect(0, h - getPaddingBottom(), w, h, band);
        }
    }

    /// .ignoresSafeArea(): its child reaches to the window's edge along each side
    /// where this view touches the safe area (RootHost's padding), for a
    /// background that should run under the bars. Elsewhere it is its own size.
    public static final class BleedLayout extends android.widget.FrameLayout {
        public BleedLayout(Context context) {
            super(context);
            setClipChildren(false);
            setClipToPadding(false);
        }

        @Override
        protected void onLayout(boolean changed, int left, int top, int right, int bottom) {
            RootHost host = null;
            for (android.view.ViewParent p = getParent(); p != null; p = p.getParent()) {
                if (p instanceof RootHost) { host = (RootHost) p; break; }
            }
            int w = right - left, h = bottom - top;
            int extLeft = 0, extTop = 0, extRight = 0, extBottom = 0;
            if (host != null) {
                int[] mine = new int[2], theirs = new int[2];
                getLocationInWindow(mine);
                host.getLocationInWindow(theirs);
                int x = mine[0] - theirs[0], y = mine[1] - theirs[1];
                int rightGap = host.getWidth() - (x + w), bottomGap = host.getHeight() - (y + h);
                if (y <= host.getPaddingTop() + 1) extTop = y;
                if (bottomGap <= host.getPaddingBottom() + 1) extBottom = bottomGap;
                if (x <= host.getPaddingLeft() + 1) extLeft = x;
                if (rightGap <= host.getPaddingRight() + 1) extRight = rightGap;
                // The child draws past this view, so nothing between here and the
                // host may clip it.
                for (android.view.ViewParent p = getParent(); p instanceof ViewGroup && p != host; p = p.getParent()) {
                    ((ViewGroup) p).setClipChildren(false);
                }
            }
            int width = w + extLeft + extRight, height = h + extTop + extBottom;
            for (int i = 0; i < getChildCount(); i++) {
                View child = getChildAt(i);
                if (child.getVisibility() == GONE) continue;
                child.measure(MeasureSpec.makeMeasureSpec(width, MeasureSpec.EXACTLY),
                              MeasureSpec.makeMeasureSpec(height, MeasureSpec.EXACTLY));
                child.layout(-extLeft, -extTop, w + extRight, h + extBottom);
            }
        }
    }

    /// Bar icons dark on a light edge, light on a dark one.
    private static void appearance(android.view.Window window, int top, int bottom) {
        if (android.os.Build.VERSION.SDK_INT >= 30) {
            android.view.WindowInsetsController controller = window.getInsetsController();
            if (controller == null) return;
            int light = android.view.WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS;
            int lightNav = android.view.WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS;
            controller.setSystemBarsAppearance(
                (isLight(top) ? light : 0) | (isLight(bottom) ? lightNav : 0), light | lightNav);
        } else {
            View decor = window.getDecorView();
            int light = View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR;
            int lightNav = View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR;
            int flags = decor.getSystemUiVisibility() & ~(light | lightNav);
            flags |= (isLight(top) ? light : 0) | (isLight(bottom) ? lightNav : 0);
            if (flags != decor.getSystemUiVisibility()) decor.setSystemUiVisibility(flags);
        }
    }

    private static boolean isLight(int color) {
        double luminance = 0.2126 * Color.red(color) + 0.7152 * Color.green(color)
            + 0.0722 * Color.blue(color);
        return luminance > 160;
    }

    /// The opaque colour drawn at (x, y) in `view`'s coordinates: the topmost
    /// child there that has one, else the view's own. 0 for none.
    private static int colorAt(View view, int x, int y) {
        if (view.getVisibility() != View.VISIBLE) return 0;
        // Not what scrolls past the edge (a light button scrolled under the tab bar
        // turned the strip behind the navigation bar white): the screen behind it.
        // A horizontal pager's pages are still looked into.
        if (view instanceof ViewGroup && !(view instanceof ScrollView)) {
            ViewGroup group = (ViewGroup) view;
            for (int i = group.getChildCount() - 1; i >= 0; i--) {
                View child = group.getChildAt(i);
                int cx = x - child.getLeft() + group.getScrollX();
                int cy = y - child.getTop() + group.getScrollY();
                if (cx < 0 || cy < 0 || cx >= child.getWidth() || cy >= child.getHeight()) continue;
                int inner = colorAt(child, cx, cy);
                if (inner != 0) return inner;
            }
        }
        android.graphics.drawable.Drawable background = view.getBackground();
        int color = 0;
        if (background instanceof android.graphics.drawable.ColorDrawable) {
            color = ((android.graphics.drawable.ColorDrawable) background).getColor();
        } else if (background instanceof GradientDrawable) {
            android.content.res.ColorStateList fill = ((GradientDrawable) background).getColor();
            if (fill != null) color = fill.getDefaultColor();
        }
        return Color.alpha(color) == 255 ? color : 0;
    }

    /// A shape's outline, drawn along its path as on Apple. `kind`: 0 rounded
    /// rectangle, 1 capsule, 2 ellipse, 3 circle. `inset` is strokeBorder: the
    /// whole line inside the bounds. Otherwise it is centred on the edge.
    public static void setStroke(View view, int kind, float radiusDp, float widthDp,
                                 boolean inset, int color) {
        float density = view.getResources().getDisplayMetrics().density;
        view.setBackground(new StrokeDrawable(kind, radiusDp * density, widthDp * density, inset, color));
    }

    /// A view with no size of its own: under a parent that wraps its content it
    /// measures to nothing, and the parent then stretches it to its own size
    /// (FrameLayout re-measures MATCH_PARENT children once it knows it). A plain
    /// View measures to the most it is offered, so an overlay's stroke made the
    /// field it outlines as tall as the screen.
    public static final class FillView extends View {
        public FillView(Context context) { super(context); }

        @Override
        protected void onMeasure(int widthSpec, int heightSpec) {
            setMeasuredDimension(exact(widthSpec), exact(heightSpec));
        }

        private static int exact(int spec) {
            return MeasureSpec.getMode(spec) == MeasureSpec.EXACTLY ? MeasureSpec.getSize(spec) : 0;
        }

        /// FrameLayout re-measures MATCH_PARENT children only when it has two of
        /// them; over a base that wraps (a Text), this one would stay at nothing.
        /// So it takes the frame's size itself: the frame's own bounds are set
        /// before it lays out its children.
        @Override
        public void layout(int left, int top, int right, int bottom) {
            ViewGroup.LayoutParams params = getLayoutParams();
            if (getParent() instanceof android.widget.FrameLayout && params != null) {
                android.widget.FrameLayout frame = (android.widget.FrameLayout) getParent();
                if (params.width == ViewGroup.LayoutParams.MATCH_PARENT) {
                    left = frame.getPaddingLeft();
                    right = frame.getWidth() - frame.getPaddingRight();
                }
                if (params.height == ViewGroup.LayoutParams.MATCH_PARENT) {
                    top = frame.getPaddingTop();
                    bottom = frame.getHeight() - frame.getPaddingBottom();
                }
            }
            super.layout(left, top, right, bottom);
        }
    }

    private static final class StrokeDrawable extends android.graphics.drawable.Drawable {
        private final int kind;
        private final float radius;
        private final boolean inset;
        private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final android.graphics.RectF rect = new android.graphics.RectF();

        StrokeDrawable(int kind, float radius, float width, boolean inset, int color) {
            this.kind = kind;
            this.radius = radius;
            this.inset = inset;
            paint.setStyle(Paint.Style.STROKE);
            paint.setStrokeWidth(width);
            paint.setColor(color);
        }

        @Override
        public void draw(Canvas canvas) {
            float half = paint.getStrokeWidth() / 2f;
            rect.set(getBounds());
            if (inset) rect.inset(half, half);
            if (rect.width() <= 0 || rect.height() <= 0) return;
            // Clamped to half the short side, as SwiftUI's radii are.
            float shortHalf = Math.min(rect.width(), rect.height()) / 2f;
            switch (kind) {
                case 1:
                    canvas.drawRoundRect(rect, shortHalf, shortHalf, paint);
                    break;
                case 2:
                    canvas.drawOval(rect, paint);
                    break;
                case 3:
                    canvas.drawCircle(rect.centerX(), rect.centerY(), shortHalf, paint);
                    break;
                default:
                    float r = Math.min(Math.max(radius - (inset ? half : 0), 0), shortHalf);
                    canvas.drawRoundRect(rect, r, r, paint);
            }
        }

        @Override public void setAlpha(int alpha) { paint.setAlpha(alpha); invalidateSelf(); }
        @Override public void setColorFilter(android.graphics.ColorFilter filter) { paint.setColorFilter(filter); invalidateSelf(); }
        @Override public int getOpacity() { return android.graphics.PixelFormat.TRANSLUCENT; }
    }

    public static void setImageBytes(ImageView view, byte[] data) {
        Bitmap bitmap = BitmapFactory.decodeByteArray(data, 0, data.length);
        if (bitmap != null) {
            view.setScaleType(ImageView.ScaleType.FIT_CENTER);
            view.setImageBitmap(bitmap);
        }
    }

    public static void setLinearLayoutSpacing(LinearLayout view, int spacing) {
        // Create an invisible drawable that acts purely as a spacing block
        GradientDrawable divider = new GradientDrawable();

        // This acts as height in VERTICAL layout, and width in HORIZONTAL layout
        divider.setSize(spacing, spacing);

        view.setDividerDrawable(divider);
        view.setShowDividers(LinearLayout.SHOW_DIVIDER_MIDDLE);
    }

    public static void setMultiline(EditText view) {
        view.setSingleLine(false);
        view.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_MULTI_LINE);
    }

    public static void setSecureText(EditText view) {
        // Sets keyboard to standard text + hints it's a password
        view.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
        // Enforces the dot (•) masking transformation
        view.setTransformationMethod(PasswordTransformationMethod.getInstance());
    }

    // 1. The custom view that intercepts swipes
    public static class OmniSwipeLayout extends android.widget.FrameLayout {
        private android.view.GestureDetector detector;

        public OmniSwipeLayout(android.content.Context context) {
            super(context);
        }

        public void setSwipePointers(long leftPtr, long rightPtr) {
            detector = new android.view.GestureDetector(getContext(), new android.view.GestureDetector.SimpleOnGestureListener() {
                private static final int SWIPE_THRESHOLD = 100;
                private static final int SWIPE_VELOCITY_THRESHOLD = 100;

                @Override
                public boolean onFling(android.view.MotionEvent e1, android.view.MotionEvent e2, float velocityX, float velocityY) {
                    float diffX = e2.getX() - e1.getX();
                    float diffY = e2.getY() - e1.getY();

                    if (Math.abs(diffX) > Math.abs(diffY) &&
                        Math.abs(diffX) > SWIPE_THRESHOLD &&
                        Math.abs(velocityX) > SWIPE_VELOCITY_THRESHOLD) {

                        if (diffX > 0 && rightPtr != 0) {
                            OmniEventBridge.dispatchVoid(rightPtr);
                            return true;
                        } else if (diffX < 0 && leftPtr != 0) {
                            OmniEventBridge.dispatchVoid(leftPtr);
                            return true;
                        }
                    }
                    return false;
                }
            });
        }

        @Override
        public boolean onInterceptTouchEvent(android.view.MotionEvent ev) {
            if (detector != null && detector.onTouchEvent(ev)) return true; // Steal the swipe!
            return super.onInterceptTouchEvent(ev);
        }

        @Override
        public boolean onTouchEvent(android.view.MotionEvent ev) {
            if (detector != null) detector.onTouchEvent(ev);
            return true;
        }
    }

    // 2. The method called by C to attach the pointers
    public static void attachSwipeGestures(android.view.View view, long leftPtr, long rightPtr) {
        if (view instanceof OmniSwipeLayout) {
            ((OmniSwipeLayout) view).setSwipePointers(leftPtr, rightPtr);
        }
    }

    // A stroke needs a drawable, so the fill comes along rather than being
    // overwritten by it.
    public static void setBox(View view, boolean hasFill, int fill, int strokeWidth, int stroke) {
        GradientDrawable box = new GradientDrawable();
        if (hasFill) box.setColor(fill);
        if (strokeWidth > 0) box.setStroke(strokeWidth, stroke);
        view.setBackground(box);
    }

    /// Glass and materials as Android can draw them: a translucent fill and a
    /// hairline in the shape, with no blur of what is behind. A capsule asks
    /// for any radius past half its height: GradientDrawable clamps it there.
    public static void setGlass(View view, int fill, int stroke, float radius, boolean isCircular) {
        GradientDrawable surface = new GradientDrawable();
        surface.setColor(fill);
        surface.setStroke(Math.max(1, Math.round(view.getResources().getDisplayMetrics().density * 0.5f)), stroke);
        surface.setCornerRadius(isCircular ? 100000f : radius);
        view.setBackground(surface);
        // Its content inside the shape, as iOS clips a material: the outline
        // is the drawable's, rounded as it is.
        view.setClipToOutline(true);
    }

    /// Glass's faint shadow, which iOS's glass draws itself (a tab bar's).
    public static void setGlassShadow(final View view, final float elevation) {
        // The background's shape, cast as if solid: a GradientDrawable that isn't opaque
        // (glass is a translucent fill) gives its outline no alpha, and Android draws no
        // shadow for it, however high it's lifted.
        view.setOutlineProvider(new ViewOutlineProvider() {
            @Override public void getOutline(View v, Outline outline) {
                android.graphics.drawable.Drawable background = v.getBackground();
                if (background != null) background.getOutline(outline);
                else outline.setRect(0, 0, v.getWidth(), v.getHeight());
                outline.setAlpha(1f);
            }
        });
        view.post(() -> lift(view, elevation, 0, view));
    }

    public static void setClipRadius(View view, float radius, boolean isCircular) {
        view.setClipToOutline(true);
        view.setOutlineProvider(new ViewOutlineProvider() {
            @Override
            public void getOutline(View v, Outline outline) {
                if (isCircular) {
                    // Rounded by half the shorter side: a capsule, and a circle
                    // in a square. A square of that side clipped a capsule to a circle.
                    int size = Math.min(v.getWidth(), v.getHeight());
                    // Outline gets evaluated when layout happens, so size > 0 check is safe
                    if (size > 0) {
                        outline.setRoundRect(0, 0, v.getWidth(), v.getHeight(), size / 2f);
                    }
                } else {
                    // For standard rounded rectangles
                    outline.setRoundRect(0, 0, v.getWidth(), v.getHeight(), radius);
                }
            }
        });
        // Force the view to re-evaluate the outline immediately
        view.invalidateOutline();
    }

    public static void dumpTree(final View root) {
        int flags = root.getContext().getApplicationInfo().flags;
        if ((flags & android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) == 0) return;

        Runnable dump = new Runnable() {
            @Override public void run() {
                Log.i("OmniLayout", "--- view tree ---");
                dumpNode(root, 0);
                Log.i("OmniLayout", "--- end ---");
            }
        };
        root.post(dump);
    }

    private static String describeSize(int value) {
        if (value == ViewGroup.LayoutParams.MATCH_PARENT) return "match";
        if (value == ViewGroup.LayoutParams.WRAP_CONTENT) return "wrap";
        return Integer.toString(value);
    }

    private static void dumpNode(View view, int depth) {
        StringBuilder line = new StringBuilder();
        for (int i = 0; i < depth; i++) line.append("  ");
        line.append(view.getClass().getSimpleName());
        line.append(' ').append(view.getWidth()).append('x').append(view.getHeight());
        line.append('@').append(view.getLeft()).append(',').append(view.getTop());

        ViewGroup.LayoutParams params = view.getLayoutParams();
        if (params == null) {
            line.append(" params=none");
        } else {
            line.append(" want=").append(describeSize(params.width))
                .append('x').append(describeSize(params.height));
            if (params instanceof LinearLayout.LayoutParams) {
                line.append(" weight=").append(((LinearLayout.LayoutParams) params).weight);
            }
        }
        if (view.getVisibility() != View.VISIBLE) line.append(" hidden");
        if (view.getTranslationX() != 0 || view.getTranslationY() != 0) {
            line.append(" moved=").append(view.getTranslationX()).append(',').append(view.getTranslationY());
        }
        if (view.getPaddingLeft() != 0 || view.getPaddingTop() != 0 || view.getPaddingRight() != 0 || view.getPaddingBottom() != 0) {
            line.append(" pad=").append(view.getPaddingLeft()).append(',').append(view.getPaddingTop())
                .append(',').append(view.getPaddingRight()).append(',').append(view.getPaddingBottom());
        }
        if (view.getScaleX() != 1 || view.getScaleY() != 1) line.append(" scale=").append(view.getScaleX());
        if (view.getAlpha() != 1) line.append(" alpha=").append(view.getAlpha());
        if (view.getElevation() != 0) line.append(" elev=").append(view.getElevation())
            .append(view.getOutlineProvider() == null ? " no-outline" : "");
        if (view.getClipToOutline()) line.append(" clipOutline");
        if (view instanceof ViewGroup && ((ViewGroup) view).getClipChildren()) line.append(" clips");
        if (view instanceof TextView) {
            CharSequence text = ((TextView) view).getText();
            if (text != null && text.length() > 0) {
                line.append(" \"").append(text.length() > 24 ? text.subSequence(0, 24) + "…" : text).append('"');
            }
        }
        Log.i("OmniLayout", line.toString());

        if (view instanceof ViewGroup) {
            ViewGroup group = (ViewGroup) view;
            for (int i = 0; i < group.getChildCount(); i++) {
                dumpNode(group.getChildAt(i), depth + 1);
            }
        }
    }

    public static void setSpinnerOptions(Spinner spinner, String optionsJoined) {
        String[] options = optionsJoined.split("\\|\\|\\|");

        // Use Android's built-in simple dropdown layout
        ArrayAdapter<String> adapter = new ArrayAdapter<>(
            spinner.getContext(),
            android.R.layout.simple_spinner_item,
            options
        );
        adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);

        spinner.setAdapter(adapter);
    }


    private static long pendingPermissionPtr = 0;

    public static void requestPermission(Activity activity, String permission, int requestCode, long ptr) {
        pendingPermissionPtr = ptr;
        activity.requestPermissions(new String[]{ permission }, requestCode);
    }

    /// Called from the generated MainActivity's onRequestPermissionsResult.
    public static void onRequestPermissionsResult(int requestCode, int[] grantResults) {
        long ptr = pendingPermissionPtr;
        pendingPermissionPtr = 0;
        if (ptr == 0) return;
        boolean granted = grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED;
        dispatchCameraPermissionResult(ptr, granted);
    }

    private static long pendingActivityResultPtr = 0;

    public static boolean launchCameraCapture(Activity activity, String outputPath, int requestCode,
                                              boolean frontFacing, long ptr) {
        Uri uri = OmniFileProvider.uriFor(activity, new java.io.File(outputPath));
        Intent intent = new Intent(MediaStore.ACTION_IMAGE_CAPTURE);
        intent.putExtra(MediaStore.EXTRA_OUTPUT, uri);
        intent.addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
        if (frontFacing) intent.putExtra("android.intent.extras.CAMERA_FACING", 1);

        if (intent.resolveActivity(activity.getPackageManager()) == null) {
            return false;
        }
        pendingActivityResultPtr = ptr;
        activity.startActivityForResult(intent, requestCode);
        return true;
    }

    public static void launchImagePick(Activity activity, int requestCode, long ptr) {
        pendingActivityResultPtr = ptr;
        Intent intent = new Intent(Intent.ACTION_PICK, MediaStore.Images.Media.EXTERNAL_CONTENT_URI);
        activity.startActivityForResult(intent, requestCode);
    }

    /// Called from the generated MainActivity's onActivityResult.
    public static void onActivityResult(int requestCode, int resultCode, Intent data) {
        long ptr = pendingActivityResultPtr;
        pendingActivityResultPtr = 0;
        if (ptr == 0) return;
        boolean ok = resultCode == Activity.RESULT_OK;
        String uri = (ok && data != null && data.getData() != null) ? data.getData().toString() : null;
        dispatchCameraActivityResult(ptr, ok, uri);
    }

    public static byte[] readUri(Context context, String uriString) {
        try (InputStream in = context.getContentResolver().openInputStream(Uri.parse(uriString))) {
            if (in == null) return null;
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buffer = new byte[8192];
            int n;
            while ((n = in.read(buffer)) != -1) out.write(buffer, 0, n);
            return out.toByteArray();
        } catch (IOException e) {
            return null;
        }
    }

    public static byte[] encodeImage(byte[] input, int maxDimension, String format, double quality) {
        Bitmap bitmap = BitmapFactory.decodeByteArray(input, 0, input.length);
        if (bitmap == null) return null;

        if (maxDimension > 0) {
            int width = bitmap.getWidth();
            int height = bitmap.getHeight();
            int longest = Math.max(width, height);
            if (longest > maxDimension) {
                double ratio = (double) maxDimension / (double) longest;
                int targetWidth = Math.max(1, (int) Math.round(width * ratio));
                int targetHeight = Math.max(1, (int) Math.round(height * ratio));
                bitmap = Bitmap.createScaledBitmap(bitmap, targetWidth, targetHeight, true);
            }
        }

        Bitmap.CompressFormat compressFormat;
        switch (format) {
            case "png": compressFormat = Bitmap.CompressFormat.PNG; break;
            default: compressFormat = Bitmap.CompressFormat.JPEG; break;
        }

        int qualityPercent = (int) Math.round(quality * 100);
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        boolean encoded;
        try {
            encoded = bitmap.compress(compressFormat, qualityPercent, out);
        } catch (Throwable t) {
            encoded = false;
        }
        return encoded ? out.toByteArray() : null;
    }

    public static int[] imageDimensions(byte[] data) {
        BitmapFactory.Options options = new BitmapFactory.Options();
        options.inJustDecodeBounds = true;
        BitmapFactory.decodeByteArray(data, 0, data.length, options);
        return new int[]{ options.outWidth, options.outHeight };
    }
}
