#pragma once

#include <jni.h>
#include <stdbool.h>

typedef JNIEnv *SwiftUIJNIEnvironment;

typedef struct SwiftUIAndroidBridge SwiftUIAndroidBridge;

SwiftUIAndroidBridge *swiftui_android_bridge_create(JNIEnv *env, jobject host);
void swiftui_android_bridge_destroy(JNIEnv *env, SwiftUIAndroidBridge *bridge);
void swiftui_android_bridge_schedule_render(SwiftUIAndroidBridge *bridge);
void swiftui_android_bridge_open_url(SwiftUIAndroidBridge *bridge, const char *url);

static inline jstring swiftui_android_string(JNIEnv *env, const jchar *text, jsize length) {
  return (*env)->NewString(env, text, length);
}

static inline jmethodID swiftui_android_text_measurer(JNIEnv *env, jobject host) {
  jclass type = (*env)->GetObjectClass(env, host);
  jmethodID method = (*env)->GetMethodID(env, type, "measureText", "(Ljava/lang/String;DLjava/lang/String;I)J");
  (*env)->DeleteLocalRef(env, type);
  return method;
}

static inline jlong swiftui_android_measure_text(
    JNIEnv *env, jobject host, jmethodID method, jstring text, jdouble size,
    jstring family, jint weight) {
  jlong measured = (*env)->CallLongMethod(env, host, method, text, size, family, weight);
  (*env)->DeleteLocalRef(env, text);
  (*env)->DeleteLocalRef(env, family);
  return measured;
}

static inline const char *swiftui_android_get_utf8(JNIEnv *env, jstring str) {
  if (!str) return NULL;
  return (*env)->GetStringUTFChars(env, str, NULL);
}

static inline void swiftui_android_release_utf8(JNIEnv *env, jstring str, const char *chars) {
  if (str && chars) {
    (*env)->ReleaseStringUTFChars(env, str, chars);
  }
}
