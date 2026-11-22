#pragma once
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

void cak_free(void *ptr);

// Clipboard (write/read payload helpers; sequence/clear/probing/concealed use NativeAPI.Clipboard)
char *cak_clipboard_get_text(void);
int cak_clipboard_set_text(const char *utf8_text);
int cak_clipboard_add_text(const char *utf8_text);
char *cak_clipboard_get_files_newline(void);
int cak_clipboard_set_files(const char *const *utf8_paths, int count);
int cak_clipboard_add_files(const char *const *utf8_paths, int count);
uint8_t *cak_clipboard_get_png(size_t *out_len);
int cak_clipboard_set_png(const uint8_t *png_data, size_t len);
int cak_clipboard_add_png(const uint8_t *png_data, size_t len);
int cak_clipboard_add_custom(const char *utf8_format, const uint8_t *data, size_t len);
uint8_t *cak_clipboard_get_custom(const char *utf8_format, size_t *out_len);
uint8_t *cak_clipboard_get_rtf(size_t *out_len);
uint8_t *cak_clipboard_get_html(size_t *out_len);

// Workspace, Shell & Processes
int cak_open_url_or_path(const char *utf8_target);
int cak_open_with_app(const char *utf8_app, const char *utf8_arg);
int cak_reveal_in_explorer(const char *utf8_path);
uint32_t cak_frontmost_pid(void);
uint32_t cak_frontmost_real_pid(void);
uint32_t cak_current_pid(void);
int cak_process_info(uint32_t pid, char *exe_buf, int exe_cap, char *title_buf, int title_cap);
int cak_activate_pid(uint32_t pid);
int cak_hide_pid(uint32_t pid);
int cak_terminate_pid(uint32_t pid, int force);
uint32_t *cak_enum_gui_pids(int *out_count);
uint8_t *cak_file_icon_png(const char *utf8_path, int size_px, size_t *out_len);
uint8_t *cak_shell_thumbnail_png(const char *utf8_path, int max_px, int *out_w, int *out_h, size_t *out_len);
int cak_resolve_lnk(
    const char *utf8_lnk_path,
    char *target_buf, int target_cap,
    char *args_buf, int args_cap,
    char *icon_buf, int icon_cap,
    int *out_icon_index,
    char *desc_buf, int desc_cap
);
char *cak_known_start_menu_dirs_newline(void);

// Graphics, Font & Theme
int cak_image_dimensions(const uint8_t *data, size_t len, int *out_w, int *out_h);
int cak_image_file_dimensions(const char *utf8_path, int *out_w, int *out_h);
uint8_t *cak_image_resize_png(const uint8_t *data, size_t len, int max_px, size_t *out_len);
uint8_t *cak_image_resize_png_dims(const uint8_t *data, size_t len, int max_px, int *out_w, int *out_h, size_t *out_len);
void cak_font_metrics(
    const char *family,
    double size,
    double weight,
    double *out_ascender,
    double *out_descender,
    double *out_cap_height,
    double *out_x_height,
    double *out_leading
);
void cak_enable_per_monitor_dpi(void);

// Window & FieldEditor & Cursor & Synthetic Input
void cak_window_set_backdrop(void *hwnd, int backdrop_kind, int is_dark);
void cak_window_set_tool_style(void *hwnd, int hide_from_taskbar, int non_activating);
void cak_window_apply_frameless(void *hwnd, int is_frameless);
uint32_t cak_modifier_flags(void);
void cak_set_cursor(int cursor_kind);
void *cak_focused_hwnd(void);
void cak_edit_get_selection(void *hwnd, int *out_start, int *out_length);
void cak_edit_set_selection(void *hwnd, int start, int length);
int cak_edit_has_ime_composition(void *hwnd);
char *cak_hwnd_get_text(void *hwnd);
int cak_send_paste_chord(void);
int cak_send_copy_chord(void);
int cak_send_vk_key(uint16_t vk);
int cak_send_unicode_text(const char *utf8_text);
int cak_send_backspaces(int count);
uint32_t cak_current_thread_id(void);
int cak_pump_mouse_tracking_step(int *out_event, double *out_screen_x, double *out_screen_y);

// External Window Management
typedef struct {
  uint64_t hwnd;
  uint32_t pid;
  int32_t x, y, width, height;
  int32_t is_maximized;
  int32_t is_minimized;
} cak_win_entry;

cak_win_entry *cak_enum_top_windows(int *out_count);
char *cak_hwnd_title(uint64_t hwnd);
int cak_set_window_rect(uint64_t hwnd, int x, int y, int width, int height);
int cak_control_window(uint64_t hwnd, int action); // 1=minimize, 2=maximize, 3=restore, 4=close, 5=focus

// System Actions
int cak_lock_workstation(void);
int cak_empty_recycle_bin(void);

// Crypto (Windows CNG BCrypt)
int cak_sha256(const uint8_t *data, size_t len, uint8_t out_digest[32]);
int cak_sha384(const uint8_t *data, size_t len, uint8_t out_digest[48]);
int cak_sha512(const uint8_t *data, size_t len, uint8_t out_digest[64]);
int cak_sha1(const uint8_t *data, size_t len, uint8_t out_digest[20]);
int cak_md5(const uint8_t *data, size_t len, uint8_t out_digest[16]);
int cak_pbkdf2(
    int alg_id, // 1=SHA1, 2=SHA224(unsupported), 3=SHA256, 4=SHA384, 5=SHA512
    const uint8_t *password, size_t password_len,
    const uint8_t *salt, size_t salt_len,
    uint32_t iterations,
    uint8_t *out_key, size_t key_len
);
int cak_aes_crypt(
    int decrypt,
    int ecb_mode,
    int pkcs7_pad,
    const uint8_t *key, size_t key_len,
    const uint8_t *iv,
    const uint8_t *data, size_t data_len,
    uint8_t *out_buf, size_t out_cap,
    size_t *out_written
);
int cak_hmac_sha256(
    const uint8_t *key, size_t key_len,
    const uint8_t *data, size_t data_len,
    uint8_t out_mac[32]
);
int cak_aes_gcm_decrypt(
    const uint8_t *key, size_t key_len,
    const uint8_t *nonce, size_t nonce_len,
    const uint8_t *ciphertext, size_t ciphertext_len,
    const uint8_t *aad, size_t aad_len,
    const uint8_t *tag, size_t tag_len,
    uint8_t *out_plaintext
);
int cak_aes_gcm_encrypt(
    const uint8_t *key, size_t key_len,
    const uint8_t *nonce, size_t nonce_len,
    const uint8_t *plaintext, size_t plaintext_len,
    const uint8_t *aad, size_t aad_len,
    uint8_t *out_ciphertext,
    uint8_t *out_tag, size_t tag_len
);
int cak_random_bytes(uint8_t *buf, size_t len);

// POSIX / Darwin File & Directory Shims
typedef struct {
  uint16_t st_mode;
  uint32_t st_flags;
  int64_t st_size;
  int64_t mtime_sec;
  int64_t mtime_nsec;
  int64_t atime_sec;
  int64_t atime_nsec;
  int64_t ctime_sec;
  int64_t ctime_nsec;
  int64_t btime_sec;
  int64_t btime_nsec;
} cak_stat_info;

int cak_posix_open(const char *utf8_path, int posix_flags, int mode, int *out_errno);
int cak_posix_close(int fd);
int cak_posix_stat(const char *utf8_path, int follow_links, cak_stat_info *out_info, int *out_errno);
int cak_posix_fstat(int fd, cak_stat_info *out_info, int *out_errno);
int cak_posix_mkdir(const char *utf8_path, int *out_errno);
int cak_posix_utimes(
    const char *utf8_path,
    int64_t atime_sec, int64_t atime_usec,
    int64_t mtime_sec, int64_t mtime_usec,
    int *out_errno
);
char *cak_realpath(const char *utf8_path);
int cak_getattrlistbulk(int dirfd, void *attrbuf, size_t attrbuf_size);

// Windows Credential Manager (Keychain shim)
int cak_cred_available(void);
int cak_cred_write(const char *utf8_target, const char *utf8_user, const uint8_t *secret, size_t len);
uint8_t *cak_cred_read(const char *utf8_target, size_t *out_len);
int cak_cred_delete(const char *utf8_target);
int cak_cred_exists(const char *utf8_target);

int cak_login_item_status(const char *utf8_app_name);
int cak_login_item_set(const char *utf8_app_name, const char *utf8_command);
int cak_login_item_remove(const char *utf8_app_name);

void cak_window_relinquish_focus(void *hwnd_ptr);
int cak_send_paste_chord_to_pid(uint32_t pid);
int cak_is_background_pasting(void);

typedef void (*cak_single_instance_callback)(const char *utf8_payload);
int cak_single_instance_acquire(
    const char *utf8_app_id,
    const char *utf8_payload,
    int notify_primary,
    int wait_ms,
    cak_single_instance_callback callback
);
void cak_single_instance_release(void);

#ifdef __cplusplus
}
#endif
