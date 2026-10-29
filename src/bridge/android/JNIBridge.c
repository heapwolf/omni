// src/lib/CAndroid/JNIBridge.c
#ifdef __ANDROID__
#include "JNIBridge.h"
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <android/log.h>
#include <stdarg.h>

// --- Global Context References ---
JavaVM* global_jvm = NULL;
jobject global_activity = NULL;

static void omni_jni_clear_pending(JNIEnv *env) {
    if ((*env)->ExceptionCheck(env)) {
        (*env)->ExceptionClear(env);
    }
}

// A NULL jmethodID aborts the process.
void omni_jni_log(const char *tag, const char *message) {
    __android_log_print(ANDROID_LOG_INFO, tag ? tag : "Omni", "%s", message ? message : "");
}

static jmethodID omni_jni_lookup(JNIEnv *env, jclass clazz,
                                 const char* methodName, const char* signature) {
    jmethodID method = (*env)->GetMethodID(env, clazz, methodName, signature);
    if (!method) {
        omni_jni_clear_pending(env);
        __android_log_print(ANDROID_LOG_ERROR, "Omni",
                            "no method %s%s on this class; skipping",
                            methodName, signature);
    }
    return method;
}

/// Calls a void instance method, logging and skipping if it does not resolve.
static void omni_jni_call(JNIEnv *env, jobject obj, const char* name,
                          const char* signature, ...) {
    jclass clazz = (*env)->GetObjectClass(env, obj);
    jmethodID method = omni_jni_lookup(env, clazz, name, signature);
    if (method) {
        va_list args;
        va_start(args, signature);
        (*env)->CallVoidMethodV(env, obj, method, args);
        va_end(args);
    }
    (*env)->DeleteLocalRef(env, clazz);
}

/// Asks Java to begin ticking the main queue. Called once, from init.
static void omni_jni_start_main_pump(JNIEnv *env) {
    jclass bridge = (*env)->FindClass(env, "com/omni/OmniEventBridge");
    if (!bridge) {
        omni_jni_clear_pending(env);
        __android_log_print(ANDROID_LOG_ERROR, "Omni",
                            "no OmniEventBridge; async work will never run");
        return;
    }
    jmethodID start = (*env)->GetStaticMethodID(env, bridge, "startMainQueuePump", "()V");
    if (!start) {
        omni_jni_clear_pending(env);
        __android_log_print(ANDROID_LOG_ERROR, "Omni",
                            "no OmniEventBridge.startMainQueuePump; async work will never run");
        (*env)->DeleteLocalRef(env, bridge);
        return;
    }
    (*env)->CallStaticVoidMethod(env, bridge, start);
    (*env)->DeleteLocalRef(env, bridge);
}

void omni_jni_init(JNIEnv *env, jobject activity) {
    // Cache the JVM and a global ref to the MainActivity.
    (*env)->GetJavaVM(env, &global_jvm);
    global_activity = (*env)->NewGlobalRef(env, activity);
    // Start the main-queue pump; see below.
    omni_jni_start_main_pump(env);
}


// Nothing drains libdispatch's main queue here; this pump is what runs MainActor jobs.
extern void _dispatch_main_queue_callback_4CF(void *msg);

/// Drains ready main-queue work. Must run on the thread owning the main queue.
JNIEXPORT void JNICALL Java_com_omni_OmniEventBridge_drainMainQueue(JNIEnv *env, jclass clazz) {
    (void)env; (void)clazz;
    _dispatch_main_queue_callback_4CF(NULL);
}



jobject omni_jni_create_view(JNIEnv *env, const char* classPath) {
    jclass clazz = (*env)->FindClass(env, classPath);
    if (!clazz) {
        omni_jni_clear_pending(env);
        return NULL;
    }

    // Every View subclass takes a Context in its one-argument constructor.
    jmethodID constructor = (*env)->GetMethodID(env, clazz, "<init>", "(Landroid/content/Context;)V");
    if (!constructor) {
        omni_jni_clear_pending(env);
        (*env)->DeleteLocalRef(env, clazz);
        return NULL;
    }

    jobject local = (*env)->NewObject(env, clazz, constructor, global_activity);
    (*env)->DeleteLocalRef(env, clazz);
    if (!local) {
        omni_jni_clear_pending(env);
        return NULL;
    }

    // Global ref: a local one dies when the native call returns.
    jobject global = (*env)->NewGlobalRef(env, local);
    (*env)->DeleteLocalRef(env, local);
    return global;
}

void omni_jni_call_void_method_string(JNIEnv *env, jobject obj, const char* methodName, const char* arg) {
    jclass clazz = (*env)->GetObjectClass(env, obj);

    // setText and friends are declared over CharSequence; fall back to String.
    jmethodID method = (*env)->GetMethodID(env, clazz, methodName, "(Ljava/lang/CharSequence;)V");
    if (!method) {
        omni_jni_clear_pending(env);
        method = omni_jni_lookup(env, clazz, methodName, "(Ljava/lang/String;)V");
    }

    if (method) {
        jstring value = (*env)->NewStringUTF(env, arg ? arg : "");
        (*env)->CallVoidMethod(env, obj, method, value);
        (*env)->DeleteLocalRef(env, value);
    } else {
        omni_jni_clear_pending(env);
    }

    (*env)->DeleteLocalRef(env, clazz);
}

jobject omni_jni_activity(void) {
    return global_activity;
}

JNIEnv* omni_get_env(void) {
    JNIEnv *env = NULL;
    if (global_jvm) {
        (*global_jvm)->AttachCurrentThread(global_jvm, &env, NULL);
    }
    return env;
}

/// One of the app's classes (com/omni/...), from any thread. FindClass on a
/// thread attached from native code sees only the system's classes, so a
/// Keystore call from a Swift task found no OmniDeviceKey; the activity's
/// class loader sees the app's. A local ref, as FindClass gives.
static jclass omni_jni_app_class(JNIEnv *env, const char *name) {
    jclass clazz = (*env)->FindClass(env, name);
    if (clazz) return clazz;
    omni_jni_clear_pending(env);
    if (!global_activity) return NULL;

    char dotted[256];
    size_t i = 0;
    for (; name[i] && i < sizeof(dotted) - 1; i++) dotted[i] = name[i] == '/' ? '.' : name[i];
    dotted[i] = 0;

    jclass activityClass = (*env)->GetObjectClass(env, global_activity);
    jmethodID getLoader = (*env)->GetMethodID(env, activityClass, "getClassLoader", "()Ljava/lang/ClassLoader;");
    jobject loader = getLoader ? (*env)->CallObjectMethod(env, global_activity, getLoader) : NULL;
    omni_jni_clear_pending(env);
    jclass loaderClass = loader ? (*env)->GetObjectClass(env, loader) : NULL;
    jmethodID loadClass = loaderClass
        ? (*env)->GetMethodID(env, loaderClass, "loadClass", "(Ljava/lang/String;)Ljava/lang/Class;") : NULL;
    jstring jName = (*env)->NewStringUTF(env, dotted);
    clazz = loadClass ? (jclass)(*env)->CallObjectMethod(env, loader, loadClass, jName) : NULL;
    omni_jni_clear_pending(env);

    (*env)->DeleteLocalRef(env, jName);
    if (loaderClass) (*env)->DeleteLocalRef(env, loaderClass);
    if (loader) (*env)->DeleteLocalRef(env, loader);
    (*env)->DeleteLocalRef(env, activityClass);
    return clazz;
}

// Android Layout Constants
const int MATCH_PARENT = -1;
const int WRAP_CONTENT = -2;
const int OMNI_LAYOUT_KEEP = -3;

// Android setters take pixels; the framework measures in points.
static float omni_density = 0.0f;

static float omni_jni_density(JNIEnv *env) {
    if (omni_density > 0.0f) return omni_density;
    omni_density = 1.0f;

    jclass ctxClass = (*env)->GetObjectClass(env, global_activity);
    jmethodID getResources = omni_jni_lookup(env, ctxClass, "getResources",
        "()Landroid/content/res/Resources;");
    (*env)->DeleteLocalRef(env, ctxClass);
    if (!getResources) return omni_density;

    jobject resources = (*env)->CallObjectMethod(env, global_activity, getResources);
    if (!resources) { omni_jni_clear_pending(env); return omni_density; }

    jclass resClass = (*env)->GetObjectClass(env, resources);
    jmethodID getMetrics = omni_jni_lookup(env, resClass, "getDisplayMetrics",
        "()Landroid/util/DisplayMetrics;");
    (*env)->DeleteLocalRef(env, resClass);

    if (getMetrics) {
        jobject metrics = (*env)->CallObjectMethod(env, resources, getMetrics);
        if (metrics) {
            jclass metricsClass = (*env)->GetObjectClass(env, metrics);
            jfieldID density = (*env)->GetFieldID(env, metricsClass, "density", "F");
            if (density) {
                omni_density = (*env)->GetFloatField(env, metrics, density);
            } else {
                omni_jni_clear_pending(env);
            }
            (*env)->DeleteLocalRef(env, metricsClass);
            (*env)->DeleteLocalRef(env, metrics);
        } else {
            omni_jni_clear_pending(env);
        }
    }
    (*env)->DeleteLocalRef(env, resources);

    if (omni_density <= 0.0f) omni_density = 1.0f;
    return omni_density;
}

/// A layout dimension in pixels. The three negatives are modes, and 0 is the
/// weighted-child idiom a Spacer relies on; none of them scale.
static int omni_jni_px(JNIEnv *env, int points) {
    if (points == MATCH_PARENT || points == WRAP_CONTENT
        || points == OMNI_LAYOUT_KEEP || points == 0) {
        return points;
    }
    return (int)(points * omni_jni_density(env) + 0.5f);
}

/// The same conversion where the platform takes a float.
static float omni_jni_pxf(JNIEnv *env, float points) {
    return points * omni_jni_density(env);
}

// Android Gravity Constants
const int GRAVITY_LEFT = 3;
const int GRAVITY_RIGHT = 5;
const int GRAVITY_CENTER_HORIZONTAL = 1;
const int GRAVITY_CENTER_VERTICAL = 16;
const int GRAVITY_CENTER = 17;

// --- Hierarchy & Layout Parameters ---
void omni_jni_add_view(JNIEnv *env, jobject parent, jobject child) {
    jclass viewGroupClass = (*env)->FindClass(env, "android/view/ViewGroup");
    jmethodID addViewMethod = omni_jni_lookup(env, viewGroupClass, "addView", "(Landroid/view/View;)V");
    if (addViewMethod) {
        (*env)->CallVoidMethod(env, parent, addViewMethod, child);
    }
    (*env)->DeleteLocalRef(env, viewGroupClass);
}

// Detaches a view. A single-child container throws when a replacement is
// added over the old one, so a dropped view has to leave its parent.
void omni_jni_remove_view(JNIEnv *env, jobject child) {
    jclass viewClass = (*env)->FindClass(env, "android/view/View");
    jmethodID getParent = omni_jni_lookup(env, viewClass, "getParent", "()Landroid/view/ViewParent;");
    (*env)->DeleteLocalRef(env, viewClass);
    if (!getParent) return;

    jobject parent = (*env)->CallObjectMethod(env, child, getParent);
    if (!parent) {
        // Never attached, or the content view itself.
        omni_jni_clear_pending(env);
        return;
    }

    // getParent returns a ViewParent: the top of the hierarchy is a ViewRootImpl.
    jclass viewGroupClass = (*env)->FindClass(env, "android/view/ViewGroup");
    if ((*env)->IsInstanceOf(env, parent, viewGroupClass)) {
        jmethodID removeView = omni_jni_lookup(env, viewGroupClass, "removeView", "(Landroid/view/View;)V");
        if (removeView) {
            (*env)->CallVoidMethod(env, parent, removeView, child);
        }
    }
    (*env)->DeleteLocalRef(env, viewGroupClass);
    (*env)->DeleteLocalRef(env, parent);
}

// A replaced view's insertion and removal; see OmniEventBridge.animateReplacement.
// `arriving` or `leaving` may be NULL.
void omni_jni_animate_replacement(JNIEnv *env, jobject scene_root, jobject parent, jobject arriving,
                                  jobject leaving, int duration_ms, int curve,
                                  float in_x, float in_y, int in_fade,
                                  float out_x, float out_y, int out_fade) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    if (!bridgeClass) {
        omni_jni_clear_pending(env);
        return;
    }
    jmethodID method = (*env)->GetStaticMethodID(env, bridgeClass, "animateReplacement",
        "(Landroid/view/ViewGroup;Landroid/view/ViewGroup;Landroid/view/View;Landroid/view/View;JIFFZFFZ)V");
    if (method) {
        (*env)->CallStaticVoidMethod(env, bridgeClass, method, scene_root, parent, arriving, leaving,
                                     (jlong)duration_ms, curve, in_x, in_y, (jboolean)in_fade,
                                     out_x, out_y, (jboolean)out_fade);
    }
    omni_jni_clear_pending(env);
    (*env)->DeleteLocalRef(env, bridgeClass);
}

// Moves `child` to `index` among `parent`'s children. insertChild appends, so a
// replaced view is moved back to where the old one was. Its LayoutParams stay.
void omni_jni_move_child(JNIEnv *env, jobject parent, jobject child, int index) {
    jclass viewGroupClass = (*env)->FindClass(env, "android/view/ViewGroup");
    jmethodID indexOf = omni_jni_lookup(env, viewGroupClass, "indexOfChild", "(Landroid/view/View;)I");
    jmethodID count = omni_jni_lookup(env, viewGroupClass, "getChildCount", "()I");
    jmethodID removeView = omni_jni_lookup(env, viewGroupClass, "removeView", "(Landroid/view/View;)V");
    jmethodID addView = omni_jni_lookup(env, viewGroupClass, "addView", "(Landroid/view/View;I)V");
    if (indexOf && count && removeView && addView) {
        int current = (*env)->CallIntMethod(env, parent, indexOf, child);
        int total = (*env)->CallIntMethod(env, parent, count);
        if (index > total - 1) index = total - 1;
        if (current >= 0 && current != index && index >= 0) {
            (*env)->CallVoidMethod(env, parent, removeView, child);
            (*env)->CallVoidMethod(env, parent, addView, child, index);
        }
    }
    omni_jni_clear_pending(env);
    (*env)->DeleteLocalRef(env, viewGroupClass);
}

void omni_jni_set_layout_params(JNIEnv *env, jobject view, int width, int height) {
    width = omni_jni_px(env, width);
    height = omni_jni_px(env, height);

    jclass viewClass = (*env)->GetObjectClass(env, view);
    jmethodID setLayoutParams = (*env)->GetMethodID(env, viewClass, "setLayoutParams",
        "(Landroid/view/ViewGroup$LayoutParams;)V");
    jmethodID getLayoutParams = (*env)->GetMethodID(env, viewClass, "getLayoutParams",
        "()Landroid/view/ViewGroup$LayoutParams;");

    jobject existing = getLayoutParams
        ? (*env)->CallObjectMethod(env, view, getLayoutParams) : NULL;

    if (existing) {
        // Resize the parent's params: a plain LayoutParams after attach throws.
        jclass existingClass = (*env)->GetObjectClass(env, existing);
        jfieldID widthField = (*env)->GetFieldID(env, existingClass, "width", "I");
        jfieldID heightField = (*env)->GetFieldID(env, existingClass, "height", "I");

        if (widthField && heightField) {
            // KEEP leaves an axis alone; pinning it collapses a wrapper with no intrinsic size.
            if (width != OMNI_LAYOUT_KEEP) {
                (*env)->SetIntField(env, existing, widthField, width);
            }
            if (height != OMNI_LAYOUT_KEEP) {
                (*env)->SetIntField(env, existing, heightField, height);
            }
            // Reassign to request a fresh layout pass.
            (*env)->CallVoidMethod(env, view, setLayoutParams, existing);
        } else {
            omni_jni_clear_pending(env);
        }

        (*env)->DeleteLocalRef(env, existingClass);
        (*env)->DeleteLocalRef(env, existing);
    } else {
        // Detached: addView converts a generic instance to the parent's subclass.
        omni_jni_clear_pending(env);
        jclass paramsClass = (*env)->FindClass(env, "android/view/ViewGroup$LayoutParams");
        jmethodID constructor = (*env)->GetMethodID(env, paramsClass, "<init>", "(II)V");
        // Nothing to keep yet, so KEEP means "whatever the parent decides".
        jobject params = (*env)->NewObject(env, paramsClass, constructor,
                                           width == OMNI_LAYOUT_KEEP ? WRAP_CONTENT : width,
                                           height == OMNI_LAYOUT_KEEP ? WRAP_CONTENT : height);
        (*env)->CallVoidMethod(env, view, setLayoutParams, params);
        (*env)->DeleteLocalRef(env, params);
        (*env)->DeleteLocalRef(env, paramsClass);
    }

    (*env)->DeleteLocalRef(env, viewClass);
}

void omni_jni_set_linear_layout_params(JNIEnv *env, jobject view, int width, int height, float weight) {
    width = omni_jni_px(env, width);
    height = omni_jni_px(env, height);

    jclass viewClass = (*env)->GetObjectClass(env, view);
    jmethodID setLayoutParams = (*env)->GetMethodID(env, viewClass, "setLayoutParams",
        "(Landroid/view/ViewGroup$LayoutParams;)V");
    jmethodID getLayoutParams = (*env)->GetMethodID(env, viewClass, "getLayoutParams",
        "()Landroid/view/ViewGroup$LayoutParams;");

    jclass linearParamsClass = (*env)->FindClass(env, "android/widget/LinearLayout$LayoutParams");
    jobject existing = getLayoutParams
        ? (*env)->CallObjectMethod(env, view, getLayoutParams) : NULL;

    if (existing) {
        // Resize in place: LinearLayout.LayoutParams on a FrameLayout child makes
        // FrameLayout.onMeasure fail its cast.
        jclass existingClass = (*env)->GetObjectClass(env, existing);
        jfieldID widthField = (*env)->GetFieldID(env, existingClass, "width", "I");
        jfieldID heightField = (*env)->GetFieldID(env, existingClass, "height", "I");

        if (widthField && heightField) {
            (*env)->SetIntField(env, existing, widthField, width);
            (*env)->SetIntField(env, existing, heightField, height);
        } else {
            omni_jni_clear_pending(env);
        }

        // weight exists only on LinearLayout.LayoutParams.
        if ((*env)->IsInstanceOf(env, existing, linearParamsClass)) {
            jfieldID weightField = (*env)->GetFieldID(env, existingClass, "weight", "F");
            if (weightField) {
                (*env)->SetFloatField(env, existing, weightField, weight);
            } else {
                omni_jni_clear_pending(env);
            }
        }

        (*env)->CallVoidMethod(env, view, setLayoutParams, existing);
        (*env)->DeleteLocalRef(env, existingClass);
        (*env)->DeleteLocalRef(env, existing);
    } else {
        // addView converts these to the parent's subclass, dropping weight if it is
        // not a LinearLayout.
        omni_jni_clear_pending(env);
        jmethodID constructor = (*env)->GetMethodID(env, linearParamsClass, "<init>", "(IIF)V");
        jobject params = (*env)->NewObject(env, linearParamsClass, constructor, width, height, weight);
        (*env)->CallVoidMethod(env, view, setLayoutParams, params);
        (*env)->DeleteLocalRef(env, params);
    }

    (*env)->DeleteLocalRef(env, linearParamsClass);
    (*env)->DeleteLocalRef(env, viewClass);
}

// --- UI Styling (Colors, Fonts, Gravity) ---
void omni_jni_set_text_color(JNIEnv *env, jobject view, int a, int r, int g, int b) {
    // Java equivalent: Color.argb(a, r, g, b)
    int color = (a & 0xFF) << 24 | (r & 0xFF) << 16 | (g & 0xFF) << 8 | (b & 0xFF);
    omni_jni_call(env, view, "setTextColor", "(I)V", color);
}

void omni_jni_set_padding(JNIEnv *env, jobject view, int left, int top, int right, int bottom) {
    omni_jni_call(env, view, "setPadding", "(IIII)V",
                  omni_jni_px(env, left), omni_jni_px(env, top),
                  omni_jni_px(env, right), omni_jni_px(env, bottom));
}

void omni_jni_set_shadow(JNIEnv *env, jobject container, float radius) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    if (!bridgeClass) return;
    jmethodID method = (*env)->GetStaticMethodID(env, bridgeClass, "setShadow", "(Landroid/view/View;F)V");
    if (method) (*env)->CallStaticVoidMethod(env, bridgeClass, method, container, omni_jni_pxf(env, radius));
    omni_jni_clear_pending(env);
    (*env)->DeleteLocalRef(env, bridgeClass);
}

void omni_jni_set_image_scale(JNIEnv *env, jobject view, int fill) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    if (!bridgeClass) return;
    jmethodID method = (*env)->GetStaticMethodID(env, bridgeClass, "setImageScale", "(Landroid/widget/ImageView;Z)V");
    if (method) (*env)->CallStaticVoidMethod(env, bridgeClass, method, view, (jboolean)(fill != 0));
    omni_jni_clear_pending(env);
    (*env)->DeleteLocalRef(env, bridgeClass);
}

void omni_jni_set_transform(JNIEnv *env, jobject view, float x, float y, float scale) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    if (!bridgeClass) return;
    jmethodID method = (*env)->GetStaticMethodID(env, bridgeClass, "setTransform", "(Landroid/view/View;FFF)V");
    if (method) {
        (*env)->CallStaticVoidMethod(env, bridgeClass, method, view,
                                     omni_jni_pxf(env, x), omni_jni_pxf(env, y), scale);
    }
    omni_jni_clear_pending(env);
    (*env)->DeleteLocalRef(env, bridgeClass);
}

void omni_jni_set_alpha(JNIEnv *env, jobject view, float alpha) {
    omni_jni_call(env, view, "setAlpha", "(F)V", alpha);
}

void omni_jni_set_elevation(JNIEnv *env, jobject view, float elevation) {
    omni_jni_call(env, view, "setElevation", "(F)V", omni_jni_pxf(env, elevation));
}

void omni_jni_set_background_color(JNIEnv *env, jobject view, int a, int r, int g, int b) {
    // Java equivalent: Color.argb(a, r, g, b)
    int color = (a & 0xFF) << 24 | (r & 0xFF) << 16 | (g & 0xFF) << 8 | (b & 0xFF);
    omni_jni_call(env, view, "setBackgroundColor", "(I)V", color);
}

void omni_jni_set_box(JNIEnv *env, jobject view, int hasFill,
                      int fa, int fr, int fg, int fb,
                      int strokePoints, int sa, int sr, int sg, int sb) {
    int fill = (fa & 0xFF) << 24 | (fr & 0xFF) << 16 | (fg & 0xFF) << 8 | (fb & 0xFF);
    int stroke = (sa & 0xFF) << 24 | (sr & 0xFF) << 16 | (sg & 0xFF) << 8 | (sb & 0xFF);
    int strokeWidth = (int)(strokePoints * omni_jni_density(env) + 0.5f);
    if (strokePoints > 0 && strokeWidth < 1) strokeWidth = 1;

    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    if (!bridgeClass) { omni_jni_clear_pending(env); return; }
    jmethodID method = (*env)->GetStaticMethodID(env, bridgeClass, "setBox",
        "(Landroid/view/View;ZIII)V");
    if (method) {
        (*env)->CallStaticVoidMethod(env, bridgeClass, method, view,
                                     (jboolean)(hasFill != 0), fill, strokeWidth, stroke);
    } else {
        omni_jni_clear_pending(env);
    }
    (*env)->DeleteLocalRef(env, bridgeClass);
}

void omni_jni_set_monospace(JNIEnv *env, jobject view, int isMonospaced) {
    jclass typefaceClass = (*env)->FindClass(env, "android/graphics/Typeface");
    if (!typefaceClass) { omni_jni_clear_pending(env); return; }

    // Typeface.MONOSPACE / DEFAULT are static fields on Typeface.
    jfieldID fieldID = (*env)->GetStaticFieldID(env, typefaceClass,
        isMonospaced ? "MONOSPACE" : "DEFAULT", "Landroid/graphics/Typeface;");
    if (!fieldID) {
        omni_jni_clear_pending(env);
        (*env)->DeleteLocalRef(env, typefaceClass);
        return;
    }

    jobject typeface = (*env)->GetStaticObjectField(env, typefaceClass, fieldID);
    jclass viewClass = (*env)->GetObjectClass(env, view);
    jmethodID setTypeface = omni_jni_lookup(env, viewClass, "setTypeface",
        "(Landroid/graphics/Typeface;)V");
    if (setTypeface) {
        (*env)->CallVoidMethod(env, view, setTypeface, typeface);
    }

    (*env)->DeleteLocalRef(env, viewClass);
    (*env)->DeleteLocalRef(env, typeface);
    (*env)->DeleteLocalRef(env, typefaceClass);
}

int omni_jni_register_font(JNIEnv *env, const char* family, const char* path) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    if (!bridgeClass) { omni_jni_clear_pending(env); return 0; }
    jmethodID method = (*env)->GetStaticMethodID(env, bridgeClass, "registerFont",
        "(Ljava/lang/String;Ljava/lang/String;)Z");
    int ok = 0;
    if (method) {
        jstring jFamily = (*env)->NewStringUTF(env, family);
        jstring jPath = (*env)->NewStringUTF(env, path);
        ok = (*env)->CallStaticBooleanMethod(env, bridgeClass, method, jFamily, jPath) ? 1 : 0;
        (*env)->DeleteLocalRef(env, jFamily);
        (*env)->DeleteLocalRef(env, jPath);
    } else {
        omni_jni_clear_pending(env);
    }
    (*env)->DeleteLocalRef(env, bridgeClass);
    return ok;
}

// family may be NULL for the platform's own UI font.
void omni_jni_set_typeface(JNIEnv *env, jobject view, const char* family,
                           int weight, int italic, int monospaced) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    if (!bridgeClass) { omni_jni_clear_pending(env); return; }
    jmethodID method = (*env)->GetStaticMethodID(env, bridgeClass, "setTypeface",
        "(Landroid/widget/TextView;Ljava/lang/String;IZZ)V");
    if (method) {
        jstring jFamily = family ? (*env)->NewStringUTF(env, family) : NULL;
        (*env)->CallStaticVoidMethod(env, bridgeClass, method, view, jFamily,
                                     weight, (jboolean)italic, (jboolean)monospaced);
        if (jFamily) (*env)->DeleteLocalRef(env, jFamily);
    } else {
        omni_jni_clear_pending(env);
    }
    (*env)->DeleteLocalRef(env, bridgeClass);
}

void omni_jni_set_text_size(JNIEnv *env, jobject view, float size) {
    // setTextSize(float) defaults to SP (scaled pixels)
    omni_jni_call(env, view, "setTextSize", "(F)V", size);
}

// setLineSpacing takes extra pixels; setLetterSpacing takes ems, so tracking
// is divided by the font size at the call site.
void omni_jni_set_text_spacing(JNIEnv *env, jobject view, float linePoints, float letterEm) {
    jclass viewClass = (*env)->GetObjectClass(env, view);
    jmethodID setLineSpacing = omni_jni_lookup(env, viewClass, "setLineSpacing", "(FF)V");
    if (setLineSpacing) {
        (*env)->CallVoidMethod(env, view, setLineSpacing, omni_jni_pxf(env, linePoints), 1.0f);
    }
    jmethodID setLetterSpacing = omni_jni_lookup(env, viewClass, "setLetterSpacing", "(F)V");
    if (setLetterSpacing) {
        (*env)->CallVoidMethod(env, view, setLetterSpacing, letterEm);
    }
    (*env)->DeleteLocalRef(env, viewClass);
}

void omni_jni_set_secure_text(JNIEnv *env, jobject view) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    jmethodID method = (*env)->GetStaticMethodID(env, bridgeClass, "setSecureText", "(Landroid/widget/EditText;)V");
    (*env)->CallStaticVoidMethod(env, bridgeClass, method, view);
    (*env)->DeleteLocalRef(env, bridgeClass);
}

void omni_jni_set_gravity(JNIEnv *env, jobject view, int gravity) {
    jclass clazz = (*env)->GetObjectClass(env, view);
    jmethodID method = (*env)->GetMethodID(env, clazz, "setGravity", "(I)V");
    // No-op on views without setGravity.
    if (method != NULL) {
        (*env)->CallVoidMethod(env, view, method, gravity);
    } else {
        (*env)->ExceptionClear(env);
    }
    (*env)->DeleteLocalRef(env, clazz);
}

void omni_jni_set_child_gravity(JNIEnv *env, jobject child, int gravity) {
    jclass viewClass = (*env)->GetObjectClass(env, child);
    jmethodID setter = omni_jni_lookup(env, viewClass, "setLayoutParams",
        "(Landroid/view/ViewGroup$LayoutParams;)V");
    jmethodID getter = omni_jni_lookup(env, viewClass, "getLayoutParams",
        "()Landroid/view/ViewGroup$LayoutParams;");
    (*env)->DeleteLocalRef(env, viewClass);
    if (!setter || !getter) return;

    jobject params = (*env)->CallObjectMethod(env, child, getter);
    if (!params) {
        omni_jni_clear_pending(env);
        return;
    }

    // gravity lives on FrameLayout.LayoutParams; other parents have no such field.
    jclass frameParams = (*env)->FindClass(env, "android/widget/FrameLayout$LayoutParams");
    if (frameParams) {
        if ((*env)->IsInstanceOf(env, params, frameParams)) {
            jclass paramsClass = (*env)->GetObjectClass(env, params);
            jfieldID field = (*env)->GetFieldID(env, paramsClass, "gravity", "I");
            if (field) {
                (*env)->SetIntField(env, params, field, gravity);
                (*env)->CallVoidMethod(env, child, setter, params);
            } else {
                omni_jni_clear_pending(env);
            }
            (*env)->DeleteLocalRef(env, paramsClass);
        }
        (*env)->DeleteLocalRef(env, frameParams);
    } else {
        omni_jni_clear_pending(env);
    }

    (*env)->DeleteLocalRef(env, params);
}

// Arms an animation over the subtree at `root`. curve is AnimationCurve's
// ordinal; see OmniEventBridge.beginTransition.
void omni_jni_begin_transition(JNIEnv *env, jobject root, long durationMs, int curve) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    if (!bridgeClass) { omni_jni_clear_pending(env); return; }
    jmethodID method = (*env)->GetStaticMethodID(env, bridgeClass, "beginTransition",
        "(Landroid/view/ViewGroup;JI)V");
    if (method) {
        (*env)->CallStaticVoidMethod(env, bridgeClass, method, root, (jlong)durationMs, curve);
    } else {
        omni_jni_clear_pending(env);
    }
    (*env)->DeleteLocalRef(env, bridgeClass);
}

// The push/pop slide; counterpart of ZStack+Apple's CATransition.
void omni_jni_begin_navigation_transition(JNIEnv *env, jobject root, int isPush, long durationMs) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    if (!bridgeClass) { omni_jni_clear_pending(env); return; }
    jmethodID method = (*env)->GetStaticMethodID(env, bridgeClass, "beginNavigationTransition",
        "(Landroid/view/ViewGroup;ZJ)V");
    if (method) {
        (*env)->CallStaticVoidMethod(env, bridgeClass, method, root,
                                     (jboolean)isPush, (jlong)durationMs);
    } else {
        omni_jni_clear_pending(env);
    }
    (*env)->DeleteLocalRef(env, bridgeClass);
}

// --- Event Routing ---
void omni_jni_set_on_click(JNIEnv *env, jobject view, void* swift_ptr) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    jmethodID attachMethod = (*env)->GetStaticMethodID(env, bridgeClass, "attachOnClick", "(Landroid/view/View;J)V");

    (*env)->CallStaticVoidMethod(env, bridgeClass, attachMethod, view, (jlong)swift_ptr);

    (*env)->DeleteLocalRef(env, bridgeClass);
}

// A press: 1 down or back inside, 0 out or cancelled, 2 released inside, each
// through dispatchInt. See PressGesture+Android.swift.
void omni_jni_set_on_press(JNIEnv *env, jobject view, void* swift_ptr) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    if (!bridgeClass) { omni_jni_clear_pending(env); return; }
    jmethodID attachMethod = (*env)->GetStaticMethodID(env, bridgeClass, "attachOnPress", "(Landroid/view/View;J)V");
    if (attachMethod) {
        (*env)->CallStaticVoidMethod(env, bridgeClass, attachMethod, view, (jlong)swift_ptr);
    } else {
        omni_jni_clear_pending(env);
    }
    (*env)->DeleteLocalRef(env, bridgeClass);
}

// A haptic, by OmniEventBridge.haptic's numbering; see SensoryFeedback.swift.
void omni_jni_haptic(JNIEnv *env, int kind) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    if (!bridgeClass) { omni_jni_clear_pending(env); return; }
    jmethodID method = (*env)->GetStaticMethodID(env, bridgeClass, "haptic", "(I)V");
    if (method) {
        (*env)->CallStaticVoidMethod(env, bridgeClass, method, (jint)kind);
    } else {
        omni_jni_clear_pending(env);
    }
    (*env)->DeleteLocalRef(env, bridgeClass);
}

// "Remove animations": see EnvironmentValues.accessibilityReduceMotion.
int omni_jni_reduce_motion(JNIEnv *env) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    if (!bridgeClass) { omni_jni_clear_pending(env); return 0; }
    jmethodID method = (*env)->GetStaticMethodID(env, bridgeClass, "reduceMotion", "()Z");
    int reduce = 0;
    if (method) {
        reduce = (*env)->CallStaticBooleanMethod(env, bridgeClass, method) ? 1 : 0;
    } else {
        omni_jni_clear_pending(env);
    }
    (*env)->DeleteLocalRef(env, bridgeClass);
    return reduce;
}

// See OmniEventBridge.setGlass. Colours are packed ARGB; the radius is in points.
void omni_jni_set_glass(JNIEnv *env, jobject view, int fill, int stroke, float radius, int circular) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    if (!bridgeClass) { omni_jni_clear_pending(env); return; }
    jmethodID method = (*env)->GetStaticMethodID(env, bridgeClass, "setGlass", "(Landroid/view/View;IIFZ)V");
    if (method) {
        (*env)->CallStaticVoidMethod(env, bridgeClass, method, view, (jint)fill, (jint)stroke,
                                     omni_jni_pxf(env, radius), circular ? JNI_TRUE : JNI_FALSE);
    } else {
        omni_jni_clear_pending(env);
    }
    (*env)->DeleteLocalRef(env, bridgeClass);
}

// .frame(minWidth:minHeight:), in points; 0 leaves an axis free.
void omni_jni_set_minimum_size(JNIEnv *env, jobject view, float width, float height) {
    jclass viewClass = (*env)->GetObjectClass(env, view);
    jmethodID setMinimumWidth = omni_jni_lookup(env, viewClass, "setMinimumWidth", "(I)V");
    jmethodID setMinimumHeight = omni_jni_lookup(env, viewClass, "setMinimumHeight", "(I)V");
    if (setMinimumWidth) (*env)->CallVoidMethod(env, view, setMinimumWidth, (jint)omni_jni_pxf(env, width));
    if (setMinimumHeight) (*env)->CallVoidMethod(env, view, setMinimumHeight, (jint)omni_jni_pxf(env, height));
    (*env)->DeleteLocalRef(env, viewClass);
}

// Clipboard.copy; see OmniEventBridge.copyText. The text crosses as UTF-8
// bytes: NewStringUTF takes Modified UTF-8, and an emoji's four bytes are not.
void omni_jni_copy_text(JNIEnv *env, const char* text) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    if (!bridgeClass) { omni_jni_clear_pending(env); return; }
    jmethodID method = (*env)->GetStaticMethodID(env, bridgeClass, "copyText", "([B)V");
    if (method) {
        jsize length = (jsize)strlen(text);
        jbyteArray bytes = (*env)->NewByteArray(env, length);
        if (bytes) {
            (*env)->SetByteArrayRegion(env, bytes, 0, length, (const jbyte*)text);
            (*env)->CallStaticVoidMethod(env, bridgeClass, method, bytes);
            (*env)->DeleteLocalRef(env, bytes);
        }
    } else {
        omni_jni_clear_pending(env);
    }
    (*env)->DeleteLocalRef(env, bridgeClass);
}

// OmniEventBridge.<method>(byte[]): text handed to Java as UTF-8 bytes, for
// the same reason as copyText. openURL and share.
void omni_jni_send_text(JNIEnv *env, const char* method, const char* text) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    if (!bridgeClass) { omni_jni_clear_pending(env); return; }
    jmethodID m = (*env)->GetStaticMethodID(env, bridgeClass, method, "([B)V");
    if (m) {
        jsize length = (jsize)strlen(text);
        jbyteArray bytes = (*env)->NewByteArray(env, length);
        if (bytes) {
            (*env)->SetByteArrayRegion(env, bytes, 0, length, (const jbyte*)text);
            (*env)->CallStaticVoidMethod(env, bridgeClass, m, bytes);
            (*env)->DeleteLocalRef(env, bytes);
        }
    } else {
        omni_jni_clear_pending(env);
    }
    (*env)->DeleteLocalRef(env, bridgeClass);
}

// Clipboard.string: a malloc'd, NUL-terminated UTF-8 copy the caller frees, or NULL.
char* omni_jni_pasted_text(JNIEnv *env) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    if (!bridgeClass) { omni_jni_clear_pending(env); return NULL; }
    jmethodID method = (*env)->GetStaticMethodID(env, bridgeClass, "pastedText", "()[B");
    char* result = NULL;
    if (method) {
        jbyteArray bytes = (jbyteArray)(*env)->CallStaticObjectMethod(env, bridgeClass, method);
        if (bytes) {
            jsize length = (*env)->GetArrayLength(env, bytes);
            result = (char*)malloc((size_t)length + 1);
            if (result) {
                (*env)->GetByteArrayRegion(env, bytes, 0, length, (jbyte*)result);
                result[length] = 0;
            }
            (*env)->DeleteLocalRef(env, bytes);
        }
    } else {
        omni_jni_clear_pending(env);
    }
    (*env)->DeleteLocalRef(env, bridgeClass);
    return result;
}

// See OmniEventBridge.setAccessibility. label, value and hint may be NULL:
// left as an earlier modifier set them.
void omni_jni_set_accessibility(JNIEnv *env, jobject view, const char* label, const char* value,
                                const char* hint, int element, int traits) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    if (!bridgeClass) { omni_jni_clear_pending(env); return; }
    jmethodID method = (*env)->GetStaticMethodID(env, bridgeClass, "setAccessibility",
        "(Landroid/view/View;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;ZI)V");
    if (method) {
        jstring jLabel = label ? (*env)->NewStringUTF(env, label) : NULL;
        jstring jValue = value ? (*env)->NewStringUTF(env, value) : NULL;
        jstring jHint = hint ? (*env)->NewStringUTF(env, hint) : NULL;
        (*env)->CallStaticVoidMethod(env, bridgeClass, method, view, jLabel, jValue, jHint,
                                     element ? JNI_TRUE : JNI_FALSE, (jint)traits);
        if (jLabel) (*env)->DeleteLocalRef(env, jLabel);
        if (jValue) (*env)->DeleteLocalRef(env, jValue);
        if (jHint) (*env)->DeleteLocalRef(env, jHint);
    } else {
        omni_jni_clear_pending(env);
    }
    (*env)->DeleteLocalRef(env, bridgeClass);
}

// .accessibilityHidden: the view and everything in it, out of TalkBack's reach.
void omni_jni_set_accessibility_hidden(JNIEnv *env, jobject view, int hidden) {
    // View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS is 4, AUTO is 0.
    omni_jni_call_void_method_int(env, view, "setImportantForAccessibility", hidden ? 4 : 0);
}

void omni_jni_call_void_method_int(JNIEnv *env, jobject obj, const char* methodName, int arg) {
    jclass clazz = (*env)->GetObjectClass(env, obj);
    jmethodID method = omni_jni_lookup(env, clazz, methodName, "(I)V");
    if (method) {
        (*env)->CallVoidMethod(env, obj, method, arg);
    }
    (*env)->DeleteLocalRef(env, clazz);
}

void omni_jni_call_void_method_bool(JNIEnv *env, jobject obj, const char* methodName, int arg) {
    jclass clazz = (*env)->GetObjectClass(env, obj);
    // Java booleans are "Z", not "I".
    jmethodID method = omni_jni_lookup(env, clazz, methodName, "(Z)V");
    if (method) {
        (*env)->CallVoidMethod(env, obj, method, (jboolean)(arg ? JNI_TRUE : JNI_FALSE));
    }
    (*env)->DeleteLocalRef(env, clazz);
}

// Declare Swift generic receivers
extern void omni_swift_dispatch_int(void* ptr, int val);
extern void omni_swift_dispatch_float(void* ptr, float val);
extern void omni_swift_dispatch_float2(void* ptr, float x, float y);
extern void omni_swift_dispatch_void(void* ptr);
extern void omni_swift_dispatch_bool(void* ptr, int val);
extern void omni_swift_dispatch_string(void* ptr, const char* str);

JNIEXPORT void JNICALL Java_com_omni_OmniEventBridge_dispatchString(JNIEnv *env, jclass clazz, jlong ptr, jstring val) {
    const char *cStr = (*env)->GetStringUTFChars(env, val, NULL);
    omni_swift_dispatch_string((void*)ptr, cStr);
    (*env)->ReleaseStringUTFChars(env, val, cStr);
}

JNIEXPORT void JNICALL Java_com_omni_OmniEventBridge_dispatchBool(JNIEnv *env, jclass clazz, jlong ptr, jboolean val) {
    omni_swift_dispatch_bool((void*)ptr, (int)val);
}

JNIEXPORT void JNICALL Java_com_omni_OmniEventBridge_dispatchVoid(JNIEnv *env, jclass clazz, jlong ptr) {
    omni_swift_dispatch_void((void*)ptr);
}

JNIEXPORT void JNICALL Java_com_omni_OmniEventBridge_dispatchInt(JNIEnv *env, jclass clazz, jlong ptr, jint val) {
    omni_swift_dispatch_int((void*)ptr, (int)val);
}

JNIEXPORT void JNICALL Java_com_omni_OmniEventBridge_dispatchFloat(JNIEnv *env, jclass clazz, jlong ptr, jfloat val) {
    omni_swift_dispatch_float((void*)ptr, (float)val);
}

JNIEXPORT void JNICALL Java_com_omni_OmniEventBridge_dispatchFloat2(JNIEnv *env, jclass clazz, jlong ptr, jfloat val1, jfloat val2) {
    omni_swift_dispatch_float2((void*)ptr, (float)val1, (float)val2);
}

void omni_jni_attach_on_seek_bar_change(JNIEnv *env, jobject view, void* swift_ptr) {
    jclass clazz = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    jmethodID method = (*env)->GetStaticMethodID(env, clazz, "attachOnSeekBarChange", "(Landroid/widget/SeekBar;J)V");
    (*env)->CallStaticVoidMethod(env, clazz, method, view, (jlong)swift_ptr);
}

void omni_jni_attach_frame_gestures(JNIEnv *env, jobject view, void* tap_ptr, void* tap_loc_ptr, void* drag_ptr, void* drag_end_ptr, void* scroll_ptr) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");

    // Takes one View and five longs (pointers).
    jmethodID attachMethod = (*env)->GetStaticMethodID(env, bridgeClass, "attachFrameGestures", "(Landroid/view/View;JJJJJ)V");

    (*env)->CallStaticVoidMethod(env, bridgeClass, attachMethod, view, (jlong)tap_ptr, (jlong)tap_loc_ptr, (jlong)drag_ptr, (jlong)drag_end_ptr, (jlong)scroll_ptr);

    (*env)->DeleteLocalRef(env, bridgeClass);
}

void omni_jni_set_image(JNIEnv *env, jobject view, const char* name, int isSystem) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    jmethodID method = (*env)->GetStaticMethodID(env, bridgeClass, "setImage", "(Landroid/widget/ImageView;Ljava/lang/String;Z)V");

    jstring jName = (*env)->NewStringUTF(env, name);
    (*env)->CallStaticVoidMethod(env, bridgeClass, method, view, jName, (jboolean)isSystem);

    (*env)->DeleteLocalRef(env, jName);
    (*env)->DeleteLocalRef(env, bridgeClass);
}

// A shape's outline; see OmniEventBridge.setStroke.
void omni_jni_set_stroke(JNIEnv *env, jobject view, int kind, float radius, float width,
                         int inset, int a, int r, int g, int b) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    if (!bridgeClass) {
        omni_jni_clear_pending(env);
        return;
    }
    jmethodID method = (*env)->GetStaticMethodID(env, bridgeClass, "setStroke",
        "(Landroid/view/View;IFFZI)V");
    if (method) {
        int color = (a & 0xFF) << 24 | (r & 0xFF) << 16 | (g & 0xFF) << 8 | (b & 0xFF);
        (*env)->CallStaticVoidMethod(env, bridgeClass, method, view, kind, radius, width,
                                     (jboolean)inset, color);
    }
    omni_jni_clear_pending(env);
    (*env)->DeleteLocalRef(env, bridgeClass);
}

// .textContentType; see OmniEventBridge.setAutofillHint. "" clears it.
void omni_jni_set_autofill_hint(JNIEnv *env, jobject view, const char* hint) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    if (!bridgeClass) {
        omni_jni_clear_pending(env);
        return;
    }
    jmethodID method = (*env)->GetStaticMethodID(env, bridgeClass, "setAutofillHint",
        "(Landroid/view/View;Ljava/lang/String;)V");
    if (method) {
        jstring jHint = (*env)->NewStringUTF(env, hint);
        (*env)->CallStaticVoidMethod(env, bridgeClass, method, view, jHint);
        (*env)->DeleteLocalRef(env, jHint);
    }
    omni_jni_clear_pending(env);
    (*env)->DeleteLocalRef(env, bridgeClass);
}

// ARGB colours, evenly spaced; see OmniEventBridge.setLinearGradient.
void omni_jni_set_linear_gradient(JNIEnv *env, jobject view, const int32_t* colors, int count,
                                  float start_x, float start_y, float end_x, float end_y) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    if (!bridgeClass) {
        omni_jni_clear_pending(env);
        return;
    }
    jmethodID method = (*env)->GetStaticMethodID(env, bridgeClass, "setLinearGradient",
        "(Landroid/view/View;[IFFFF)V");
    if (method) {
        jintArray jColors = (*env)->NewIntArray(env, count);
        (*env)->SetIntArrayRegion(env, jColors, 0, count, (const jint*)colors);
        (*env)->CallStaticVoidMethod(env, bridgeClass, method, view, jColors,
                                     start_x, start_y, end_x, end_y);
        (*env)->DeleteLocalRef(env, jColors);
    }
    omni_jni_clear_pending(env);
    (*env)->DeleteLocalRef(env, bridgeClass);
}

// .foregroundColor for the drawn symbols in a subtree; see OmniEventBridge.tintSymbols.
void omni_jni_tint_symbols(JNIEnv *env, jobject view, int a, int r, int g, int b) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    if (!bridgeClass) {
        omni_jni_clear_pending(env);
        return;
    }
    jmethodID method = (*env)->GetStaticMethodID(env, bridgeClass, "tintSymbols", "(Landroid/view/View;I)V");
    if (method) {
        int color = (a & 0xFF) << 24 | (r & 0xFF) << 16 | (g & 0xFF) << 8 | (b & 0xFF);
        (*env)->CallStaticVoidMethod(env, bridgeClass, method, view, color);
    } else {
        omni_jni_clear_pending(env);
    }
    (*env)->DeleteLocalRef(env, bridgeClass);
}

void omni_jni_set_image_bytes(JNIEnv *env, jobject view, const uint8_t* data, int length) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    jmethodID method = (*env)->GetStaticMethodID(env, bridgeClass, "setImageBytes",
        "(Landroid/widget/ImageView;[B)V");
    if (method) {
        jbyteArray jData = (*env)->NewByteArray(env, length);
        (*env)->SetByteArrayRegion(env, jData, 0, length, (const jbyte*)data);
        (*env)->CallStaticVoidMethod(env, bridgeClass, method, view, jData);
        (*env)->DeleteLocalRef(env, jData);
    } else {
        omni_jni_clear_pending(env);
    }
    (*env)->DeleteLocalRef(env, bridgeClass);
}

static void omni_jni_resolve_axis(JNIEnv *env, jobject params, jfieldID field, int fills) {
    int current = (*env)->GetIntField(env, params, field);
    if (current != MATCH_PARENT && current != WRAP_CONTENT) return;
    (*env)->SetIntField(env, params, field, fills ? MATCH_PARENT : WRAP_CONTENT);
}

// Reads a view's LayoutParams and the width/height fields on them. Returns 0
// and leaves nothing pending if the view is detached or the fields are missing.
static int omni_jni_layout_fields(JNIEnv *env, jobject view, jobject *outParams,
                                  jclass *outClass, jfieldID *outWidth, jfieldID *outHeight,
                                  jmethodID *outSetter) {
    jclass viewClass = (*env)->GetObjectClass(env, view);
    jmethodID setter = omni_jni_lookup(env, viewClass, "setLayoutParams",
        "(Landroid/view/ViewGroup$LayoutParams;)V");
    jmethodID getter = omni_jni_lookup(env, viewClass, "getLayoutParams",
        "()Landroid/view/ViewGroup$LayoutParams;");
    (*env)->DeleteLocalRef(env, viewClass);
    if (!setter || !getter) return 0;

    jobject params = (*env)->CallObjectMethod(env, view, getter);
    if (!params) {
        omni_jni_clear_pending(env);
        return 0;
    }

    jclass paramsClass = (*env)->GetObjectClass(env, params);
    jfieldID width = (*env)->GetFieldID(env, paramsClass, "width", "I");
    jfieldID height = (*env)->GetFieldID(env, paramsClass, "height", "I");
    if (!width || !height) {
        omni_jni_clear_pending(env);
        (*env)->DeleteLocalRef(env, paramsClass);
        (*env)->DeleteLocalRef(env, params);
        return 0;
    }

    *outParams = params;
    *outClass = paramsClass;
    *outWidth = width;
    *outHeight = height;
    *outSetter = setter;
    return 1;
}

// How a wrapper; a padding, a background, a sheet host; sizes the one view
// inside it: to its content, unless the content asked for more.
void omni_jni_resolve_child_size(JNIEnv *env, jobject child, int fillsWidth, int fillsHeight) {
    jobject params; jclass paramsClass; jfieldID width, height; jmethodID setter;
    if (!omni_jni_layout_fields(env, child, &params, &paramsClass, &width, &height, &setter)) return;

    omni_jni_resolve_axis(env, params, width, fillsWidth);
    omni_jni_resolve_axis(env, params, height, fillsHeight);

    (*env)->CallVoidMethod(env, child, setter, params);
    (*env)->DeleteLocalRef(env, paramsClass);
    (*env)->DeleteLocalRef(env, params);
}

// 1 for a vertical LinearLayout, 0 for a horizontal one, -1 for anything else.
int omni_jni_linear_orientation(JNIEnv *env, jobject view) {
    jclass linear = (*env)->FindClass(env, "android/widget/LinearLayout");
    int orientation = -1;
    if (linear && (*env)->IsInstanceOf(env, view, linear)) {
        jmethodID getter = omni_jni_lookup(env, linear, "getOrientation", "()I");
        if (getter) orientation = (*env)->CallIntMethod(env, view, getter);
    }
    omni_jni_clear_pending(env);
    if (linear) (*env)->DeleteLocalRef(env, linear);
    return orientation;
}

void omni_jni_set_stack_child(JNIEnv *env, jobject child, int vertical,
                              int fillsCrossAxis, float weight) {
    jobject params; jclass paramsClass; jfieldID width, height; jmethodID setter;
    if (!omni_jni_layout_fields(env, child, &params, &paramsClass, &width, &height, &setter)) return;

    // The main axis is the stack's to distribute, through the weight; the cross
    // axis is the child's to claim.
    omni_jni_resolve_axis(env, params, vertical ? width : height, fillsCrossAxis);

    // weight exists only on LinearLayout.LayoutParams.
    jclass linearParams = (*env)->FindClass(env, "android/widget/LinearLayout$LayoutParams");
    if ((*env)->IsInstanceOf(env, params, linearParams)) {
        jfieldID weightField = (*env)->GetFieldID(env, paramsClass, "weight", "F");
        if (weightField) {
            (*env)->SetFloatField(env, params, weightField, weight);

            if (weight > 0) {
                (*env)->SetIntField(env, params, vertical ? height : width, 0);
            }
        } else {
            omni_jni_clear_pending(env);
        }
    }
    (*env)->DeleteLocalRef(env, linearParams);

    (*env)->CallVoidMethod(env, child, setter, params);
    (*env)->DeleteLocalRef(env, paramsClass);
    (*env)->DeleteLocalRef(env, params);
}

void omni_jni_size_to_content(JNIEnv *env, jobject child, int vertical) {
    jobject params; jclass paramsClass; jfieldID width, height; jmethodID setter;
    if (!omni_jni_layout_fields(env, child, &params, &paramsClass, &width, &height, &setter)) return;
    jfieldID along = vertical ? height : width;
    if ((*env)->GetIntField(env, params, along) == 0) {
        (*env)->SetIntField(env, params, along, WRAP_CONTENT);
        (*env)->CallVoidMethod(env, child, setter, params);
    }
    (*env)->DeleteLocalRef(env, paramsClass);
    (*env)->DeleteLocalRef(env, params);
}

void omni_jni_set_spacer_extent(JNIEnv *env, jobject view, int vertical) {
    jobject params; jclass paramsClass; jfieldID width, height; jmethodID setter;
    if (!omni_jni_layout_fields(env, view, &params, &paramsClass, &width, &height, &setter)) return;

    jfieldID along = vertical ? height : width;
    jfieldID across = vertical ? width : height;

    int current = (*env)->GetIntField(env, params, along);
    if (current == MATCH_PARENT || current == WRAP_CONTENT) {
        (*env)->SetIntField(env, params, along, 0);
    }
    (*env)->SetIntField(env, params, across, 0);

    (*env)->CallVoidMethod(env, view, setter, params);
    (*env)->DeleteLocalRef(env, paramsClass);
    (*env)->DeleteLocalRef(env, params);
}

// The window's content, edge to edge; see OmniEventBridge.installRoot.
void omni_jni_install_root(JNIEnv *env, jobject activity, jobject root) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    if (!bridgeClass) {
        omni_jni_clear_pending(env);
        return;
    }
    jmethodID method = (*env)->GetStaticMethodID(env, bridgeClass, "installRoot",
        "(Landroid/app/Activity;Landroid/view/View;)V");
    if (method) {
        (*env)->CallStaticVoidMethod(env, bridgeClass, method, activity, root);
    }
    omni_jni_clear_pending(env);
    (*env)->DeleteLocalRef(env, bridgeClass);
}

// Asks the Java side to log the laid-out tree. See OmniEventBridge.dumpTree.
void omni_jni_dump_view_tree(JNIEnv *env, jobject root) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    if (!bridgeClass) {
        omni_jni_clear_pending(env);
        return;
    }
    jmethodID method = (*env)->GetStaticMethodID(env, bridgeClass, "dumpTree", "(Landroid/view/View;)V");
    if (method) {
        (*env)->CallStaticVoidMethod(env, bridgeClass, method, root);
    } else {
        omni_jni_clear_pending(env);
    }
    (*env)->DeleteLocalRef(env, bridgeClass);
}

void omni_jni_set_linear_layout_spacing(JNIEnv *env, jobject view, int spacing) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    jmethodID method = (*env)->GetStaticMethodID(env, bridgeClass, "setLinearLayoutSpacing", "(Landroid/widget/LinearLayout;I)V");
    (*env)->CallStaticVoidMethod(env, bridgeClass, method, view, omni_jni_px(env, spacing));
    (*env)->DeleteLocalRef(env, bridgeClass);
}

void omni_jni_set_checked(JNIEnv *env, jobject view, int isChecked) {
    // Method: setChecked(boolean) -> "(Z)V"
    omni_jni_call(env, view, "setChecked", "(Z)V", (jboolean)isChecked);
}

void omni_jni_attach_on_checked(JNIEnv *env, jobject view, void* swift_ptr) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    jmethodID attachMethod = (*env)->GetStaticMethodID(env, bridgeClass, "attachOnChecked", "(Landroid/widget/CompoundButton;J)V");
    (*env)->CallStaticVoidMethod(env, bridgeClass, attachMethod, view, (jlong)swift_ptr);
    (*env)->DeleteLocalRef(env, bridgeClass);
}

// A field leaving the screen; see OmniEventBridge.detachTextField.
void omni_jni_detach_text_field(JNIEnv *env, jobject view) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    if (!bridgeClass) {
        omni_jni_clear_pending(env);
        return;
    }
    jmethodID method = (*env)->GetStaticMethodID(env, bridgeClass, "detachTextField", "(Landroid/widget/EditText;)V");
    if (method) (*env)->CallStaticVoidMethod(env, bridgeClass, method, view);
    omni_jni_clear_pending(env);
    (*env)->DeleteLocalRef(env, bridgeClass);
}

void omni_jni_attach_text_watcher(JNIEnv *env, jobject view, void* swift_ptr) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    jmethodID attachMethod = (*env)->GetStaticMethodID(env, bridgeClass, "attachTextWatcher", "(Landroid/widget/EditText;J)V");
    (*env)->CallStaticVoidMethod(env, bridgeClass, attachMethod, view, (jlong)swift_ptr);
    (*env)->DeleteLocalRef(env, bridgeClass);
}

// Retrieves the text from an EditText and returns a C string (caller must free())
char* omni_jni_get_text(JNIEnv *env, jobject view) {
    jclass clazz = (*env)->GetObjectClass(env, view);
    jmethodID method = (*env)->GetMethodID(env, clazz, "getText", "()Landroid/text/Editable;");
    jobject editable = (*env)->CallObjectMethod(env, view, method);

    jclass editableClass = (*env)->FindClass(env, "java/lang/CharSequence");
    jmethodID toStringMethod = (*env)->GetMethodID(env, editableClass, "toString", "()Ljava/lang/String;");
    jstring jstr = (jstring)(*env)->CallObjectMethod(env, editable, toStringMethod);

    const char *cStr = (*env)->GetStringUTFChars(env, jstr, NULL);
    char *result = strdup(cStr); // Copy it so we can safely release the JNI reference

    (*env)->ReleaseStringUTFChars(env, jstr, cStr);
    (*env)->DeleteLocalRef(env, jstr);
    (*env)->DeleteLocalRef(env, editable);
    (*env)->DeleteLocalRef(env, editableClass);
    (*env)->DeleteLocalRef(env, clazz);

    return result;
}

void omni_jni_set_multiline(JNIEnv *env, jobject view) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    jmethodID method = (*env)->GetStaticMethodID(env, bridgeClass, "setMultiline", "(Landroid/widget/EditText;)V");
    (*env)->CallStaticVoidMethod(env, bridgeClass, method, view);
    (*env)->DeleteLocalRef(env, bridgeClass);
}

void omni_jni_attach_swipe_gestures(JNIEnv *env, jobject view, void* left_ptr, void* right_ptr) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    jmethodID attachMethod = (*env)->GetStaticMethodID(env, bridgeClass, "attachSwipeGestures", "(Landroid/view/View;JJ)V");
    (*env)->CallStaticVoidMethod(env, bridgeClass, attachMethod, view, (jlong)left_ptr, (jlong)right_ptr);
    (*env)->DeleteLocalRef(env, bridgeClass);
}

void omni_jni_set_clip_radius(JNIEnv *env, jobject view, float radius, int isCircular) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    jmethodID method = (*env)->GetStaticMethodID(env, bridgeClass, "setClipRadius", "(Landroid/view/View;FZ)V");
    (*env)->CallStaticVoidMethod(env, bridgeClass, method, view,
                                 omni_jni_pxf(env, radius), (jboolean)isCircular);
    (*env)->DeleteLocalRef(env, bridgeClass);
}

void omni_jni_attach_on_scroll_change(JNIEnv *env, jobject view, void* swift_ptr) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    jmethodID attachMethod = (*env)->GetStaticMethodID(env, bridgeClass, "attachOnScrollChange", "(Landroid/view/View;J)V");
    (*env)->CallStaticVoidMethod(env, bridgeClass, attachMethod, view, (jlong)swift_ptr);
    (*env)->DeleteLocalRef(env, bridgeClass);
}

static jobject omni_jni_call_bridge_dialog(JNIEnv *env, const char* method, const char* sig,
                                          jobject arg0, jstring arg1, void* swift_ptr) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    jmethodID m = (*env)->GetStaticMethodID(env, bridgeClass, method, sig);

    jobject dialog;
    if (arg1) {
        dialog = (*env)->CallStaticObjectMethod(env, bridgeClass, m, arg0, arg1, (jlong)swift_ptr);
    } else {
        dialog = (*env)->CallStaticObjectMethod(env, bridgeClass, m, arg0, (jlong)swift_ptr);
    }
    (*env)->DeleteLocalRef(env, bridgeClass);

    if (!dialog) return NULL;

    // Held across calls by SheetState/AlertState, so it needs a global ref.
    jobject global = (*env)->NewGlobalRef(env, dialog);
    (*env)->DeleteLocalRef(env, dialog);
    return global;
}

jobject omni_jni_present_sheet(JNIEnv *env, jobject content, void* swift_ptr,
                               float fraction, float height_dp, float corner_radius_dp,
                               int shows_indicator, int is_dismissable, int surface_argb) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    jmethodID m = (*env)->GetStaticMethodID(env, bridgeClass, "presentSheet",
        "(Landroid/view/View;JFFFZZI)Landroid/app/Dialog;");
    jobject dialog = m ? (*env)->CallStaticObjectMethod(env, bridgeClass, m, content,
        (jlong)swift_ptr, (jfloat)fraction, (jfloat)height_dp, (jfloat)corner_radius_dp,
        (jboolean)shows_indicator, (jboolean)is_dismissable, (jint)surface_argb) : NULL;
    omni_jni_clear_pending(env);
    (*env)->DeleteLocalRef(env, bridgeClass);
    if (!dialog) return NULL;

    // Held across calls by SheetState, so it needs a global ref.
    jobject global = (*env)->NewGlobalRef(env, dialog);
    (*env)->DeleteLocalRef(env, dialog);
    return global;
}

// See OmniEventBridge.presentAlert. message may be NULL. swift_ptr is an
// EventHandlerInt for the chosen button's index.
jobject omni_jni_present_alert(JNIEnv *env, jobject anchor, const char* title, const char* message,
                               const char* titles, const char* roles, void* swift_ptr) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    if (!bridgeClass) { omni_jni_clear_pending(env); return NULL; }
    jmethodID m = (*env)->GetStaticMethodID(env, bridgeClass, "presentAlert",
        "(Landroid/view/View;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;J)Landroid/app/Dialog;");
    jobject dialog = NULL;
    if (m) {
        jstring jTitle = (*env)->NewStringUTF(env, title ? title : "");
        jstring jMessage = message ? (*env)->NewStringUTF(env, message) : NULL;
        jstring jTitles = (*env)->NewStringUTF(env, titles ? titles : "");
        jstring jRoles = (*env)->NewStringUTF(env, roles ? roles : "");
        dialog = (*env)->CallStaticObjectMethod(env, bridgeClass, m, anchor, jTitle, jMessage, jTitles, jRoles,
                                                (jlong)swift_ptr);
        (*env)->DeleteLocalRef(env, jTitle);
        if (jMessage) (*env)->DeleteLocalRef(env, jMessage);
        (*env)->DeleteLocalRef(env, jTitles);
        (*env)->DeleteLocalRef(env, jRoles);
    } else {
        omni_jni_clear_pending(env);
    }
    (*env)->DeleteLocalRef(env, bridgeClass);
    if (!dialog) return NULL;
    // Held across calls by AlertState, so it needs a global ref.
    jobject global = (*env)->NewGlobalRef(env, dialog);
    (*env)->DeleteLocalRef(env, dialog);
    return global;
}

void omni_jni_dismiss_dialog(JNIEnv *env, jobject dialog) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    jmethodID m = (*env)->GetStaticMethodID(env, bridgeClass, "dismissDialog", "(Landroid/app/Dialog;)V");
    (*env)->CallStaticVoidMethod(env, bridgeClass, m, dialog);
    (*env)->DeleteLocalRef(env, bridgeClass);
    (*env)->DeleteGlobalRef(env, dialog);
}

void omni_jni_attach_on_layout_change(JNIEnv *env, jobject view, void* swift_ptr) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    jmethodID attachMethod = (*env)->GetStaticMethodID(env, bridgeClass, "attachOnLayoutChange", "(Landroid/view/View;J)V");
    (*env)->CallStaticVoidMethod(env, bridgeClass, attachMethod, view, (jlong)swift_ptr);
    (*env)->DeleteLocalRef(env, bridgeClass);
}

void omni_jni_scroll_to(JNIEnv *env, jobject view, int x, int y) {
    jclass clazz = (*env)->GetObjectClass(env, view);
    jmethodID method = (*env)->GetMethodID(env, clazz, "scrollTo", "(II)V");
    x = omni_jni_px(env, x);
    y = omni_jni_px(env, y);

    // Android natively ignores this call if the x/y matches the current scroll position,
    // avoiding infinite scroll loops automatically.
    (*env)->CallVoidMethod(env, view, method, x, y);
    (*env)->DeleteLocalRef(env, clazz);
}

void omni_jni_set_scroll_behavior(JNIEnv *env, jobject view, int paging, int disabled, void* page_ptr) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    jmethodID method = (*env)->GetStaticMethodID(env, bridgeClass, "setScrollBehavior", "(Landroid/view/View;ZZJ)V");
    (*env)->CallStaticVoidMethod(env, bridgeClass, method, view, (jboolean)(paging != 0), (jboolean)(disabled != 0), (jlong)page_ptr);
    (*env)->DeleteLocalRef(env, bridgeClass);
}

void omni_jni_attach_scroll_sizes(JNIEnv *env, jobject view, void* size_ptr, void* content_ptr) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    jmethodID method = (*env)->GetStaticMethodID(env, bridgeClass, "attachScrollSizes", "(Landroid/view/View;JJ)V");
    (*env)->CallStaticVoidMethod(env, bridgeClass, method, view, (jlong)size_ptr, (jlong)content_ptr);
    (*env)->DeleteLocalRef(env, bridgeClass);
}

/// PageScrubber: `method` is scrubPages (F), releaseScrub (F) or goToPage (I).
static void omni_jni_call_paging(JNIEnv *env, jobject view, const char *method, const char *sig, ...) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    if (!bridgeClass) return;
    jmethodID m = (*env)->GetStaticMethodID(env, bridgeClass, method, sig);
    if (m) {
        va_list args;
        va_start(args, sig);
        (*env)->CallStaticVoidMethodV(env, bridgeClass, m, args);
        va_end(args);
    }
    omni_jni_clear_pending(env);
    (*env)->DeleteLocalRef(env, bridgeClass);
}

void omni_jni_scrub_pages(JNIEnv *env, jobject view, float pages) {
    omni_jni_call_paging(env, view, "scrubPages", "(Landroid/view/View;F)V", view, pages);
}

void omni_jni_release_scrub(JNIEnv *env, jobject view, float velocity) {
    omni_jni_call_paging(env, view, "releaseScrub", "(Landroid/view/View;F)V", view, velocity);
}

void omni_jni_go_to_page(JNIEnv *env, jobject view, int page) {
    omni_jni_call_paging(env, view, "goToPage", "(Landroid/view/View;I)V", view, (jint)page);
}

void omni_jni_show_page(JNIEnv *env, jobject view, int page) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    jmethodID method = (*env)->GetStaticMethodID(env, bridgeClass, "showPage", "(Landroid/view/View;I)V");
    (*env)->CallStaticVoidMethod(env, bridgeClass, method, view, (jint)page);
    (*env)->DeleteLocalRef(env, bridgeClass);
}

void omni_jni_set_spinner_options(JNIEnv *env, jobject view, const char* options_joined) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    jmethodID method = (*env)->GetStaticMethodID(env, bridgeClass, "setSpinnerOptions", "(Landroid/widget/Spinner;Ljava/lang/String;)V");

    jstring jStr = (*env)->NewStringUTF(env, options_joined);
    (*env)->CallStaticVoidMethod(env, bridgeClass, method, view, jStr);

    (*env)->DeleteLocalRef(env, jStr);
    (*env)->DeleteLocalRef(env, bridgeClass);
}

void omni_jni_attach_on_item_selected(JNIEnv *env, jobject view, void* swift_ptr) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    jmethodID attachMethod = (*env)->GetStaticMethodID(env, bridgeClass, "attachOnItemSelected", "(Landroid/widget/AdapterView;J)V");
    (*env)->CallStaticVoidMethod(env, bridgeClass, attachMethod, view, (jlong)swift_ptr);
    (*env)->DeleteLocalRef(env, bridgeClass);
}

void omni_jni_canvas_reset(JNIEnv *env, jobject view) {
    omni_jni_call(env, view, "resetCommands", "()V");
}

void omni_jni_canvas_begin_path(JNIEnv *env, jobject view) {
    omni_jni_call(env, view, "beginPath", "()V");
}

void omni_jni_canvas_move_to(JNIEnv *env, jobject view, float x, float y) {
    omni_jni_call(env, view, "moveTo", "(FF)V", omni_jni_pxf(env, x), omni_jni_pxf(env, y));
}

void omni_jni_canvas_line_to(JNIEnv *env, jobject view, float x, float y) {
    omni_jni_call(env, view, "lineTo", "(FF)V", omni_jni_pxf(env, x), omni_jni_pxf(env, y));
}

void omni_jni_canvas_cubic_to(JNIEnv *env, jobject view, float c1x, float c1y, float c2x, float c2y, float x, float y) {
    omni_jni_call(env, view, "cubicTo", "(FFFFFF)V",
                  omni_jni_pxf(env, c1x), omni_jni_pxf(env, c1y),
                  omni_jni_pxf(env, c2x), omni_jni_pxf(env, c2y),
                  omni_jni_pxf(env, x), omni_jni_pxf(env, y));
}

void omni_jni_canvas_set_stroke_color(JNIEnv *env, jobject view, int a, int r, int g, int b) {
    omni_jni_call(env, view, "setStrokeColor", "(IIII)V", a, r, g, b);
}

void omni_jni_canvas_set_fill_color(JNIEnv *env, jobject view, int a, int r, int g, int b) {
    omni_jni_call(env, view, "setFillColor", "(IIII)V", a, r, g, b);
}

void omni_jni_canvas_set_stroke_width(JNIEnv *env, jobject view, float width) {
    omni_jni_call(env, view, "setStrokeWidth", "(F)V", omni_jni_pxf(env, width));
}

void omni_jni_canvas_stroke(JNIEnv *env, jobject view) {
    omni_jni_call(env, view, "addStrokeCommand", "()V");
}

void omni_jni_canvas_fill(JNIEnv *env, jobject view) {
    omni_jni_call(env, view, "addFillCommand", "()V");
}

void omni_jni_canvas_invalidate(JNIEnv *env, jobject view) {
    omni_jni_call(env, view, "postInvalidate", "()V");
}

// --- Camera ---

int omni_jni_check_self_permission(JNIEnv *env, jobject activity, const char* permission) {
    jclass clazz = (*env)->GetObjectClass(env, activity);
    // checkSelfPermission is declared on Context, not Activity, but JNI's
    // method lookup walks the class hierarchy the same way Java's does.
    jmethodID method = omni_jni_lookup(env, clazz, "checkSelfPermission", "(Ljava/lang/String;)I");
    int result = -1; // PackageManager.PERMISSION_DENIED, if the lookup itself fails
    if (method) {
        jstring jPermission = (*env)->NewStringUTF(env, permission);
        result = (int)(*env)->CallIntMethod(env, activity, method, jPermission);
        (*env)->DeleteLocalRef(env, jPermission);
    }
    (*env)->DeleteLocalRef(env, clazz);
    return result;
}

void omni_jni_request_permission(JNIEnv *env, jobject activity, const char* permission, int requestCode, void* swift_ptr) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    jmethodID method = (*env)->GetStaticMethodID(env, bridgeClass, "requestPermission",
        "(Landroid/app/Activity;Ljava/lang/String;IJ)V");
    if (method) {
        jstring jPermission = (*env)->NewStringUTF(env, permission);
        (*env)->CallStaticVoidMethod(env, bridgeClass, method, activity, jPermission,
                                     (jint)requestCode, (jlong)(intptr_t)swift_ptr);
        (*env)->DeleteLocalRef(env, jPermission);
    } else {
        omni_jni_clear_pending(env);
    }
    (*env)->DeleteLocalRef(env, bridgeClass);
}

int omni_jni_launch_camera_capture(JNIEnv *env, jobject activity, const char* outputPath, int requestCode, int frontFacing, void* swift_ptr) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    jmethodID method = (*env)->GetStaticMethodID(env, bridgeClass, "launchCameraCapture",
        "(Landroid/app/Activity;Ljava/lang/String;IZJ)Z");
    jboolean started = JNI_FALSE;
    if (method) {
        jstring jPath = (*env)->NewStringUTF(env, outputPath);
        started = (*env)->CallStaticBooleanMethod(env, bridgeClass, method, activity, jPath,
            (jint)requestCode, (jboolean)(frontFacing ? JNI_TRUE : JNI_FALSE), (jlong)(intptr_t)swift_ptr);
        (*env)->DeleteLocalRef(env, jPath);
    } else {
        omni_jni_clear_pending(env);
    }
    (*env)->DeleteLocalRef(env, bridgeClass);
    return started == JNI_TRUE ? 1 : 0;
}

void omni_jni_launch_image_pick(JNIEnv *env, jobject activity, int requestCode, void* swift_ptr) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    jmethodID method = (*env)->GetStaticMethodID(env, bridgeClass, "launchImagePick",
        "(Landroid/app/Activity;IJ)V");
    if (method) {
        (*env)->CallStaticVoidMethod(env, bridgeClass, method, activity,
                                     (jint)requestCode, (jlong)(intptr_t)swift_ptr);
    } else {
        omni_jni_clear_pending(env);
    }
    (*env)->DeleteLocalRef(env, bridgeClass);
}


// MARK: - Keystore (OmniKeychain)

static jclass omni_keystore_class(JNIEnv *env) {
    jclass clazz = omni_jni_app_class(env, "com/omni/OmniKeystore");
    if (!clazz) omni_jni_clear_pending(env);
    return clazz;
}

int omni_jni_keystore_set(JNIEnv *env, jobject context, const char *key,
                          const uint8_t *value, int length, int level) {
    jclass clazz = omni_keystore_class(env);
    if (!clazz) return 0;
    jmethodID method = (*env)->GetStaticMethodID(env, clazz, "set",
        "(Landroid/content/Context;Ljava/lang/String;[BI)Z");
    if (!method) { omni_jni_clear_pending(env); (*env)->DeleteLocalRef(env, clazz); return 0; }

    jstring jKey = (*env)->NewStringUTF(env, key);
    jbyteArray jValue = (*env)->NewByteArray(env, length);
    (*env)->SetByteArrayRegion(env, jValue, 0, length, (const jbyte *)value);

    jboolean ok = (*env)->CallStaticBooleanMethod(env, clazz, method, context, jKey, jValue, level);

    (*env)->DeleteLocalRef(env, jValue);
    (*env)->DeleteLocalRef(env, jKey);
    (*env)->DeleteLocalRef(env, clazz);
    return ok ? 1 : 0;
}

uint8_t* omni_jni_keystore_get(JNIEnv *env, jobject context, const char *key, int *outLength) {
    *outLength = 0;
    jclass clazz = omni_keystore_class(env);
    if (!clazz) return NULL;
    jmethodID method = (*env)->GetStaticMethodID(env, clazz, "get",
        "(Landroid/content/Context;Ljava/lang/String;)[B");
    if (!method) { omni_jni_clear_pending(env); (*env)->DeleteLocalRef(env, clazz); return NULL; }

    jstring jKey = (*env)->NewStringUTF(env, key);
    jbyteArray jBytes = (jbyteArray)(*env)->CallStaticObjectMethod(env, clazz, method, context, jKey);
    (*env)->DeleteLocalRef(env, jKey);
    (*env)->DeleteLocalRef(env, clazz);
    if (!jBytes) return NULL;

    jsize length = (*env)->GetArrayLength(env, jBytes);
    uint8_t *buffer = (uint8_t *)malloc((size_t)length > 0 ? (size_t)length : 1);
    if (buffer) {
        (*env)->GetByteArrayRegion(env, jBytes, 0, length, (jbyte *)buffer);
        *outLength = (int)length;
    }
    (*env)->DeleteLocalRef(env, jBytes);
    return buffer;
}

int omni_jni_keystore_has(JNIEnv *env, jobject context, const char *key) {
    jclass clazz = omni_keystore_class(env);
    if (!clazz) return 0;
    jmethodID method = (*env)->GetStaticMethodID(env, clazz, "has",
        "(Landroid/content/Context;Ljava/lang/String;)Z");
    if (!method) { omni_jni_clear_pending(env); (*env)->DeleteLocalRef(env, clazz); return 0; }
    jstring jKey = (*env)->NewStringUTF(env, key);
    jboolean present = (*env)->CallStaticBooleanMethod(env, clazz, method, context, jKey);
    (*env)->DeleteLocalRef(env, jKey);
    (*env)->DeleteLocalRef(env, clazz);
    return present ? 1 : 0;
}

int omni_jni_keystore_delete(JNIEnv *env, jobject context, const char *key) {
    jclass clazz = omni_keystore_class(env);
    if (!clazz) return 0;
    jmethodID method = (*env)->GetStaticMethodID(env, clazz, "delete",
        "(Landroid/content/Context;Ljava/lang/String;)Z");
    if (!method) { omni_jni_clear_pending(env); (*env)->DeleteLocalRef(env, clazz); return 0; }
    jstring jKey = (*env)->NewStringUTF(env, key);
    jboolean removed = (*env)->CallStaticBooleanMethod(env, clazz, method, context, jKey);
    (*env)->DeleteLocalRef(env, jKey);
    (*env)->DeleteLocalRef(env, clazz);
    return removed ? 1 : 0;
}

// MARK: - Device keys (OmniKeychain)

static jclass omni_device_key_class(JNIEnv *env) {
    jclass clazz = omni_jni_app_class(env, "com/omni/OmniDeviceKey");
    if (!clazz) omni_jni_clear_pending(env);
    return clazz;
}

/// A Java byte[] copied out to malloc'd memory, the local ref released.
static uint8_t* omni_jni_copy_bytes(JNIEnv *env, jbyteArray jBytes, int *outLength) {
    *outLength = 0;
    if (!jBytes) return NULL;
    jsize length = (*env)->GetArrayLength(env, jBytes);
    uint8_t *buffer = (uint8_t *)malloc((size_t)length > 0 ? (size_t)length : 1);
    if (buffer) {
        (*env)->GetByteArrayRegion(env, jBytes, 0, length, (jbyte *)buffer);
        *outLength = (int)length;
    }
    (*env)->DeleteLocalRef(env, jBytes);
    return buffer;
}

uint8_t* omni_jni_device_key_public(JNIEnv *env, jobject context, const char *tag, int *outLength) {
    *outLength = 0;
    jclass clazz = omni_device_key_class(env);
    if (!clazz) return NULL;
    jmethodID method = (*env)->GetStaticMethodID(env, clazz, "publicKey",
        "(Landroid/content/Context;Ljava/lang/String;)[B");
    if (!method) { omni_jni_clear_pending(env); (*env)->DeleteLocalRef(env, clazz); return NULL; }

    jstring jTag = (*env)->NewStringUTF(env, tag);
    jbyteArray jBytes = (jbyteArray)(*env)->CallStaticObjectMethod(env, clazz, method, context, jTag);
    omni_jni_clear_pending(env);
    (*env)->DeleteLocalRef(env, jTag);
    (*env)->DeleteLocalRef(env, clazz);
    return omni_jni_copy_bytes(env, jBytes, outLength);
}

uint8_t* omni_jni_device_key_sign(JNIEnv *env, jobject context, const char *tag,
                                  const uint8_t *message, int length, int *outLength) {
    *outLength = 0;
    jclass clazz = omni_device_key_class(env);
    if (!clazz) return NULL;
    jmethodID method = (*env)->GetStaticMethodID(env, clazz, "sign",
        "(Landroid/content/Context;Ljava/lang/String;[B)[B");
    if (!method) { omni_jni_clear_pending(env); (*env)->DeleteLocalRef(env, clazz); return NULL; }

    jstring jTag = (*env)->NewStringUTF(env, tag);
    jbyteArray jMessage = (*env)->NewByteArray(env, length);
    (*env)->SetByteArrayRegion(env, jMessage, 0, length, (const jbyte *)message);

    jbyteArray jBytes = (jbyteArray)(*env)->CallStaticObjectMethod(env, clazz, method, context, jTag, jMessage);
    omni_jni_clear_pending(env);
    (*env)->DeleteLocalRef(env, jMessage);
    (*env)->DeleteLocalRef(env, jTag);
    (*env)->DeleteLocalRef(env, clazz);
    return omni_jni_copy_bytes(env, jBytes, outLength);
}

int omni_jni_device_key_delete(JNIEnv *env, jobject context, const char *tag) {
    jclass clazz = omni_device_key_class(env);
    if (!clazz) return 0;
    jmethodID method = (*env)->GetStaticMethodID(env, clazz, "delete",
        "(Landroid/content/Context;Ljava/lang/String;)Z");
    if (!method) { omni_jni_clear_pending(env); (*env)->DeleteLocalRef(env, clazz); return 0; }
    jstring jTag = (*env)->NewStringUTF(env, tag);
    jboolean removed = (*env)->CallStaticBooleanMethod(env, clazz, method, context, jTag);
    omni_jni_clear_pending(env);
    (*env)->DeleteLocalRef(env, jTag);
    (*env)->DeleteLocalRef(env, clazz);
    return removed ? 1 : 0;
}

// MARK: - Approval keys (OmniKeychain)

static jclass omni_approval_key_class(JNIEnv *env) {
    jclass clazz = omni_jni_app_class(env, "com/omni/OmniApprovalKey");
    if (!clazz) omni_jni_clear_pending(env);
    return clazz;
}

int omni_jni_approval_biometry(JNIEnv *env, jobject context) {
    jclass clazz = omni_approval_key_class(env);
    if (!clazz) return 0;
    jmethodID method = (*env)->GetStaticMethodID(env, clazz, "biometry", "(Landroid/content/Context;)I");
    if (!method) { omni_jni_clear_pending(env); (*env)->DeleteLocalRef(env, clazz); return 0; }
    jint value = (*env)->CallStaticIntMethod(env, clazz, method, context);
    omni_jni_clear_pending(env);
    (*env)->DeleteLocalRef(env, clazz);
    return (int)value;
}

int omni_jni_approval_key_has(JNIEnv *env, jobject context, const char *tag) {
    jclass clazz = omni_approval_key_class(env);
    if (!clazz) return 0;
    jmethodID method = (*env)->GetStaticMethodID(env, clazz, "has", "(Landroid/content/Context;Ljava/lang/String;)Z");
    if (!method) { omni_jni_clear_pending(env); (*env)->DeleteLocalRef(env, clazz); return 0; }
    jstring jTag = (*env)->NewStringUTF(env, tag);
    jboolean found = (*env)->CallStaticBooleanMethod(env, clazz, method, context, jTag);
    omni_jni_clear_pending(env);
    (*env)->DeleteLocalRef(env, jTag);
    (*env)->DeleteLocalRef(env, clazz);
    return found ? 1 : 0;
}

uint8_t* omni_jni_approval_key_create(JNIEnv *env, jobject context, const char *tag, int *outLength) {
    *outLength = 0;
    jclass clazz = omni_approval_key_class(env);
    if (!clazz) return NULL;
    jmethodID method = (*env)->GetStaticMethodID(env, clazz, "create",
        "(Landroid/content/Context;Ljava/lang/String;)[B");
    if (!method) { omni_jni_clear_pending(env); (*env)->DeleteLocalRef(env, clazz); return NULL; }
    jstring jTag = (*env)->NewStringUTF(env, tag);
    jbyteArray jBytes = (jbyteArray)(*env)->CallStaticObjectMethod(env, clazz, method, context, jTag);
    omni_jni_clear_pending(env);
    (*env)->DeleteLocalRef(env, jTag);
    (*env)->DeleteLocalRef(env, clazz);
    return omni_jni_copy_bytes(env, jBytes, outLength);
}

int omni_jni_approval_key_delete(JNIEnv *env, jobject context, const char *tag) {
    jclass clazz = omni_approval_key_class(env);
    if (!clazz) return 0;
    jmethodID method = (*env)->GetStaticMethodID(env, clazz, "delete", "(Landroid/content/Context;Ljava/lang/String;)Z");
    if (!method) { omni_jni_clear_pending(env); (*env)->DeleteLocalRef(env, clazz); return 0; }
    jstring jTag = (*env)->NewStringUTF(env, tag);
    jboolean removed = (*env)->CallStaticBooleanMethod(env, clazz, method, context, jTag);
    omni_jni_clear_pending(env);
    (*env)->DeleteLocalRef(env, jTag);
    (*env)->DeleteLocalRef(env, clazz);
    return removed ? 1 : 0;
}

uint8_t* omni_jni_approval_key_sign(const char *tag, const uint8_t *message, int length,
                                    const char *title, const char *reason, const char *cancel,
                                    int *outLength, int *outStatus) {
    *outLength = 0;
    *outStatus = 4;
    if (!global_jvm || !global_activity) return NULL;
    JNIEnv *env = NULL;
    int attached = 0;
    if ((*global_jvm)->GetEnv(global_jvm, (void **)&env, JNI_VERSION_1_6) == JNI_EDETACHED) {
        if ((*global_jvm)->AttachCurrentThread(global_jvm, &env, NULL) != JNI_OK) return NULL;
        attached = 1;
    }
    uint8_t *result = NULL;

    // An attached thread needs the app's class loader.
    jclass activityClass = (*env)->GetObjectClass(env, global_activity);
    jmethodID getLoader = (*env)->GetMethodID(env, activityClass, "getClassLoader", "()Ljava/lang/ClassLoader;");
    jobject loader = getLoader ? (*env)->CallObjectMethod(env, global_activity, getLoader) : NULL;
    omni_jni_clear_pending(env);
    jclass loaderClass = loader ? (*env)->GetObjectClass(env, loader) : NULL;
    jmethodID loadClass = loaderClass
        ? (*env)->GetMethodID(env, loaderClass, "loadClass", "(Ljava/lang/String;)Ljava/lang/Class;") : NULL;
    jstring name = (*env)->NewStringUTF(env, "com.omni.OmniApprovalKey");
    jclass clazz = loadClass ? (jclass)(*env)->CallObjectMethod(env, loader, loadClass, name) : NULL;
    omni_jni_clear_pending(env);

    jmethodID sign = clazz ? (*env)->GetStaticMethodID(env, clazz, "sign",
        "(Landroid/app/Activity;Ljava/lang/String;[BLjava/lang/String;Ljava/lang/String;Ljava/lang/String;)[B") : NULL;
    jfieldID status = clazz ? (*env)->GetStaticFieldID(env, clazz, "lastStatus", "I") : NULL;
    omni_jni_clear_pending(env);
    if (sign && status) {
        jstring jTag = (*env)->NewStringUTF(env, tag);
        jstring jTitle = (*env)->NewStringUTF(env, title);
        jstring jReason = (*env)->NewStringUTF(env, reason);
        jstring jCancel = (*env)->NewStringUTF(env, cancel);
        jbyteArray jMessage = (*env)->NewByteArray(env, length);
        (*env)->SetByteArrayRegion(env, jMessage, 0, length, (const jbyte *)message);
        jbyteArray jBytes = (jbyteArray)(*env)->CallStaticObjectMethod(env, clazz, sign, global_activity, jTag,
                                                                     jMessage, jTitle, jReason, jCancel);
        omni_jni_clear_pending(env);
        *outStatus = (int)(*env)->GetStaticIntField(env, clazz, status);
        result = omni_jni_copy_bytes(env, jBytes, outLength);
        if (result) *outStatus = 0;
        (*env)->DeleteLocalRef(env, jMessage);
        (*env)->DeleteLocalRef(env, jCancel);
        (*env)->DeleteLocalRef(env, jReason);
        (*env)->DeleteLocalRef(env, jTitle);
        (*env)->DeleteLocalRef(env, jTag);
    }

    (*env)->DeleteLocalRef(env, name);
    if (clazz) (*env)->DeleteLocalRef(env, clazz);
    if (loaderClass) (*env)->DeleteLocalRef(env, loaderClass);
    if (loader) (*env)->DeleteLocalRef(env, loader);
    (*env)->DeleteLocalRef(env, activityClass);
    if (attached) (*global_jvm)->DetachCurrentThread(global_jvm);
    return result;
}

// MARK: - Play Integrity (OmniKeychain)

char* omni_jni_attest_token(const char *requestHash) {
    if (!global_jvm || !global_activity) return NULL;
    JNIEnv *env = NULL;
    int attached = 0;
    if ((*global_jvm)->GetEnv(global_jvm, (void **)&env, JNI_VERSION_1_6) == JNI_EDETACHED) {
        if ((*global_jvm)->AttachCurrentThread(global_jvm, &env, NULL) != JNI_OK) return NULL;
        attached = 1;
    }
    char *result = NULL;

    // The app's class loader: FindClass on an attached thread sees only the system's.
    jclass activityClass = (*env)->GetObjectClass(env, global_activity);
    jmethodID getLoader = (*env)->GetMethodID(env, activityClass, "getClassLoader", "()Ljava/lang/ClassLoader;");
    jobject loader = getLoader ? (*env)->CallObjectMethod(env, global_activity, getLoader) : NULL;
    omni_jni_clear_pending(env);
    jclass loaderClass = loader ? (*env)->GetObjectClass(env, loader) : NULL;
    jmethodID loadClass = loaderClass
        ? (*env)->GetMethodID(env, loaderClass, "loadClass", "(Ljava/lang/String;)Ljava/lang/Class;") : NULL;
    jstring name = (*env)->NewStringUTF(env, "com.omni.OmniAttest");
    // Not built in: ClassNotFoundException, cleared.
    jclass clazz = loadClass ? (jclass)(*env)->CallObjectMethod(env, loader, loadClass, name) : NULL;
    omni_jni_clear_pending(env);

    jmethodID token = clazz ? (*env)->GetStaticMethodID(env, clazz, "token",
        "(Landroid/content/Context;Ljava/lang/String;)Ljava/lang/String;") : NULL;
    omni_jni_clear_pending(env);
    if (token) {
        jstring hash = (*env)->NewStringUTF(env, requestHash);
        jstring value = (jstring)(*env)->CallStaticObjectMethod(env, clazz, token, global_activity, hash);
        omni_jni_clear_pending(env);
        if (value) {
            const char *chars = (*env)->GetStringUTFChars(env, value, NULL);
            if (chars) {
                result = strdup(chars);
                (*env)->ReleaseStringUTFChars(env, value, chars);
            }
            (*env)->DeleteLocalRef(env, value);
        }
        (*env)->DeleteLocalRef(env, hash);
    }

    (*env)->DeleteLocalRef(env, name);
    if (clazz) (*env)->DeleteLocalRef(env, clazz);
    if (loaderClass) (*env)->DeleteLocalRef(env, loaderClass);
    if (loader) (*env)->DeleteLocalRef(env, loader);
    (*env)->DeleteLocalRef(env, activityClass);
    if (attached) (*global_jvm)->DetachCurrentThread(global_jvm);
    return result;
}

uint8_t* omni_jni_read_uri(JNIEnv *env, jobject activity, const char* uri, int* outLength) {
    *outLength = 0;
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    jmethodID method = (*env)->GetStaticMethodID(env, bridgeClass, "readUri",
        "(Landroid/content/Context;Ljava/lang/String;)[B");
    if (!method) {
        omni_jni_clear_pending(env);
        (*env)->DeleteLocalRef(env, bridgeClass);
        return NULL;
    }

    jstring jUri = (*env)->NewStringUTF(env, uri);
    jbyteArray jBytes = (jbyteArray)(*env)->CallStaticObjectMethod(env, bridgeClass, method, activity, jUri);
    (*env)->DeleteLocalRef(env, jUri);
    (*env)->DeleteLocalRef(env, bridgeClass);
    if (!jBytes) return NULL;

    jsize length = (*env)->GetArrayLength(env, jBytes);
    uint8_t* buffer = (uint8_t*)malloc((size_t)length > 0 ? (size_t)length : 1);
    if (buffer) {
        (*env)->GetByteArrayRegion(env, jBytes, 0, length, (jbyte*)buffer);
        *outLength = (int)length;
    }
    (*env)->DeleteLocalRef(env, jBytes);
    return buffer;
}

static char* omni_jni_context_dir(JNIEnv *env, jobject activity, const char* getter);

char* omni_jni_cache_dir(JNIEnv *env, jobject activity) {
    return omni_jni_context_dir(env, activity, "getCacheDir");
}

// The app's private files directory: AppDirectories.support.
char* omni_jni_files_dir(JNIEnv *env, jobject activity) {
    return omni_jni_context_dir(env, activity, "getFilesDir");
}

// A Context getter returning a File, as a malloc'd absolute path, or NULL.
static char* omni_jni_context_dir(JNIEnv *env, jobject activity, const char* getter) {
    jclass clazz = (*env)->GetObjectClass(env, activity);
    jmethodID method = omni_jni_lookup(env, clazz, getter, "()Ljava/io/File;");
    char *result = NULL;
    if (method) {
        jobject fileObj = (*env)->CallObjectMethod(env, activity, method);
        if (fileObj) {
            jclass fileClass = (*env)->GetObjectClass(env, fileObj);
            jmethodID pathMethod = (*env)->GetMethodID(env, fileClass, "getAbsolutePath", "()Ljava/lang/String;");
            if (pathMethod) {
                jstring jPath = (jstring)(*env)->CallObjectMethod(env, fileObj, pathMethod);
                const char *cStr = (*env)->GetStringUTFChars(env, jPath, NULL);
                result = strdup(cStr);
                (*env)->ReleaseStringUTFChars(env, jPath, cStr);
                (*env)->DeleteLocalRef(env, jPath);
            }
            (*env)->DeleteLocalRef(env, fileClass);
            (*env)->DeleteLocalRef(env, fileObj);
        }
    }
    (*env)->DeleteLocalRef(env, clazz);
    return result;
}

uint8_t* omni_jni_encode_image(JNIEnv *env, const uint8_t* input, int inputLength,
                               int maxDimension, const char* format, double quality, int* outLength) {
    *outLength = 0;
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    jmethodID method = (*env)->GetStaticMethodID(env, bridgeClass, "encodeImage", "([BILjava/lang/String;D)[B");
    if (!method) {
        omni_jni_clear_pending(env);
        (*env)->DeleteLocalRef(env, bridgeClass);
        return NULL;
    }

    jbyteArray jInput = (*env)->NewByteArray(env, inputLength);
    (*env)->SetByteArrayRegion(env, jInput, 0, inputLength, (const jbyte*)input);
    jstring jFormat = (*env)->NewStringUTF(env, format);

    jbyteArray jOut = (jbyteArray)(*env)->CallStaticObjectMethod(env, bridgeClass, method,
        jInput, (jint)maxDimension, jFormat, (jdouble)quality);

    (*env)->DeleteLocalRef(env, jInput);
    (*env)->DeleteLocalRef(env, jFormat);
    (*env)->DeleteLocalRef(env, bridgeClass);
    if (!jOut) return NULL;

    jsize length = (*env)->GetArrayLength(env, jOut);
    uint8_t* buffer = (uint8_t*)malloc((size_t)length > 0 ? (size_t)length : 1);
    if (buffer) {
        (*env)->GetByteArrayRegion(env, jOut, 0, length, (jbyte*)buffer);
        *outLength = (int)length;
    }
    (*env)->DeleteLocalRef(env, jOut);
    return buffer;
}

void omni_jni_image_dimensions(JNIEnv *env, const uint8_t* data, int length, int* outWidth, int* outHeight) {
    *outWidth = 0;
    *outHeight = 0;
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    jmethodID method = (*env)->GetStaticMethodID(env, bridgeClass, "imageDimensions", "([B)[I");
    if (!method) {
        omni_jni_clear_pending(env);
        (*env)->DeleteLocalRef(env, bridgeClass);
        return;
    }

    jbyteArray jData = (*env)->NewByteArray(env, length);
    (*env)->SetByteArrayRegion(env, jData, 0, length, (const jbyte*)data);

    jintArray jDims = (jintArray)(*env)->CallStaticObjectMethod(env, bridgeClass, method, jData);
    (*env)->DeleteLocalRef(env, jData);
    (*env)->DeleteLocalRef(env, bridgeClass);
    if (!jDims) return;

    jint dims[2] = {0, 0};
    (*env)->GetIntArrayRegion(env, jDims, 0, 2, dims);
    (*env)->DeleteLocalRef(env, jDims);
    *outWidth = (int)dims[0];
    *outHeight = (int)dims[1];
}

extern void omni_swift_lifecycle(int foreground);
extern void omni_swift_user_activity(void);

JNIEXPORT void JNICALL Java_com_omni_OmniEventBridge_dispatchLifecycle(JNIEnv *env, jclass clazz, jboolean foreground) {
    omni_swift_lifecycle(foreground ? 1 : 0);
}

JNIEXPORT void JNICALL Java_com_omni_OmniEventBridge_dispatchActivity(JNIEnv *env, jclass clazz) {
    omni_swift_user_activity();
}

extern void omni_swift_safe_area(float top, float bottom);

JNIEXPORT void JNICALL Java_com_omni_OmniEventBridge_dispatchSafeArea(JNIEnv *env, jclass clazz, jfloat top, jfloat bottom) {
    omni_swift_safe_area(top, bottom);
}

// Keyboard.dismiss; see OmniEventBridge.dismissKeyboard.
void omni_jni_dismiss_keyboard(JNIEnv *env) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    if (!bridgeClass) { omni_jni_clear_pending(env); return; }
    jmethodID method = (*env)->GetStaticMethodID(env, bridgeClass, "dismissKeyboard", "()V");
    if (method) {
        (*env)->CallStaticVoidMethod(env, bridgeClass, method);
    } else {
        omni_jni_clear_pending(env);
    }
    (*env)->DeleteLocalRef(env, bridgeClass);
}

// Keyboard.coversContent; see OmniEventBridge.setKeyboardCovers.
void omni_jni_set_keyboard_covers(JNIEnv *env, int covers) {
    jclass bridgeClass = omni_jni_app_class(env, "com/omni/OmniEventBridge");
    if (!bridgeClass) { omni_jni_clear_pending(env); return; }
    jmethodID method = (*env)->GetStaticMethodID(env, bridgeClass, "setKeyboardCovers", "(Z)V");
    if (method) {
        (*env)->CallStaticVoidMethod(env, bridgeClass, method, covers ? JNI_TRUE : JNI_FALSE);
    } else {
        omni_jni_clear_pending(env);
    }
    (*env)->DeleteLocalRef(env, bridgeClass);
}

extern void omni_swift_deep_link(const char* url);

JNIEXPORT void JNICALL Java_com_omni_OmniEventBridge_dispatchDeepLink(JNIEnv *env, jclass clazz, jstring url) {
    if (!url) return;
    const char *cStr = (*env)->GetStringUTFChars(env, url, NULL);
    omni_swift_deep_link(cStr);
    (*env)->ReleaseStringUTFChars(env, url, cStr);
}

// Weak: they live in OmniCamera, which an app may not link. Without it these
// are NULL, and no camera request can be pending to call back.
extern void omni_camera_dispatch_permission_result(void* ptr, int granted) __attribute__((weak));
extern void omni_camera_dispatch_activity_result(void* ptr, int ok, const char* uri) __attribute__((weak));

JNIEXPORT void JNICALL Java_com_omni_OmniEventBridge_dispatchCameraPermissionResult(JNIEnv *env, jclass clazz, jlong ptr, jboolean granted) {
    if (!omni_camera_dispatch_permission_result) return;
    omni_camera_dispatch_permission_result((void*)(intptr_t)ptr, (int)granted);
}

JNIEXPORT void JNICALL Java_com_omni_OmniEventBridge_dispatchCameraActivityResult(JNIEnv *env, jclass clazz, jlong ptr, jboolean ok, jstring uri) {
    if (!omni_camera_dispatch_activity_result) return;
    if (uri) {
        const char *cStr = (*env)->GetStringUTFChars(env, uri, NULL);
        omni_camera_dispatch_activity_result((void*)(intptr_t)ptr, (int)ok, cStr);
        (*env)->ReleaseStringUTFChars(env, uri, cStr);
    } else {
        omni_camera_dispatch_activity_result((void*)(intptr_t)ptr, (int)ok, NULL);
    }
}

// MARK: - WebView (OmniWebView.java)

void omni_jni_call_void_method(JNIEnv *env, jobject obj, const char* methodName) {
    jclass clazz = (*env)->GetObjectClass(env, obj);
    jmethodID method = omni_jni_lookup(env, clazz, methodName, "()V");
    if (method) {
        (*env)->CallVoidMethod(env, obj, method);
    } else {
        omni_jni_clear_pending(env);
    }
    (*env)->DeleteLocalRef(env, clazz);
}

void omni_jni_web_attach(JNIEnv *env, jobject view, void* swift_ptr) {
    jclass clazz = (*env)->GetObjectClass(env, view);
    jmethodID method = omni_jni_lookup(env, clazz, "setSwiftHandle", "(J)V");
    if (method) {
        (*env)->CallVoidMethod(env, view, method, (jlong)(intptr_t)swift_ptr);
    } else {
        omni_jni_clear_pending(env);
    }
    (*env)->DeleteLocalRef(env, clazz);
}

void omni_jni_web_load_html(JNIEnv *env, jobject view, const char* html, const char* baseURL) {
    jclass clazz = (*env)->GetObjectClass(env, view);
    jmethodID method = omni_jni_lookup(env, clazz, "loadHTML",
                                       "(Ljava/lang/String;Ljava/lang/String;)V");
    if (method) {
        jstring jHtml = (*env)->NewStringUTF(env, html ? html : "");
        jstring jBase = baseURL ? (*env)->NewStringUTF(env, baseURL) : NULL;
        (*env)->CallVoidMethod(env, view, method, jHtml, jBase);
        (*env)->DeleteLocalRef(env, jHtml);
        if (jBase) (*env)->DeleteLocalRef(env, jBase);
    } else {
        omni_jni_clear_pending(env);
    }
    (*env)->DeleteLocalRef(env, clazz);
}

extern int  omni_swift_web_policy(void* ptr, const char* url);
extern void omni_swift_web_event(void* ptr, int kind, const char* value);
extern void omni_swift_web_state(void* ptr, int progress, int can_go_back, int can_go_forward);

JNIEXPORT jboolean JNICALL Java_com_omni_OmniWebView_dispatchWebPolicy(JNIEnv *env, jclass clazz, jlong ptr, jstring url) {
    if (!url) return JNI_FALSE;
    const char *cStr = (*env)->GetStringUTFChars(env, url, NULL);
    int cancel = omni_swift_web_policy((void*)(intptr_t)ptr, cStr);
    (*env)->ReleaseStringUTFChars(env, url, cStr);
    return cancel ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT void JNICALL Java_com_omni_OmniWebView_dispatchWebEvent(JNIEnv *env, jclass clazz, jlong ptr, jint kind, jstring value) {
    if (value) {
        const char *cStr = (*env)->GetStringUTFChars(env, value, NULL);
        omni_swift_web_event((void*)(intptr_t)ptr, (int)kind, cStr);
        (*env)->ReleaseStringUTFChars(env, value, cStr);
    } else {
        omni_swift_web_event((void*)(intptr_t)ptr, (int)kind, NULL);
    }
}

JNIEXPORT void JNICALL Java_com_omni_OmniWebView_dispatchWebState(JNIEnv *env, jclass clazz, jlong ptr, jint progress, jboolean canGoBack, jboolean canGoForward) {
    omni_swift_web_state((void*)(intptr_t)ptr, (int)progress, (int)canGoBack, (int)canGoForward);
}

#endif // __ANDROID__
