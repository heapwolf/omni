package com.omni;

import android.content.Context;
import android.graphics.Matrix;
import android.graphics.SurfaceTexture;
import android.media.MediaDataSource;
import android.media.MediaPlayer;
import android.view.Surface;
import android.view.TextureView;

/// Video.swift's view: a silent video from bytes in memory, played by the platform's
/// MediaPlayer onto a TextureView. A TextureView, not a SurfaceView: it fades, moves and clips
/// as any other view does. Not opaque, so until its first frame it shows what's under it.
public class OmniVideoView extends TextureView implements TextureView.SurfaceTextureListener {

    // Mirrored in Video+Android.swift.
    public static final int AT_START = 0;
    public static final int PLAYING  = 1;
    public static final int PAUSED   = 2;

    private byte[] bytes;
    private int playback = AT_START;
    private boolean fills = false;

    private SurfaceTexture texture;
    private Surface surface;
    private MediaPlayer player;
    private boolean isPrepared = false;
    private boolean isComplete = false;
    /// Where it was when its surface went (the view left the window): taken up from there.
    private int resumeAt = 0;
    private int videoWidth = 0, videoHeight = 0;
    /// The Swift EventHandlerVoid told when it plays to its end; 0 for none.
    private long endPtr = 0;
    /// Told this long before the end instead, in milliseconds: what follows starts as it ends.
    private int endLeadMs = 0;
    private final Runnable nearEnd = () -> {
        MediaPlayer mp = player;
        if (mp != null && mp.isPlaying() && endPtr != 0) OmniEventBridge.dispatchVoid(endPtr);
    };

    public OmniVideoView(Context context) {
        super(context);
        setOpaque(false);
        setSurfaceTextureListener(this);
    }

    /// The bytes to play. Swift sends them only when they change.
    public void setVideo(byte[] data) {
        bytes = data;
        resumeAt = 0;
        close();
        open();
    }

    public void setPlayback(int next) {
        if (next == playback) return;
        playback = next;
        apply();
    }

    public void setFill(boolean fill) {
        if (fill == fills) return;
        fills = fill;
        fit();
    }

    public void setEndHandler(long ptr) { endPtr = ptr; }

    public void setEndLead(int ms) {
        if (ms == endLeadMs) return;
        endLeadMs = ms;
        armEnd();
    }

    /// The lead's call, timed from where it plays now; none while it doesn't.
    private void armEnd() {
        removeCallbacks(nearEnd);
        MediaPlayer mp = player;
        if (endLeadMs <= 0 || mp == null || !isPrepared) return;
        try {
            if (!mp.isPlaying()) return;
            int left = mp.getDuration() - mp.getCurrentPosition() - endLeadMs;
            postDelayed(nearEnd, Math.max(0, left));
        } catch (IllegalStateException ignored) {}
    }

    /// Unmounted: the player goes; the bytes stay, should it be shown again.
    public void release() {
        endPtr = 0;
        close();
    }

    private void open() {
        if (bytes == null || texture == null || player != null) return;
        final MediaPlayer mp = new MediaPlayer();
        player = mp;
        isPrepared = false;
        isComplete = false;
        try {
            surface = new Surface(texture);
            mp.setSurface(surface);
            mp.setDataSource(new Bytes(bytes));
            mp.setVolume(0f, 0f);
            mp.setOnPreparedListener(p -> {
                if (p != player) return;
                isPrepared = true;
                videoWidth = p.getVideoWidth();
                videoHeight = p.getVideoHeight();
                fit();
                requestLayout();
                // Shows the frame there, and the first one at the start.
                p.seekTo(resumeAt, MediaPlayer.SEEK_CLOSEST);
                apply();
            });
            mp.setOnVideoSizeChangedListener((p, w, h) -> {
                if (p != player || w == 0 || h == 0) return;
                videoWidth = w;
                videoHeight = h;
                fit();
            });
            // Stays on its last frame.
            mp.setOnCompletionListener(p -> {
                if (p != player) return;
                isComplete = true;
                if (endPtr != 0 && endLeadMs <= 0) OmniEventBridge.dispatchVoid(endPtr);
            });
            // Nothing to show: what's under it shows.
            mp.setOnErrorListener((p, what, extra) -> { if (p == player) close(); return true; });
            mp.prepareAsync();
        } catch (Exception e) {
            close();
        }
    }

    private void close() {
        removeCallbacks(nearEnd);
        if (player != null) {
            if (isPrepared) {
                try { resumeAt = isComplete ? player.getDuration() : player.getCurrentPosition(); } catch (Exception ignored) {}
            }
            try { player.release(); } catch (Exception ignored) {}
            player = null;
        }
        if (surface != null) { surface.release(); surface = null; }
        isPrepared = false;
    }

    private void apply() {
        MediaPlayer mp = player;
        if (mp == null || !isPrepared) return;
        try {
            switch (playback) {
                case AT_START:
                    if (mp.isPlaying()) mp.pause();
                    mp.seekTo(0, MediaPlayer.SEEK_CLOSEST);
                    isComplete = false;
                    resumeAt = 0;
                    break;
                case PLAYING:
                    // At its end it stays on its last frame: start() would begin again.
                    if (!isComplete && !mp.isPlaying()) mp.start();
                    break;
                default:
                    if (mp.isPlaying()) mp.pause();
                    break;
            }
        } catch (IllegalStateException ignored) {}
        armEnd();
    }

    /// A TextureView stretches the video to its own size: scaled back to the video's
    /// proportions, fitted inside or filling it, about the centre.
    private void fit() {
        int w = getWidth(), h = getHeight();
        if (w == 0 || h == 0 || videoWidth == 0 || videoHeight == 0) return;
        float sx = (float) w / videoWidth, sy = (float) h / videoHeight;
        float s = fills ? Math.max(sx, sy) : Math.min(sx, sy);
        Matrix m = new Matrix();
        m.setScale(videoWidth * s / w, videoHeight * s / h, w / 2f, h / 2f);
        setTransform(m);
    }

    @Override protected void onSizeChanged(int w, int h, int oldw, int oldh) {
        super.onSizeChanged(w, h, oldw, oldh);
        fit();
    }

    /// Not resizable (no exact size given), it is the video's own size.
    @Override protected void onMeasure(int widthSpec, int heightSpec) {
        setMeasuredDimension(resolveSize(videoWidth, widthSpec), resolveSize(videoHeight, heightSpec));
    }

    @Override public void onSurfaceTextureAvailable(SurfaceTexture st, int width, int height) {
        texture = st;
        open();
    }

    @Override public void onSurfaceTextureSizeChanged(SurfaceTexture st, int width, int height) { fit(); }

    @Override public boolean onSurfaceTextureDestroyed(SurfaceTexture st) {
        close();
        texture = null;
        return true;
    }

    @Override public void onSurfaceTextureUpdated(SurfaceTexture st) {}

    /// The bytes, read in place: no file.
    private static final class Bytes extends MediaDataSource {
        private final byte[] data;
        Bytes(byte[] data) { this.data = data; }

        @Override public int readAt(long position, byte[] buffer, int offset, int size) {
            if (position >= data.length) return -1;
            int n = (int) Math.min(size, data.length - position);
            System.arraycopy(data, (int) position, buffer, offset, n);
            return n;
        }

        @Override public long getSize() { return data.length; }
        @Override public void close() {}
    }
}
