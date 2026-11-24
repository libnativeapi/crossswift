#include "include/CQuickJS.h"
#include "quickjs.h"

#include <stdlib.h>
#include <string.h>

struct QJSValueBox {
    JSValue val;
};

static QJSValueRef qjs_box_take(JSValue v) {
    struct QJSValueBox *box = (struct QJSValueBox *)malloc(sizeof(struct QJSValueBox));
    if (!box) {
        return NULL;
    }
    box->val = v;
    return box;
}

// MARK: - Runtime & Context

QJSRuntimeRef qjs_runtime_new(void) {
    JSRuntime *rt = JS_NewRuntime();
    if (!rt) {
        return NULL;
    }
    JS_SetCanBlock(rt, true);
    // Use 512 KiB JS stack limit by default so infinite JS recursion throws
    // RangeError cleanly even on 1 MiB Windows thread-pool worker stacks.
    JS_SetMaxStackSize(rt, 512 * 1024);
    return rt;
}

void qjs_runtime_free(QJSRuntimeRef rt) {
    if (rt) {
        JS_FreeRuntime(rt);
    }
}

void qjs_runtime_update_stack_top(QJSRuntimeRef rt) {
    if (rt) {
        JS_UpdateStackTop(rt);
    }
}

void qjs_runtime_set_max_stack_size(QJSRuntimeRef rt, size_t stack_size) {
    if (rt) {
        JS_SetMaxStackSize(rt, stack_size);
    }
}

void qjs_runtime_run_gc(QJSRuntimeRef rt) {
    if (rt) {
        JS_RunGC(rt);
    }
}

QJSContextRef qjs_context_new(QJSRuntimeRef rt) {
    if (!rt) {
        return NULL;
    }
    return JS_NewContext(rt);
}

void qjs_context_free(QJSContextRef ctx) {
    if (ctx) {
        JS_FreeContext(ctx);
    }
}

QJSRuntimeRef qjs_context_get_runtime(QJSContextRef ctx) {
    if (!ctx) {
        return NULL;
    }
    return JS_GetRuntime(ctx);
}

QJSValueRef qjs_get_global_object(QJSContextRef ctx) {
    if (!ctx) {
        return NULL;
    }
    return qjs_box_take(JS_GetGlobalObject(ctx));
}

// MARK: - Value Lifecycle & Constructors

QJSValueRef qjs_value_dup(QJSContextRef ctx, QJSValueRef val) {
    if (!ctx || !val) {
        return qjs_box_take(JS_UNDEFINED);
    }
    return qjs_box_take(JS_DupValue(ctx, val->val));
}

void qjs_value_free(QJSContextRef ctx, QJSValueRef val) {
    if (!val) {
        return;
    }
    if (ctx) {
        JS_FreeValue(ctx, val->val);
    }
    free(val);
}

void qjs_value_free_rt(QJSRuntimeRef rt, QJSValueRef val) {
    if (!val) {
        return;
    }
    if (rt) {
        JS_FreeValueRT(rt, val->val);
    }
    free(val);
}

QJSValueRef qjs_new_undefined(void) {
    return qjs_box_take(JS_UNDEFINED);
}

QJSValueRef qjs_new_null(void) {
    return qjs_box_take(JS_NULL);
}

QJSValueRef qjs_new_bool(QJSContextRef ctx, bool value) {
    return qjs_box_take(JS_NewBool(ctx, value));
}

QJSValueRef qjs_new_int32(QJSContextRef ctx, int32_t value) {
    return qjs_box_take(JS_NewInt32(ctx, value));
}

QJSValueRef qjs_new_float64(QJSContextRef ctx, double value) {
    return qjs_box_take(JS_NewFloat64(ctx, value));
}

QJSValueRef qjs_new_string(QJSContextRef ctx, const char *utf8, size_t byte_len) {
    if (!ctx) {
        return NULL;
    }
    if (!utf8) {
        return qjs_box_take(JS_NewStringLen(ctx, "", 0));
    }
    return qjs_box_take(JS_NewStringLen(ctx, utf8, byte_len));
}

QJSValueRef qjs_new_object(QJSContextRef ctx) {
    if (!ctx) {
        return NULL;
    }
    return qjs_box_take(JS_NewObject(ctx));
}

QJSValueRef qjs_new_array(QJSContextRef ctx) {
    if (!ctx) {
        return NULL;
    }
    return qjs_box_take(JS_NewArray(ctx));
}

QJSValueRef qjs_new_date(QJSContextRef ctx, double epoch_ms) {
    if (!ctx) {
        return NULL;
    }
    return qjs_box_take(JS_NewDate(ctx, epoch_ms));
}

typedef struct QJSClosureTrampoline {
    QJSClosureCallback callback;
    QJSClosureFinalizer finalizer;
    void *userdata;
} QJSClosureTrampoline;

static JSValue qjs_closure_invoke(
    JSContext *ctx,
    JSValueConst this_val,
    int argc,
    JSValueConst *argv,
    int magic,
    void *opaque)
{
    (void)magic;
    QJSClosureTrampoline *trampoline = (QJSClosureTrampoline *)opaque;
    if (!trampoline || !trampoline->callback) {
        return JS_UNDEFINED;
    }

    struct QJSValueBox this_box;
    this_box.val = this_val;

    struct QJSValueBox stack_boxes[16];
    QJSValueRef stack_ptrs[16];
    struct QJSValueBox *arg_boxes = stack_boxes;
    QJSValueRef *arg_ptrs = stack_ptrs;

    if (argc > 16) {
        arg_boxes = (struct QJSValueBox *)malloc((size_t)argc * sizeof(struct QJSValueBox));
        arg_ptrs = (QJSValueRef *)malloc((size_t)argc * sizeof(QJSValueRef));
        if (!arg_boxes || !arg_ptrs) {
            free(arg_boxes);
            free(arg_ptrs);
            return JS_ThrowOutOfMemory(ctx);
        }
    }

    for (int i = 0; i < argc; i++) {
        arg_boxes[i].val = argv[i];
        arg_ptrs[i] = &arg_boxes[i];
    }

    QJSValueRef result = trampoline->callback(
        ctx,
        &this_box,
        (int32_t)argc,
        argc > 0 ? arg_ptrs : NULL,
        trampoline->userdata);

    if (argc > 16) {
        free(arg_boxes);
        free(arg_ptrs);
    }

    if (result) {
        JSValue ret = result->val;
        free(result);
        return ret;
    }

    if (JS_HasException(ctx)) {
        return JS_EXCEPTION;
    }
    return JS_UNDEFINED;
}

static void qjs_closure_finalize(void *opaque) {
    QJSClosureTrampoline *trampoline = (QJSClosureTrampoline *)opaque;
    if (!trampoline) {
        return;
    }
    if (trampoline->finalizer) {
        trampoline->finalizer(trampoline->userdata);
    }
    free(trampoline);
}

QJSValueRef qjs_new_closure(
    QJSContextRef ctx,
    const char *name,
    int32_t length,
    QJSClosureCallback callback,
    QJSClosureFinalizer finalizer,
    void *userdata)
{
    if (!ctx || !callback) {
        if (finalizer) {
            finalizer(userdata);
        }
        return NULL;
    }

    QJSClosureTrampoline *trampoline =
        (QJSClosureTrampoline *)malloc(sizeof(QJSClosureTrampoline));
    if (!trampoline) {
        if (finalizer) {
            finalizer(userdata);
        }
        return NULL;
    }
    trampoline->callback = callback;
    trampoline->finalizer = finalizer;
    trampoline->userdata = userdata;

    JSValue fn = JS_NewCClosure(
        ctx,
        qjs_closure_invoke,
        name ? name : "",
        qjs_closure_finalize,
        length,
        0,
        trampoline);
    return qjs_box_take(fn);
}

// MARK: - Type Checks & Comparisons

bool qjs_is_undefined(QJSValueRef val) {
    return !val || JS_IsUndefined(val->val);
}

bool qjs_is_null(QJSValueRef val) {
    return val && JS_IsNull(val->val);
}

bool qjs_is_bool(QJSValueRef val) {
    return val && JS_IsBool(val->val);
}

bool qjs_is_number(QJSValueRef val) {
    return val && JS_IsNumber(val->val);
}

bool qjs_is_string(QJSValueRef val) {
    return val && JS_IsString(val->val);
}

bool qjs_is_symbol(QJSValueRef val) {
    return val && JS_IsSymbol(val->val);
}

bool qjs_is_object(QJSValueRef val) {
    return val && JS_IsObject(val->val);
}

bool qjs_is_array(QJSValueRef val) {
    return val && JS_IsArray(val->val);
}

bool qjs_is_date(QJSValueRef val) {
    return val && JS_IsDate(val->val);
}

bool qjs_is_function(QJSContextRef ctx, QJSValueRef val) {
    return ctx && val && JS_IsFunction(ctx, val->val);
}

bool qjs_is_exception(QJSValueRef val) {
    return val && JS_IsException(val->val);
}

bool qjs_is_error(QJSValueRef val) {
    return val && JS_IsError(val->val);
}

bool qjs_is_strict_equal(QJSContextRef ctx, QJSValueRef a, QJSValueRef b) {
    if (!ctx || !a || !b) {
        return false;
    }
    return JS_IsStrictEqual(ctx, a->val, b->val);
}

bool qjs_is_equal(QJSContextRef ctx, QJSValueRef a, QJSValueRef b) {
    if (!ctx || !a || !b) {
        return false;
    }
    int r = JS_IsEqual(ctx, a->val, b->val);
    if (r < 0) {
        JSValue exc = JS_GetException(ctx);
        JS_FreeValue(ctx, exc);
        return false;
    }
    return r != 0;
}

bool qjs_is_instance_of(QJSContextRef ctx, QJSValueRef val, QJSValueRef constructor_obj) {
    if (!ctx || !val || !constructor_obj) {
        return false;
    }
    int r = JS_IsInstanceOf(ctx, val->val, constructor_obj->val);
    if (r < 0) {
        JSValue exc = JS_GetException(ctx);
        JS_FreeValue(ctx, exc);
        return false;
    }
    return r != 0;
}

// MARK: - Conversions (JS -> C)

bool qjs_to_bool(QJSContextRef ctx, QJSValueRef val) {
    if (!ctx || !val) {
        return false;
    }
    int r = JS_ToBool(ctx, val->val);
    if (r < 0) {
        JSValue exc = JS_GetException(ctx);
        JS_FreeValue(ctx, exc);
        return false;
    }
    return r != 0;
}

int32_t qjs_to_int32(QJSContextRef ctx, QJSValueRef val) {
    if (!ctx || !val) {
        return 0;
    }
    int32_t out = 0;
    if (JS_ToInt32(ctx, &out, val->val) < 0) {
        JSValue exc = JS_GetException(ctx);
        JS_FreeValue(ctx, exc);
        return 0;
    }
    return out;
}

double qjs_to_float64(QJSContextRef ctx, QJSValueRef val) {
    if (!ctx || !val) {
        return 0.0;
    }
    double out = 0.0;
    if (JS_ToFloat64(ctx, &out, val->val) < 0) {
        JSValue exc = JS_GetException(ctx);
        JS_FreeValue(ctx, exc);
        return 0.0;
    }
    return out;
}

const char *qjs_to_cstring_len(QJSContextRef ctx, QJSValueRef val, size_t *out_len) {
    if (!ctx || !val) {
        if (out_len) {
            *out_len = 0;
        }
        return NULL;
    }
    const char *str = JS_ToCStringLen(ctx, out_len, val->val);
    if (!str && JS_HasException(ctx)) {
        JSValue exc = JS_GetException(ctx);
        JS_FreeValue(ctx, exc);
    }
    return str;
}

void qjs_free_cstring(QJSContextRef ctx, const char *str) {
    if (ctx && str) {
        JS_FreeCString(ctx, str);
    }
}

// MARK: - Property & Array Access

QJSValueRef qjs_get_property_str(QJSContextRef ctx, QJSValueRef obj, const char *prop) {
    if (!ctx || !obj || !prop) {
        return qjs_box_take(JS_UNDEFINED);
    }
    return qjs_box_take(JS_GetPropertyStr(ctx, obj->val, prop));
}

int32_t qjs_set_property_str(QJSContextRef ctx, QJSValueRef obj, const char *prop, QJSValueRef val) {
    if (!ctx || !obj || !prop) {
        return -1;
    }
    JSValue duped = val ? JS_DupValue(ctx, val->val) : JS_UNDEFINED;
    return JS_SetPropertyStr(ctx, obj->val, prop, duped);
}

QJSValueRef qjs_get_property_uint32(QJSContextRef ctx, QJSValueRef obj, uint32_t idx) {
    if (!ctx || !obj) {
        return qjs_box_take(JS_UNDEFINED);
    }
    return qjs_box_take(JS_GetPropertyUint32(ctx, obj->val, idx));
}

int32_t qjs_set_property_uint32(QJSContextRef ctx, QJSValueRef obj, uint32_t idx, QJSValueRef val) {
    if (!ctx || !obj) {
        return -1;
    }
    JSValue duped = val ? JS_DupValue(ctx, val->val) : JS_UNDEFINED;
    return JS_SetPropertyUint32(ctx, obj->val, idx, duped);
}

bool qjs_has_property_str(QJSContextRef ctx, QJSValueRef obj, const char *prop) {
    if (!ctx || !obj || !prop) {
        return false;
    }
    JSAtom atom = JS_NewAtom(ctx, prop);
    int r = JS_HasProperty(ctx, obj->val, atom);
    JS_FreeAtom(ctx, atom);
    if (r < 0) {
        JSValue exc = JS_GetException(ctx);
        JS_FreeValue(ctx, exc);
        return false;
    }
    return r != 0;
}

bool qjs_delete_property_str(QJSContextRef ctx, QJSValueRef obj, const char *prop) {
    if (!ctx || !obj || !prop) {
        return false;
    }
    JSAtom atom = JS_NewAtom(ctx, prop);
    int r = JS_DeleteProperty(ctx, obj->val, atom, 0);
    JS_FreeAtom(ctx, atom);
    if (r < 0) {
        JSValue exc = JS_GetException(ctx);
        JS_FreeValue(ctx, exc);
        return false;
    }
    return r != 0;
}

int64_t qjs_get_length(QJSContextRef ctx, QJSValueRef obj) {
    if (!ctx || !obj) {
        return 0;
    }
    int64_t len = 0;
    if (JS_GetLength(ctx, obj->val, &len) < 0) {
        JSValue exc = JS_GetException(ctx);
        JS_FreeValue(ctx, exc);
        return 0;
    }
    return len;
}

bool qjs_get_own_property_names(QJSContextRef ctx, QJSValueRef obj, QJSPropertyKeys *out_keys) {
    if (!out_keys) {
        return false;
    }
    out_keys->keys = NULL;
    out_keys->count = 0;
    if (!ctx || !obj || !JS_IsObject(obj->val)) {
        return false;
    }

    JSPropertyEnum *tab = NULL;
    uint32_t len = 0;
    if (JS_GetOwnPropertyNames(ctx, &tab, &len, obj->val, JS_GPN_STRING_MASK | JS_GPN_ENUM_ONLY) < 0) {
        JSValue exc = JS_GetException(ctx);
        JS_FreeValue(ctx, exc);
        return false;
    }
    if (len == 0) {
        JS_FreePropertyEnum(ctx, tab, len);
        return true;
    }

    char **keys = (char **)calloc(len, sizeof(char *));
    if (!keys) {
        JS_FreePropertyEnum(ctx, tab, len);
        return false;
    }

    for (uint32_t i = 0; i < len; i++) {
        const char *cstr = JS_AtomToCString(ctx, tab[i].atom);
        if (cstr) {
            size_t slen = strlen(cstr);
            keys[i] = (char *)malloc(slen + 1);
            if (keys[i]) {
                memcpy(keys[i], cstr, slen + 1);
            }
            JS_FreeCString(ctx, cstr);
        }
    }

    JS_FreePropertyEnum(ctx, tab, len);
    out_keys->keys = keys;
    out_keys->count = len;
    return true;
}

void qjs_free_property_names(QJSPropertyKeys *keys) {
    if (!keys || !keys->keys) {
        return;
    }
    for (uint32_t i = 0; i < keys->count; i++) {
        free(keys->keys[i]);
    }
    free(keys->keys);
    keys->keys = NULL;
    keys->count = 0;
}

// MARK: - Evaluation, Calls, Exceptions & Jobs

QJSValueRef qjs_eval(QJSContextRef ctx, const char *source, size_t source_len, const char *filename) {
    if (!ctx || !source) {
        return qjs_box_take(JS_UNDEFINED);
    }
    const char *fname = (filename && filename[0] != '\0') ? filename : "<eval>";
    // QuickJS requires source[source_len] == '\0'. Guarantee it even if caller passed a slice.
    char *copy = NULL;
    const char *buf = source;
    if (source[source_len] != '\0') {
        copy = (char *)malloc(source_len + 1);
        if (!copy) {
            return qjs_box_take(JS_ThrowOutOfMemory(ctx));
        }
        memcpy(copy, source, source_len);
        copy[source_len] = '\0';
        buf = copy;
    }
    JSValue res = JS_Eval(ctx, buf, source_len, fname, JS_EVAL_TYPE_GLOBAL);
    free(copy);
    return qjs_box_take(res);
}

QJSValueRef qjs_call(
    QJSContextRef ctx,
    QJSValueRef func,
    QJSValueRef this_val,
    int32_t argc,
    const QJSValueRef *argv)
{
    if (!ctx || !func) {
        return qjs_box_take(JS_UNDEFINED);
    }
    JSValue stack_args[16];
    JSValue *raw_args = stack_args;
    if (argc > 16) {
        raw_args = (JSValue *)malloc((size_t)argc * sizeof(JSValue));
        if (!raw_args) {
            return qjs_box_take(JS_ThrowOutOfMemory(ctx));
        }
    }
    for (int32_t i = 0; i < argc; i++) {
        raw_args[i] = (argv && argv[i]) ? argv[i]->val : JS_UNDEFINED;
    }
    JSValue this_js = this_val ? this_val->val : JS_UNDEFINED;
    JSValue res = JS_Call(ctx, func->val, this_js, argc, argc > 0 ? raw_args : NULL);
    if (argc > 16) {
        free(raw_args);
    }
    return qjs_box_take(res);
}

QJSValueRef qjs_invoke(
    QJSContextRef ctx,
    QJSValueRef this_val,
    const char *method,
    int32_t argc,
    const QJSValueRef *argv)
{
    if (!ctx || !this_val || !method) {
        return qjs_box_take(JS_UNDEFINED);
    }
    JSValue stack_args[16];
    JSValue *raw_args = stack_args;
    if (argc > 16) {
        raw_args = (JSValue *)malloc((size_t)argc * sizeof(JSValue));
        if (!raw_args) {
            return qjs_box_take(JS_ThrowOutOfMemory(ctx));
        }
    }
    for (int32_t i = 0; i < argc; i++) {
        raw_args[i] = (argv && argv[i]) ? argv[i]->val : JS_UNDEFINED;
    }
    JSAtom atom = JS_NewAtom(ctx, method);
    JSValue res = JS_Invoke(ctx, this_val->val, atom, argc, argc > 0 ? raw_args : NULL);
    JS_FreeAtom(ctx, atom);
    if (argc > 16) {
        free(raw_args);
    }
    return qjs_box_take(res);
}

QJSValueRef qjs_call_constructor(
    QJSContextRef ctx,
    QJSValueRef func,
    int32_t argc,
    const QJSValueRef *argv)
{
    if (!ctx || !func) {
        return qjs_box_take(JS_UNDEFINED);
    }
    JSValue stack_args[16];
    JSValue *raw_args = stack_args;
    if (argc > 16) {
        raw_args = (JSValue *)malloc((size_t)argc * sizeof(JSValue));
        if (!raw_args) {
            return qjs_box_take(JS_ThrowOutOfMemory(ctx));
        }
    }
    for (int32_t i = 0; i < argc; i++) {
        raw_args[i] = (argv && argv[i]) ? argv[i]->val : JS_UNDEFINED;
    }
    JSValue res = JS_CallConstructor(ctx, func->val, argc, argc > 0 ? raw_args : NULL);
    if (argc > 16) {
        free(raw_args);
    }
    return qjs_box_take(res);
}

bool qjs_has_exception(QJSContextRef ctx) {
    return ctx && JS_HasException(ctx);
}

QJSValueRef qjs_get_exception(QJSContextRef ctx) {
    if (!ctx) {
        return qjs_box_take(JS_UNDEFINED);
    }
    return qjs_box_take(JS_GetException(ctx));
}

QJSValueRef qjs_throw(QJSContextRef ctx, QJSValueRef val) {
    if (!ctx) {
        return NULL;
    }
    JSValue duped = val ? JS_DupValue(ctx, val->val) : JS_UNDEFINED;
    return qjs_box_take(JS_Throw(ctx, duped));
}

QJSValueRef qjs_throw_error(QJSContextRef ctx, const char *message) {
    if (!ctx) {
        return NULL;
    }
    return qjs_box_take(JS_ThrowPlainError(ctx, "%s", message ? message : "Error"));
}

bool qjs_is_job_pending(QJSRuntimeRef rt) {
    return rt && JS_IsJobPending(rt);
}

int32_t qjs_execute_pending_job(QJSRuntimeRef rt, QJSContextRef *out_ctx) {
    if (!rt) {
        if (out_ctx) {
            *out_ctx = NULL;
        }
        return 0;
    }
    JSContext *pctx = NULL;
    int r = JS_ExecutePendingJob(rt, &pctx);
    if (out_ctx) {
        *out_ctx = pctx;
    }
    return (int32_t)r;
}
