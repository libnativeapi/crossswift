#include "shim_sqlite3.h"
#include <stddef.h>

int _crossappkit_sqlite3_anchor(void) { return 0; }

#if defined(__OHOS__)
#define CAK_SQLITE_WEAK __attribute__((weak))

CAK_SQLITE_WEAK int sqlite3_open(const char *filename, sqlite3 **ppDb) {
  (void)filename;
  if (ppDb) *ppDb = NULL;
  return SQLITE_ERROR;
}

CAK_SQLITE_WEAK int sqlite3_open_v2(const char *filename, sqlite3 **ppDb, int flags, const char *zVfs) {
  (void)filename;
  (void)flags;
  (void)zVfs;
  if (ppDb) *ppDb = NULL;
  return SQLITE_ERROR;
}

CAK_SQLITE_WEAK int sqlite3_close(sqlite3 *db) {
  (void)db;
  return SQLITE_OK;
}

CAK_SQLITE_WEAK int sqlite3_close_v2(sqlite3 *db) {
  (void)db;
  return SQLITE_OK;
}

CAK_SQLITE_WEAK int sqlite3_busy_timeout(sqlite3 *db, int ms) {
  (void)db;
  (void)ms;
  return SQLITE_OK;
}

CAK_SQLITE_WEAK int sqlite3_changes(sqlite3 *db) {
  (void)db;
  return 0;
}

CAK_SQLITE_WEAK sqlite3_int64 sqlite3_last_insert_rowid(sqlite3 *db) {
  (void)db;
  return 0;
}

CAK_SQLITE_WEAK const char *sqlite3_errmsg(sqlite3 *db) {
  (void)db;
  return "SQLite3 is unavailable on HarmonyOS";
}

CAK_SQLITE_WEAK int sqlite3_errcode(sqlite3 *db) {
  (void)db;
  return SQLITE_ERROR;
}

CAK_SQLITE_WEAK void sqlite3_progress_handler(
  sqlite3 *db, int nOps, int (*xProgress)(void *), void *pArg
) {
  (void)db;
  (void)nOps;
  (void)xProgress;
  (void)pArg;
}

CAK_SQLITE_WEAK int sqlite3_exec(
  sqlite3 *db, const char *sql, sqlite3_callback callback, void *arg, char **errmsg
) {
  (void)db;
  (void)sql;
  (void)callback;
  (void)arg;
  if (errmsg) *errmsg = NULL;
  return SQLITE_ERROR;
}

CAK_SQLITE_WEAK int sqlite3_prepare_v2(
  sqlite3 *db, const char *zSql, int nByte, sqlite3_stmt **ppStmt, const char **pzTail
) {
  (void)db;
  (void)zSql;
  (void)nByte;
  if (ppStmt) *ppStmt = NULL;
  if (pzTail) *pzTail = NULL;
  return SQLITE_ERROR;
}

CAK_SQLITE_WEAK int sqlite3_step(sqlite3_stmt *pStmt) {
  (void)pStmt;
  return SQLITE_DONE;
}

CAK_SQLITE_WEAK int sqlite3_reset(sqlite3_stmt *pStmt) {
  (void)pStmt;
  return SQLITE_OK;
}

CAK_SQLITE_WEAK int sqlite3_clear_bindings(sqlite3_stmt *pStmt) {
  (void)pStmt;
  return SQLITE_OK;
}

CAK_SQLITE_WEAK int sqlite3_finalize(sqlite3_stmt *pStmt) {
  (void)pStmt;
  return SQLITE_OK;
}

CAK_SQLITE_WEAK int sqlite3_bind_blob(
  sqlite3_stmt *pStmt, int idx, const void *val, int nBytes, sqlite3_destructor_type destructor
) {
  (void)pStmt;
  (void)idx;
  (void)val;
  (void)nBytes;
  (void)destructor;
  return SQLITE_ERROR;
}

CAK_SQLITE_WEAK int sqlite3_bind_double(sqlite3_stmt *pStmt, int idx, double val) {
  (void)pStmt;
  (void)idx;
  (void)val;
  return SQLITE_ERROR;
}

CAK_SQLITE_WEAK int sqlite3_bind_int(sqlite3_stmt *pStmt, int idx, int val) {
  (void)pStmt;
  (void)idx;
  (void)val;
  return SQLITE_ERROR;
}

CAK_SQLITE_WEAK int sqlite3_bind_int64(sqlite3_stmt *pStmt, int idx, sqlite3_int64 val) {
  (void)pStmt;
  (void)idx;
  (void)val;
  return SQLITE_ERROR;
}

CAK_SQLITE_WEAK int sqlite3_bind_null(sqlite3_stmt *pStmt, int idx) {
  (void)pStmt;
  (void)idx;
  return SQLITE_ERROR;
}

CAK_SQLITE_WEAK int sqlite3_bind_text(
  sqlite3_stmt *pStmt, int idx, const char *val, int nBytes, sqlite3_destructor_type destructor
) {
  (void)pStmt;
  (void)idx;
  (void)val;
  (void)nBytes;
  (void)destructor;
  return SQLITE_ERROR;
}

CAK_SQLITE_WEAK const void *sqlite3_column_blob(sqlite3_stmt *pStmt, int iCol) {
  (void)pStmt;
  (void)iCol;
  return NULL;
}

CAK_SQLITE_WEAK int sqlite3_column_bytes(sqlite3_stmt *pStmt, int iCol) {
  (void)pStmt;
  (void)iCol;
  return 0;
}

CAK_SQLITE_WEAK double sqlite3_column_double(sqlite3_stmt *pStmt, int iCol) {
  (void)pStmt;
  (void)iCol;
  return 0.0;
}

CAK_SQLITE_WEAK int sqlite3_column_int(sqlite3_stmt *pStmt, int iCol) {
  (void)pStmt;
  (void)iCol;
  return 0;
}

CAK_SQLITE_WEAK sqlite3_int64 sqlite3_column_int64(sqlite3_stmt *pStmt, int iCol) {
  (void)pStmt;
  (void)iCol;
  return 0;
}

CAK_SQLITE_WEAK const unsigned char *sqlite3_column_text(sqlite3_stmt *pStmt, int iCol) {
  (void)pStmt;
  (void)iCol;
  return NULL;
}

CAK_SQLITE_WEAK int sqlite3_column_type(sqlite3_stmt *pStmt, int iCol) {
  (void)pStmt;
  (void)iCol;
  return SQLITE_NULL;
}

CAK_SQLITE_WEAK int sqlite3_column_count(sqlite3_stmt *pStmt) {
  (void)pStmt;
  return 0;
}
#endif

