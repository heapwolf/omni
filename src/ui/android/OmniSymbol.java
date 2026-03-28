// src/ui/android/OmniSymbol.java
package com.omni;

import android.graphics.Canvas;
import android.graphics.ColorFilter;
import android.graphics.Matrix;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.PixelFormat;
import android.graphics.Rect;
import android.graphics.RectF;
import android.graphics.drawable.Drawable;

/// The SF Symbols apps use, drawn as paths: Android has no equivalent set,
/// and its framework drawables differ by vendor. One color, so the ImageView's
/// color filter is .foregroundColor. A filled symbol cuts its mark out of the
/// fill, as SF Symbols do, instead of painting it white.
public final class OmniSymbol extends Drawable {
    private static final float BOX = 24f;
    private static final float STROKE = 2f;

    private final Path path;
    private final int edge;
    private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Path scaled = new Path();
    private final Matrix matrix = new Matrix();

    private OmniSymbol(Path path, int edge) {
        this.path = path;
        this.edge = edge;
        paint.setColor(0xFF000000);
        paint.setStyle(Paint.Style.FILL);
    }

    /// null for a name this doesn't draw.
    public static OmniSymbol make(String name, int edge) {
        Path path = build(name);
        return path == null ? null : new OmniSymbol(path, edge);
    }

    private static Path build(String name) {
        switch (name) {
            case "square": return stroke(roundedSquare());
            case "checkmark.square": return union(stroke(roundedSquare()), stroke(check(0.8f)));
            case "checkmark.square.fill": return minus(roundedSquare(), stroke(check(0.8f)));
            case "circle": return stroke(circle(9f));
            case "checkmark.circle": return union(stroke(circle(9f)), stroke(check(0.75f)));
            case "checkmark.circle.fill": return minus(circle(10f), stroke(check(0.75f)));
            case "checkmark": return stroke(check(1.1f));
            case "chevron.left": return stroke(polyline(15, 5, 8, 12, 15, 19));
            case "chevron.right": return stroke(polyline(9, 5, 16, 12, 9, 19));
            case "chevron.up": return stroke(polyline(5, 15, 12, 8, 19, 15));
            case "chevron.down": return stroke(polyline(5, 9, 12, 16, 19, 9));
            case "arrow.left": return union(stroke(polyline(11, 5, 4, 12, 11, 19)), stroke(polyline(4, 12, 20, 12)));
            case "arrow.right": return union(stroke(polyline(13, 5, 20, 12, 13, 19)), stroke(polyline(4, 12, 20, 12)));
            case "plus": return union(stroke(polyline(12, 4, 12, 20)), stroke(polyline(4, 12, 20, 12)));
            case "xmark": return union(stroke(polyline(6, 6, 18, 18)), stroke(polyline(18, 6, 6, 18)));
            case "eye": return union(stroke(almond()), stroke(circle(3.5f)));
            case "eye.fill": return eyeFill();
            case "eye.slash": return slashed(union(stroke(almond()), stroke(circle(3.5f))));
            case "eye.slash.fill": return slashed(eyeFill());
            case "lock": return lock(false);
            case "lock.fill": return lock(true);
            case "checkmark.shield": return union(stroke(shield()), stroke(check(0.6f)));
            case "checkmark.shield.fill": return minus(shield(), stroke(check(0.6f)));
            case "faceid": return faceId();
            case "arrow.up.right": return union(stroke(polyline(7, 17, 17, 7)), stroke(polyline(9, 7, 17, 7, 17, 15)));
            case "arrow.up.forward": return union(stroke(polyline(7, 17, 17, 7)), stroke(polyline(9, 7, 17, 7, 17, 15)));
            case "arrow.down.left": return union(stroke(polyline(17, 7, 7, 17)), stroke(polyline(7, 9, 7, 17, 15, 17)));
            case "arrow.left.arrow.right": return union(
                union(stroke(polyline(4, 8, 20, 8)), stroke(polyline(16, 4, 20, 8, 16, 12))),
                union(stroke(polyline(20, 16, 4, 16)), stroke(polyline(8, 12, 4, 16, 8, 20))));
            case "arrow.up.circle": return union(stroke(circle(9f)), arrowUp(0.7f));
            case "arrow.up.circle.fill": return minus(circle(10f), stroke(arrowUpPath(0.7f)));
            case "plus.circle.fill": return minus(circle(10f),
                union(stroke(polyline(12, 7.5f, 12, 16.5f)), stroke(polyline(7.5f, 12, 16.5f, 12))));
            case "ellipsis": return union(union(dot(5, 12), dot(12, 12)), dot(19, 12));
            case "bell.fill": return bell();
            case "doc.on.doc": return union(
                stroke(roundedRect(8, 8, 20, 21, 2.5f)),
                stroke(polyline(5, 16, 4, 16, 4, 5, 5, 3, 14, 3, 16, 4, 16, 5)));
            case "headphones": return headphones();
            case "person": return union(stroke(circle(12, 8, 4)), stroke(shoulders()));
            case "person.fill": return union(circle(12, 8, 4.5f), shouldersFill());
            case "house.fill": return house();
            case "clock": return union(stroke(circle(9f)), stroke(polyline(12, 7, 12, 12, 15.5f, 14)));
            case "creditcard": return union(stroke(roundedRect(2.5f, 5, 21.5f, 19, 2.5f)),
                union(stroke(polyline(3, 9.5f, 21, 9.5f)), stroke(polyline(6, 15, 10, 15))));
            case "building.columns": return union(
                union(stroke(polyline(3, 9, 12, 3.5f, 21, 9, 3, 9)), stroke(polyline(3, 20, 21, 20))),
                union(union(stroke(polyline(6, 11.5f, 6, 17.5f)), stroke(polyline(10, 11.5f, 10, 17.5f))),
                      union(stroke(polyline(14, 11.5f, 14, 17.5f)), stroke(polyline(18, 11.5f, 18, 17.5f)))));
            case "chart.line.uptrend.xyaxis": return union(
                stroke(polyline(3, 3, 3, 21, 21, 21)),
                stroke(polyline(6.5f, 16, 11, 11, 14, 14, 20, 7)));
            case "gearshape.fill": return gear();
            case "doc.text": return union(
                stroke(polyline(14, 3, 6, 3, 5, 4, 5, 20, 6, 21, 18, 21, 19, 20, 19, 8, 14, 3, 14, 8, 19, 8)),
                union(stroke(polyline(8.5f, 13, 15.5f, 13)), stroke(polyline(8.5f, 17, 13, 17))));
            case "rectangle.portrait.and.arrow.right": return union(
                stroke(polyline(14, 4, 6, 4, 5, 5, 5, 19, 6, 20, 14, 20)),
                union(stroke(polyline(10, 12, 21, 12)), stroke(polyline(17.5f, 8.5f, 21, 12, 17.5f, 15.5f))));
            case "camera.fill": return minus(union(roundedRect(2.5f, 7, 21.5f, 20, 3f),
                roundedRect(8, 4, 16, 8, 1.5f)), circle(12, 13.5f, 4f));
            case "checkmark.seal.fill": return minus(seal(), stroke(check(0.6f)));
            case "d.circle.fill": return minus(circle(10f), letterD());
            case "person.badge.plus": return union(
                union(stroke(circle(9.5f, 8, 3.5f)), stroke(shouldersAt(9.5f))),
                union(stroke(polyline(19, 8, 19, 14)), stroke(polyline(16, 11, 22, 11))));
            default: return null;
        }
    }

    // MARK: Shapes, in a 24-unit box

    private static Path roundedSquare() {
        Path p = new Path();
        p.addRoundRect(new RectF(3, 3, 21, 21), 4, 4, Path.Direction.CW);
        return p;
    }

    private static Path circle(float radius) {
        Path p = new Path();
        p.addCircle(12, 12, radius, Path.Direction.CW);
        return p;
    }

    /// A check mark about the center; scale 1 spans most of the box.
    private static Path check(float scale) {
        Path p = polyline(5, 12.5f, 10, 17.5f, 19, 7);
        Matrix m = new Matrix();
        m.setScale(scale, scale, 12, 12);
        p.transform(m);
        return p;
    }

    private static Path polyline(float... points) {
        Path p = new Path();
        p.moveTo(points[0], points[1]);
        for (int i = 2; i + 1 < points.length; i += 2) p.lineTo(points[i], points[i + 1]);
        return p;
    }

    private static Path almond() {
        Path p = new Path();
        p.moveTo(2, 12);
        p.quadTo(12, 1, 22, 12);
        p.quadTo(12, 23, 2, 12);
        p.close();
        return p;
    }

    private static Path eyeFill() {
        Path eye = minus(almond(), circle(4.5f));
        return union(eye, circle(2.5f));
    }

    /// A diagonal bar with a gap either side, over `shape`.
    private static Path slashed(Path shape) {
        Path bar = polyline(4, 3, 20, 21);
        Path gap = stroke(bar, STROKE * 2.5f);
        return union(minus(shape, gap), stroke(bar));
    }

    private static Path lock(boolean filled) {
        Path body = new Path();
        body.addRoundRect(new RectF(5, 11, 19, 21), 2.5f, 2.5f, Path.Direction.CW);
        Path shackle = new Path();
        shackle.moveTo(8, 11);
        shackle.lineTo(8, 8);
        shackle.arcTo(new RectF(8, 4, 16, 12), 180, 180);
        shackle.lineTo(16, 11);
        return union(filled ? body : stroke(body), stroke(shackle));
    }

    private static Path shield() {
        Path p = new Path();
        p.moveTo(12, 2.5f);
        p.lineTo(20, 5.5f);
        p.lineTo(20, 11);
        p.quadTo(20, 18, 12, 21.5f);
        p.quadTo(4, 18, 4, 11);
        p.lineTo(4, 5.5f);
        p.close();
        return p;
    }

    private static Path faceId() {
        Path corners = new Path();
        // Four brackets, each an L with a rounded bend.
        corners.moveTo(3, 8);   corners.lineTo(3, 6);   corners.quadTo(3, 3, 6, 3);   corners.lineTo(8, 3);
        corners.moveTo(16, 3);  corners.lineTo(18, 3);  corners.quadTo(21, 3, 21, 6); corners.lineTo(21, 8);
        corners.moveTo(21, 16); corners.lineTo(21, 18); corners.quadTo(21, 21, 18, 21); corners.lineTo(16, 21);
        corners.moveTo(8, 21);  corners.lineTo(6, 21);  corners.quadTo(3, 21, 3, 18); corners.lineTo(3, 16);
        Path face = new Path();
        face.moveTo(9, 8.5f);  face.lineTo(9, 10);
        face.moveTo(15, 8.5f); face.lineTo(15, 10);
        face.moveTo(12, 8.5f); face.lineTo(12, 13); face.lineTo(11, 13);
        face.moveTo(9, 16);    face.quadTo(12, 18, 15, 16);
        return union(stroke(corners), stroke(face));
    }

    private static Path circle(float cx, float cy, float radius) {
        Path p = new Path();
        p.addCircle(cx, cy, radius, Path.Direction.CW);
        return p;
    }

    private static Path dot(float cx, float cy) {
        return circle(cx, cy, 2f);
    }

    private static Path roundedRect(float left, float top, float right, float bottom, float radius) {
        Path p = new Path();
        p.addRoundRect(new RectF(left, top, right, bottom), radius, radius, Path.Direction.CW);
        return p;
    }

    /// An upward arrow about the center; scale 1 spans most of the box.
    private static Path arrowUpPath(float scale) {
        Path p = new Path();
        p.moveTo(12, 19); p.lineTo(12, 5);
        p.moveTo(6, 11); p.lineTo(12, 5); p.lineTo(18, 11);
        Matrix m = new Matrix();
        m.setScale(scale, scale, 12, 12);
        p.transform(m);
        return p;
    }

    private static Path arrowUp(float scale) {
        return stroke(arrowUpPath(scale));
    }

    private static Path bell() {
        Path body = new Path();
        body.moveTo(12, 3);
        body.cubicTo(8, 3, 6, 6, 6, 10);
        body.lineTo(6, 14.5f);
        body.lineTo(4, 17);
        body.lineTo(20, 17);
        body.lineTo(18, 14.5f);
        body.lineTo(18, 10);
        body.cubicTo(18, 6, 16, 3, 12, 3);
        body.close();
        Path clapper = new Path();
        clapper.addCircle(12, 19.5f, 2.5f, Path.Direction.CW);
        return union(body, clapper);
    }

    private static Path headphones() {
        Path band = new Path();
        band.moveTo(4, 15);
        band.lineTo(4, 12);
        band.arcTo(new RectF(4, 4, 20, 20), 180, 180);
        band.lineTo(20, 15);
        Path left = roundedRect(3, 13, 8, 20, 2f);
        Path right = roundedRect(16, 13, 21, 20, 2f);
        return union(stroke(band), union(left, right));
    }

    private static Path shoulders() {
        Path p = new Path();
        p.moveTo(4.5f, 20);
        p.cubicTo(5, 16, 8, 14, 12, 14);
        p.cubicTo(16, 14, 19, 16, 19.5f, 20);
        return p;
    }

    private static Path shouldersFill() {
        Path p = new Path();
        p.moveTo(4, 21);
        p.cubicTo(4.5f, 16.5f, 7.5f, 14, 12, 14);
        p.cubicTo(16.5f, 14, 19.5f, 16.5f, 20, 21);
        p.close();
        return p;
    }

    private static Path house() {
        Path p = new Path();
        p.moveTo(12, 3);
        p.lineTo(21, 11);
        p.lineTo(19, 11);
        p.lineTo(19, 20);
        p.lineTo(14.5f, 20);
        p.lineTo(14.5f, 14.5f);
        p.lineTo(9.5f, 14.5f);
        p.lineTo(9.5f, 20);
        p.lineTo(5, 20);
        p.lineTo(5, 11);
        p.lineTo(3, 11);
        p.close();
        return p;
    }

    /// Eight teeth around a ring, the centre cut out.
    private static Path gear() {
        Path teeth = new Path();
        for (int i = 0; i < 8; i++) {
            Path tooth = roundedRect(10.5f, 1.5f, 13.5f, 6.5f, 1f);
            Matrix m = new Matrix();
            m.setRotate(i * 45f, 12, 12);
            tooth.transform(m);
            teeth = union(teeth, tooth);
        }
        return minus(union(teeth, circle(12, 12, 7.5f)), circle(12, 12, 3f));
    }

    /// A rosette: twelve bumps round a disc.
    private static Path seal() {
        Path p = circle(12, 12, 8.5f);
        for (int i = 0; i < 12; i++) {
            double a = Math.toRadians(i * 30);
            p = union(p, circle(12 + (float) (7.5 * Math.cos(a)), 12 + (float) (7.5 * Math.sin(a)), 2.4f));
        }
        return p;
    }

    /// A bold D, for the OneDosh mark.
    private static Path letterD() {
        Path d = new Path();
        d.moveTo(8.5f, 7);
        d.lineTo(12, 7);
        d.cubicTo(15.5f, 7, 16.5f, 9.5f, 16.5f, 12);
        d.cubicTo(16.5f, 14.5f, 15.5f, 17, 12, 17);
        d.lineTo(8.5f, 17);
        d.close();
        return minus(d, roundedRect(10.8f, 9.3f, 13.8f, 14.7f, 1.5f));
    }

    private static Path shouldersAt(float cx) {
        Path p = new Path();
        p.moveTo(cx - 7, 20);
        p.cubicTo(cx - 6.5f, 16, cx - 3.5f, 14, cx, 14);
        p.cubicTo(cx + 3.5f, 14, cx + 6.5f, 16, cx + 7, 20);
        return p;
    }

    // MARK: Path arithmetic

    private static Path stroke(Path source) {
        return stroke(source, STROKE);
    }

    /// The outline of `source` stroked at `width`, as a fillable path.
    private static Path stroke(Path source, float width) {
        Paint p = new Paint();
        p.setStyle(Paint.Style.STROKE);
        p.setStrokeWidth(width);
        p.setStrokeCap(Paint.Cap.ROUND);
        p.setStrokeJoin(Paint.Join.ROUND);
        Path out = new Path();
        p.getFillPath(source, out);
        return out;
    }

    private static Path union(Path a, Path b) {
        Path out = new Path();
        out.op(a, b, Path.Op.UNION);
        return out;
    }

    private static Path minus(Path a, Path b) {
        Path out = new Path();
        out.op(a, b, Path.Op.DIFFERENCE);
        return out;
    }

    // MARK: Drawable

    @Override
    protected void onBoundsChange(Rect bounds) {
        float scale = Math.min(bounds.width(), bounds.height()) / BOX;
        matrix.setScale(scale, scale);
        matrix.postTranslate(bounds.left + (bounds.width() - BOX * scale) / 2f,
                             bounds.top + (bounds.height() - BOX * scale) / 2f);
        path.transform(matrix, scaled);
    }

    @Override
    public void draw(Canvas canvas) {
        canvas.drawPath(scaled, paint);
    }

    @Override public int getIntrinsicWidth() { return edge; }
    @Override public int getIntrinsicHeight() { return edge; }

    @Override
    public void setAlpha(int alpha) {
        paint.setAlpha(alpha);
        invalidateSelf();
    }

    @Override
    public void setColorFilter(ColorFilter filter) {
        paint.setColorFilter(filter);
        invalidateSelf();
    }

    @Override
    public int getOpacity() {
        return PixelFormat.TRANSLUCENT;
    }
}
