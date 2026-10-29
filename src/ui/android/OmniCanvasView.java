// src/lib/android/OmniCanvasView.java
package com.omni;
import android.app.AlertDialog;
import android.app.Dialog;
import android.view.View;
import android.view.ViewOutlineProvider;
import android.view.GestureDetector;
import android.view.MotionEvent;
import android.widget.ArrayAdapter;
import android.widget.AdapterView;
import android.widget.CompoundButton;
import android.widget.EditText;
import android.widget.SeekBar;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.Spinner;
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
import android.graphics.Path;
import java.util.ArrayList;
import java.util.List;

public class OmniCanvasView extends View {

    private interface RenderStep {
        void draw(Canvas canvas);
    }

    private final List<RenderStep> renderSteps = new ArrayList<>();
    private Path currentPath = new Path();
    private int currentStrokeColor = Color.BLACK;
    private int currentFillColor = Color.BLACK;
    private float currentStrokeWidth = 2.0f;

    public OmniCanvasView(Context context) {
        super(context);
    }

    public void resetCommands() {
        renderSteps.clear();
        currentPath = new Path();
        currentStrokeColor = Color.BLACK;
        currentFillColor = Color.BLACK;
        currentStrokeWidth = 2.0f;
        // New commands follow in this same pass; the draw comes after it.
        // Without this, a canvas redrew only when its size changed.
        invalidate();
    }

    public void beginPath() {
        currentPath = new Path();
    }

    public void moveTo(float x, float y) {
        currentPath.moveTo(x, y);
    }

    public void lineTo(float x, float y) {
        currentPath.lineTo(x, y);
    }

    public void cubicTo(float c1x, float c1y, float c2x, float c2y, float x, float y) {
        currentPath.cubicTo(c1x, c1y, c2x, c2y, x, y);
    }

    public void setStrokeColor(int a, int r, int g, int b) {
        currentStrokeColor = Color.argb(a, r, g, b);
    }

    public void setFillColor(int a, int r, int g, int b) {
        currentFillColor = Color.argb(a, r, g, b);
    }

    public void setStrokeWidth(float width) {
        currentStrokeWidth = width;
    }

    public void addStrokeCommand() {
        final Path pathToDraw = new Path(currentPath);
        final int color = currentStrokeColor;
        final float width = currentStrokeWidth;

        renderSteps.add(canvas -> {
            Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
            paint.setStyle(Paint.Style.STROKE);
            paint.setColor(color);
            paint.setStrokeWidth(width);
            canvas.drawPath(pathToDraw, paint);
        });
    }

    public void addFillCommand() {
        final Path pathToDraw = new Path(currentPath);
        final int color = currentFillColor;

        renderSteps.add(canvas -> {
            Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
            paint.setStyle(Paint.Style.FILL);
            paint.setColor(color);
            canvas.drawPath(pathToDraw, paint);
        });
    }

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        for (RenderStep step : renderSteps) {
            step.draw(canvas);
        }
    }
}
