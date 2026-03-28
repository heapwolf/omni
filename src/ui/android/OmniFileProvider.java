// androidx FileProvider is a Gradle dependency this build cannot resolve.
package com.omni;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.provider.OpenableColumns;
import java.io.File;
import java.io.FileNotFoundException;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

public class OmniFileProvider extends ContentProvider {
    private static final Map<String, String> PENDING = new ConcurrentHashMap<>();

    public static Uri uriFor(Context context, File file) {
        String token = UUID.randomUUID().toString();
        PENDING.put(token, file.getAbsolutePath());
        String authority = context.getPackageName() + ".omnifileprovider";
        return new Uri.Builder().scheme("content").authority(authority).appendPath(token).build();
    }

    private File fileFor(Uri uri) {
        String token = uri.getLastPathSegment();
        String path = token == null ? null : PENDING.get(token);
        return path == null ? null : new File(path);
    }

    @Override
    public boolean onCreate() {
        return true;
    }

    @Override
    public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
        File file = fileFor(uri);
        if (file == null) throw new FileNotFoundException("Unknown Omni file token: " + uri);
        int pfdMode = mode.contains("w")
            ? ParcelFileDescriptor.MODE_READ_WRITE | ParcelFileDescriptor.MODE_CREATE
            : ParcelFileDescriptor.MODE_READ_ONLY;
        return ParcelFileDescriptor.open(file, pfdMode);
    }

    @Override
    public Cursor query(Uri uri, String[] projection, String selection, String[] selectionArgs, String sortOrder) {
        File file = fileFor(uri);
        if (file == null) return null;
        MatrixCursor cursor = new MatrixCursor(new String[]{ OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE });
        cursor.addRow(new Object[]{ file.getName(), file.length() });
        return cursor;
    }

    @Override
    public String getType(Uri uri) {
        return "image/jpeg";
    }

    @Override
    public Uri insert(Uri uri, ContentValues values) {
        return null;
    }

    @Override
    public int delete(Uri uri, String selection, String[] selectionArgs) {
        return 0;
    }

    @Override
    public int update(Uri uri, ContentValues values, String selection, String[] selectionArgs) {
        return 0;
    }
}
