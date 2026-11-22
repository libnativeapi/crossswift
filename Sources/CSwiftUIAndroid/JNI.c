#include "CSwiftUIAndroid.h"

#include <pthread.h>
#include <stdlib.h>

struct SwiftUIAndroidBridge {
  pthread_mutex_t lock;
  JavaVM *vm;
  jobject hostGlobalRef;
  jmethodID scheduleAsyncRenderMethod;
  jmethodID openURLMethod;
  bool alive;
};

SwiftUIAndroidBridge *swiftui_android_bridge_create(JNIEnv *env, jobject host) {
  if (!env || !host) return NULL;
  JavaVM *vm = NULL;
  if ((*env)->GetJavaVM(env, &vm) != JNI_OK || !vm) return NULL;

  jobject globalHost = (*env)->NewGlobalRef(env, host);
  if (!globalHost) return NULL;

  jclass hostClass = (*env)->GetObjectClass(env, host);
  jmethodID scheduleMethod = NULL;
  jmethodID openURLMethod = NULL;
  if (hostClass) {
    scheduleMethod = (*env)->GetMethodID(env, hostClass, "scheduleAsyncRender", "()V");
    if ((*env)->ExceptionCheck(env)) {
      (*env)->ExceptionClear(env);
      scheduleMethod = NULL;
    }
    openURLMethod = (*env)->GetMethodID(env, hostClass, "openURL", "(Ljava/lang/String;)V");
    if ((*env)->ExceptionCheck(env)) {
      (*env)->ExceptionClear(env);
      openURLMethod = NULL;
    }
    (*env)->DeleteLocalRef(env, hostClass);
  }

  SwiftUIAndroidBridge *bridge = (SwiftUIAndroidBridge *)calloc(1, sizeof(SwiftUIAndroidBridge));
  if (!bridge) {
    (*env)->DeleteGlobalRef(env, globalHost);
    return NULL;
  }
  pthread_mutex_init(&bridge->lock, NULL);
  bridge->vm = vm;
  bridge->hostGlobalRef = globalHost;
  bridge->scheduleAsyncRenderMethod = scheduleMethod;
  bridge->openURLMethod = openURLMethod;
  bridge->alive = true;
  return bridge;
}

void swiftui_android_bridge_destroy(JNIEnv *env, SwiftUIAndroidBridge *bridge) {
  if (!bridge) return;
  pthread_mutex_lock(&bridge->lock);
  bridge->alive = false;
  jobject ref = bridge->hostGlobalRef;
  bridge->hostGlobalRef = NULL;
  bridge->scheduleAsyncRenderMethod = NULL;
  bridge->openURLMethod = NULL;
  pthread_mutex_unlock(&bridge->lock);

  if (env && ref) {
    (*env)->DeleteGlobalRef(env, ref);
  }
  pthread_mutex_destroy(&bridge->lock);
  free(bridge);
}

static bool attach_env(JavaVM *vm, JNIEnv **outEnv, bool *outDidAttach) {
  *outEnv = NULL;
  *outDidAttach = false;
  if (!vm) return false;
  jint status = (*vm)->GetEnv(vm, (void **)outEnv, JNI_VERSION_1_6);
  if (status == JNI_OK && *outEnv) return true;
  if (status == JNI_EDETACHED) {
    if ((*vm)->AttachCurrentThread(vm, outEnv, NULL) == JNI_OK && *outEnv) {
      *outDidAttach = true;
      return true;
    }
  }
  return false;
}

void swiftui_android_bridge_schedule_render(SwiftUIAndroidBridge *bridge) {
  if (!bridge) return;
  pthread_mutex_lock(&bridge->lock);
  if (!bridge->alive || !bridge->vm || !bridge->hostGlobalRef || !bridge->scheduleAsyncRenderMethod) {
    pthread_mutex_unlock(&bridge->lock);
    return;
  }
  JavaVM *vm = bridge->vm;
  jobject host = bridge->hostGlobalRef;
  jmethodID method = bridge->scheduleAsyncRenderMethod;

  JNIEnv *env = NULL;
  bool didAttach = false;
  if (attach_env(vm, &env, &didAttach)) {
    (*env)->CallVoidMethod(env, host, method);
    if ((*env)->ExceptionCheck(env)) {
      (*env)->ExceptionClear(env);
    }
    if (didAttach) {
      (*vm)->DetachCurrentThread(vm);
    }
  }
  pthread_mutex_unlock(&bridge->lock);
}

void swiftui_android_bridge_open_url(SwiftUIAndroidBridge *bridge, const char *url) {
  if (!bridge || !url) return;
  pthread_mutex_lock(&bridge->lock);
  if (!bridge->alive || !bridge->vm || !bridge->hostGlobalRef || !bridge->openURLMethod) {
    pthread_mutex_unlock(&bridge->lock);
    return;
  }
  JavaVM *vm = bridge->vm;
  jobject host = bridge->hostGlobalRef;
  jmethodID method = bridge->openURLMethod;

  JNIEnv *env = NULL;
  bool didAttach = false;
  if (attach_env(vm, &env, &didAttach)) {
    jstring jUrl = (*env)->NewStringUTF(env, url);
    if (jUrl) {
      (*env)->CallVoidMethod(env, host, method, jUrl);
      (*env)->DeleteLocalRef(env, jUrl);
      if ((*env)->ExceptionCheck(env)) {
        (*env)->ExceptionClear(env);
      }
    }
    if (didAttach) {
      (*vm)->DetachCurrentThread(vm);
    }
  }
  pthread_mutex_unlock(&bridge->lock);
}
