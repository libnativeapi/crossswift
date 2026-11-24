#ifndef CROSSSWIFT_CQUICKJS_H
#define CROSSSWIFT_CQUICKJS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct JSRuntime *QJSRuntimeRef;
typedef struct JSContext *QJSContextRef;
typedef struct QJSValueBox *QJSValueRef;

/// Callback invoked when JavaScript calls a bridged host closure.
/// `this_val` and every element of `argv` are borrowed for the duration of the call;
/// duplicate them with `qjs_value_dup` if they need to outlive the callback.
/// Return an owned `QJSValueRef` (transferred to the engine), or `NULL` for `undefined`
/// (or to propagate a pending exception thrown via `qjs_throw` / `qjs_throw_error`).
typedef QJSValueRef (*QJSClosureCallback)(
    QJSContextRef ctx,
    QJSValueRef this_val,
    int32_t argc,
    const QJSValueRef *argv,
    void *userdata);

typedef void (*QJSClosureFinalizer)(void *userdata);

typedef struct QJSPropertyKeys {
    char **keys;
    uint32_t count;
} QJSPropertyKeys;

// MARK: - Runtime & Context

QJSRuntimeRef qjs_runtime_new(void);
void qjs_runtime_free(QJSRuntimeRef rt);
void qjs_runtime_update_stack_top(QJSRuntimeRef rt);
void qjs_runtime_set_max_stack_size(QJSRuntimeRef rt, size_t stack_size);
void qjs_runtime_run_gc(QJSRuntimeRef rt);

QJSContextRef qjs_context_new(QJSRuntimeRef rt);
void qjs_context_free(QJSContextRef ctx);
QJSRuntimeRef qjs_context_get_runtime(QJSContextRef ctx);
QJSValueRef qjs_get_global_object(QJSContextRef ctx);

// MARK: - Value Lifecycle & Constructors

QJSValueRef qjs_value_dup(QJSContextRef ctx, QJSValueRef val);
void qjs_value_free(QJSContextRef ctx, QJSValueRef val);
void qjs_value_free_rt(QJSRuntimeRef rt, QJSValueRef val);

QJSValueRef qjs_new_undefined(void);
QJSValueRef qjs_new_null(void);
QJSValueRef qjs_new_bool(QJSContextRef ctx, bool value);
QJSValueRef qjs_new_int32(QJSContextRef ctx, int32_t value);
QJSValueRef qjs_new_float64(QJSContextRef ctx, double value);
QJSValueRef qjs_new_string(QJSContextRef ctx, const char *utf8, size_t byte_len);
QJSValueRef qjs_new_object(QJSContextRef ctx);
QJSValueRef qjs_new_array(QJSContextRef ctx);
QJSValueRef qjs_new_date(QJSContextRef ctx, double epoch_ms);
QJSValueRef qjs_new_closure(
    QJSContextRef ctx,
    const char *name,
    int32_t length,
    QJSClosureCallback callback,
    QJSClosureFinalizer finalizer,
    void *userdata);

// MARK: - Type Checks & Comparisons

bool qjs_is_undefined(QJSValueRef val);
bool qjs_is_null(QJSValueRef val);
bool qjs_is_bool(QJSValueRef val);
bool qjs_is_number(QJSValueRef val);
bool qjs_is_string(QJSValueRef val);
bool qjs_is_symbol(QJSValueRef val);
bool qjs_is_object(QJSValueRef val);
bool qjs_is_array(QJSValueRef val);
bool qjs_is_date(QJSValueRef val);
bool qjs_is_function(QJSContextRef ctx, QJSValueRef val);
bool qjs_is_exception(QJSValueRef val);
bool qjs_is_error(QJSValueRef val);

bool qjs_is_strict_equal(QJSContextRef ctx, QJSValueRef a, QJSValueRef b);
bool qjs_is_equal(QJSContextRef ctx, QJSValueRef a, QJSValueRef b);
bool qjs_is_instance_of(QJSContextRef ctx, QJSValueRef val, QJSValueRef constructor_obj);

// MARK: - Conversions (JS -> C)

bool qjs_to_bool(QJSContextRef ctx, QJSValueRef val);
int32_t qjs_to_int32(QJSContextRef ctx, QJSValueRef val);
double qjs_to_float64(QJSContextRef ctx, QJSValueRef val);
const char *qjs_to_cstring_len(QJSContextRef ctx, QJSValueRef val, size_t *out_len);
void qjs_free_cstring(QJSContextRef ctx, const char *str);

// MARK: - Property & Array Access

QJSValueRef qjs_get_property_str(QJSContextRef ctx, QJSValueRef obj, const char *prop);
int32_t qjs_set_property_str(QJSContextRef ctx, QJSValueRef obj, const char *prop, QJSValueRef val);
QJSValueRef qjs_get_property_uint32(QJSContextRef ctx, QJSValueRef obj, uint32_t idx);
int32_t qjs_set_property_uint32(QJSContextRef ctx, QJSValueRef obj, uint32_t idx, QJSValueRef val);
bool qjs_has_property_str(QJSContextRef ctx, QJSValueRef obj, const char *prop);
bool qjs_delete_property_str(QJSContextRef ctx, QJSValueRef obj, const char *prop);
int64_t qjs_get_length(QJSContextRef ctx, QJSValueRef obj);

bool qjs_get_own_property_names(QJSContextRef ctx, QJSValueRef obj, QJSPropertyKeys *out_keys);
void qjs_free_property_names(QJSPropertyKeys *keys);

// MARK: - Evaluation, Calls, Exceptions & Jobs

QJSValueRef qjs_eval(QJSContextRef ctx, const char *source, size_t source_len, const char *filename);
QJSValueRef qjs_call(
    QJSContextRef ctx,
    QJSValueRef func,
    QJSValueRef this_val,
    int32_t argc,
    const QJSValueRef *argv);
QJSValueRef qjs_invoke(
    QJSContextRef ctx,
    QJSValueRef this_val,
    const char *method,
    int32_t argc,
    const QJSValueRef *argv);
QJSValueRef qjs_call_constructor(
    QJSContextRef ctx,
    QJSValueRef func,
    int32_t argc,
    const QJSValueRef *argv);

bool qjs_has_exception(QJSContextRef ctx);
QJSValueRef qjs_get_exception(QJSContextRef ctx);
QJSValueRef qjs_throw(QJSContextRef ctx, QJSValueRef val);
QJSValueRef qjs_throw_error(QJSContextRef ctx, const char *message);

bool qjs_is_job_pending(QJSRuntimeRef rt);
int32_t qjs_execute_pending_job(QJSRuntimeRef rt, QJSContextRef *out_ctx);

#ifdef __cplusplus
}
#endif

#endif /* CROSSSWIFT_CQUICKJS_H */
