// Copyright 2025 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// ── vendored into vitro/engine/fs (唯一依赖清除 B 路线批, 2026-09-28) ──
// 来源: moonbitlang/x@0.5.5 的 fs/fs_native.c (上游 main 与 0.5.5 逐位一致,
// sha256 f10144a5cbd2a4fa36fa4f058b1461b6788ec43b9e4fd9bb0be3015e3aa272b0)。
// 改动: ① C 符号前缀 moonbitlang_x_fs_* → vitro_engine_fs_* 与 typedef
//   moonbitlang_x_os_string_t → vitro_engine_fs_os_string_t (防与任何同时
//   链接的 x 版本符号撞名); ② 文件头追加本标注。
// ── 本地逻辑修复 (B3 批 2026-11-02, 审阅 v2 M37 A-3 / V3-③-A1; 两处均为
//   上游同病, 本仓先修——Apache-2.0 §4(b) 修改声明即本段; 登记见
//   moonbit/THIRD_PARTY.md「本地逻辑修复」节) ──
// ③ _WIN32 stat 族 (stat/is_dir/is_file) 走 GetFileAttributesW, 失败**不设
//   CRT errno**, get_error_message 读到前序 CRT 调用残留 (实测: create_dir
//   已存在置 EEXIST 后 is_dir(不存在路径) 报 "File exists"; remove_dir 非空
//   置 ENOTEMPTY 后 is_file(不存在) 报 "Directory not empty")——失败路径
//   按 GetLastError 映射 errno (POSIX 分支 stat 天然设 errno 无此病)。
// ④ read_dir 两次遍历 (先计数再填充) 存在 TOCTOU: 两遍之间目录收缩 →
//   尾部 NULL 槽 (MoonBit 侧撞 null); 目录增长 → result[index++] 越界写
//   (堆溢出)。改单遍历动态缓冲 (倍增 realloc) 后一次性拷入定长 ref_array。
// 上游漂移监控: node scripts/moonbit/vendor_drift/main.mts (比上游 main 与
//   基线, 不比本仓文件——本地修复不触该闸; 上游修复日按基线漂移评估合流)。

#ifdef __cplusplus
extern "C" {
#endif

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <wchar.h>

#ifdef _WIN32
#include <direct.h>
#include <windows.h>
#else
#include <dirent.h>
#include <unistd.h>
#endif

#include "moonbit.h"

#ifdef _WIN32
typedef moonbit_string_t vitro_engine_fs_os_string_t;
#else
typedef moonbit_bytes_t vitro_engine_fs_os_string_t;
#endif

MOONBIT_FFI_EXPORT FILE *
vitro_engine_fs_fopen_ffi(vitro_engine_fs_os_string_t path,
                          vitro_engine_fs_os_string_t mode) {
#ifdef _WIN32
  return _wfopen((const wchar_t *)path, (const wchar_t *)mode);
#else
  return fopen((const char *)path, (const char *)mode);
#endif
}

MOONBIT_FFI_EXPORT int vitro_engine_fs_is_null(void *ptr) {
  return ptr == NULL;
}

MOONBIT_FFI_EXPORT size_t vitro_engine_fs_fread_ffi(moonbit_bytes_t ptr,
                                                    int size, int nitems,
                                                    FILE *stream) {
  return fread(ptr, size, nitems, stream);
}

MOONBIT_FFI_EXPORT size_t vitro_engine_fs_fwrite_ffi(moonbit_bytes_t ptr,
                                                     int size, int nitems,
                                                     FILE *stream) {
  return fwrite(ptr, size, nitems, stream);
}

MOONBIT_FFI_EXPORT int vitro_engine_fs_fseek_ffi(FILE *stream, long offset,
                                                 int whence) {
  return fseek(stream, offset, whence);
}

MOONBIT_FFI_EXPORT long vitro_engine_fs_ftell_ffi(FILE *stream) {
  return ftell(stream);
}

MOONBIT_FFI_EXPORT int vitro_engine_fs_fflush_ffi(FILE *file) {
  return fflush(file);
}

MOONBIT_FFI_EXPORT int vitro_engine_fs_fclose_ffi(FILE *stream) {
  return fclose(stream);
}

MOONBIT_FFI_EXPORT moonbit_bytes_t vitro_engine_fs_get_error_message(void) {
  const char *err_str = strerror(errno);
  size_t len = strlen(err_str);
  moonbit_bytes_t bytes = moonbit_make_bytes(len, 0);
  memcpy(bytes, err_str, len);
  return bytes;
}

#ifdef _WIN32
// 改动 ③ (B3 批): Win32 API 失败 → CRT errno 映射。GetFileAttributesW 不触
// CRT errno, 不映射则 get_error_message 返回前序 CRT 调用残留 (张冠李戴)。
// 映射面只覆盖 stat 族可能遇到的码位; 其余归 EIO (fail loud 不静默 0)。
static void vitro_engine_fs_errno_from_last_error(void) {
  switch (GetLastError()) {
  case ERROR_FILE_NOT_FOUND:
  case ERROR_PATH_NOT_FOUND:
  case ERROR_INVALID_NAME:
  case ERROR_BAD_NETPATH:
    errno = ENOENT;
    break;
  case ERROR_ACCESS_DENIED:
  case ERROR_SHARING_VIOLATION:
  case ERROR_LOCK_VIOLATION:
    errno = EACCES;
    break;
  case ERROR_NOT_ENOUGH_MEMORY:
  case ERROR_OUTOFMEMORY:
    errno = ENOMEM;
    break;
  default:
    errno = EIO;
    break;
  }
}
#endif

MOONBIT_FFI_EXPORT int
vitro_engine_fs_stat_ffi(vitro_engine_fs_os_string_t path) {
#ifdef _WIN32
  if (GetFileAttributesW((LPCWSTR)path) == INVALID_FILE_ATTRIBUTES) {
    vitro_engine_fs_errno_from_last_error();
    return -1;
  }
  return 0;
#else
  struct stat buffer;
  int status = stat((const char *)path, &buffer);
  return status;
#endif
}

MOONBIT_FFI_EXPORT int
vitro_engine_fs_is_dir_ffi(vitro_engine_fs_os_string_t path) {
#ifdef _WIN32
  DWORD attrs = GetFileAttributesW((LPCWSTR)path);
  if (attrs == INVALID_FILE_ATTRIBUTES) {
    vitro_engine_fs_errno_from_last_error();
    return -1;
  }
  if (attrs & FILE_ATTRIBUTE_DIRECTORY) {
    return 1;
  }
  return 0;
#else
  struct stat buffer;
  int status = stat((const char *)path, &buffer);
  if (status == -1) {
    return -1;
  }
  if (S_ISDIR(buffer.st_mode)) {
    return 1;
  }
  return 0;
#endif
}

MOONBIT_FFI_EXPORT int
vitro_engine_fs_is_file_ffi(vitro_engine_fs_os_string_t path) {
#ifdef _WIN32
  DWORD attrs = GetFileAttributesW((LPCWSTR)path);
  if (attrs == INVALID_FILE_ATTRIBUTES) {
    vitro_engine_fs_errno_from_last_error();
    return -1;
  }
  if (!(attrs & FILE_ATTRIBUTE_DIRECTORY)) {
    return 1;
  }
  return 0;
#else
  struct stat buffer;
  int status = stat((const char *)path, &buffer);
  if (status == -1) {
    return -1;
  }
  if (S_ISREG(buffer.st_mode)) {
    return 1;
  }
  return 0;
#endif
}

MOONBIT_FFI_EXPORT int
vitro_engine_fs_remove_dir_ffi(vitro_engine_fs_os_string_t path) {
#ifdef _WIN32
  return _wrmdir((const wchar_t *)path);
#else
  return rmdir((const char *)path);
#endif
}

MOONBIT_FFI_EXPORT int
vitro_engine_fs_remove_file_ffi(vitro_engine_fs_os_string_t path) {
#ifdef _WIN32
  return _wremove((const wchar_t *)path);
#else
  return remove((const char *)path);
#endif
}

MOONBIT_FFI_EXPORT int
vitro_engine_fs_create_dir_ffi(vitro_engine_fs_os_string_t path) {
#ifdef _WIN32
  return _wmkdir((const wchar_t *)path);
#else
  return mkdir((const char *)path, 0777);
#endif
}

// 改动 ④ (B3 批): read_dir 单遍历——边遍历边收进倍增缓冲, 遍历结束后按
// 实测条目数一次性拷入定长 ref_array。旧两遍历 (先计数再填充) 在两遍之间
// 目录变化即 TOCTOU: 收缩 → 尾部 NULL 槽; 增长 → 越界写。
// 缓冲元素是已分配的 MoonBit 对象指针 (moonbit_make_string/bytes 新对象 RC=1),
// 成功路径逐条**移动**进 ref_array (不 incref); 分配失败路径须对已建条目逐条
// moonbit_decref 再 free 缓冲本体——否则未进 array 的对象无人回收 (PR #450 审阅
// P3-3: 初版注释写了该义务而代码只 free(items), 本版兑现)。
#define VITRO_ENGINE_FS_READ_DIR_INITIAL_CAP 16

// read_dir 失败路径的缓冲清理: 已建 MoonBit 对象逐条 decref (RC=1 → 0 释放) 后
// free 缓冲本体。两平台分支共用 (元素类型 moonbit_string_t / moonbit_bytes_t 均为
// 对象指针, 以 void* 接)。
static void vitro_engine_fs_read_dir_drop_items(void **items, int count) {
  for (int i = 0; i < count; i++) {
    moonbit_decref(items[i]);
  }
  free(items);
}

MOONBIT_FFI_EXPORT vitro_engine_fs_os_string_t *
vitro_engine_fs_read_dir_ffi(vitro_engine_fs_os_string_t path) {
#ifdef _WIN32
  WIN32_FIND_DATAW find_data;
  HANDLE dir;
  moonbit_string_t *result = NULL;
  moonbit_string_t *items = NULL;
  size_t cap = VITRO_ENGINE_FS_READ_DIR_INITIAL_CAP;
  int count = 0;

  size_t path_len = wcslen((const wchar_t *)path);
  WCHAR *search_path = malloc((path_len + 3) * sizeof(WCHAR));
  if (search_path == NULL) {
    return NULL;
  }

  memcpy(search_path, path, path_len * sizeof(WCHAR));
  search_path[path_len] = L'\\';
  search_path[path_len + 1] = L'*';
  search_path[path_len + 2] = L'\0';
  dir = FindFirstFileW(search_path, &find_data);
  free(search_path);
  if (dir == INVALID_HANDLE_VALUE) {
    DWORD error = GetLastError();
    fprintf(stderr, "Failed to open directory: error code %lu\n", error);
    return NULL;
  }

  items = (moonbit_string_t *)malloc(cap * sizeof(moonbit_string_t));
  if (items == NULL) {
    FindClose(dir);
    return NULL;
  }

  do {
    if (wcscmp(find_data.cFileName, L".") != 0 &&
        wcscmp(find_data.cFileName, L"..") != 0) {
      if ((size_t)count == cap) {
        size_t new_cap = cap * 2;
        moonbit_string_t *grown = (moonbit_string_t *)realloc(
            items, new_cap * sizeof(moonbit_string_t));
        if (grown == NULL) {
          vitro_engine_fs_read_dir_drop_items((void **)items, count);
          FindClose(dir);
          return NULL;
        }
        items = grown;
        cap = new_cap;
      }
      size_t name_len = wcslen(find_data.cFileName);
      moonbit_string_t item = moonbit_make_string(name_len, 0);
      memcpy(item, find_data.cFileName, name_len * sizeof(WCHAR));
      items[count++] = item;
    }
  } while (FindNextFileW(dir, &find_data));

  FindClose(dir);

  result = (moonbit_string_t *)moonbit_make_ref_array(count, NULL);
  if (result == NULL) {
    vitro_engine_fs_read_dir_drop_items((void **)items, count);
    return NULL;
  }
  for (int i = 0; i < count; i++) {
    result[i] = items[i];
  }
  free(items);
  return result;
#else

  DIR *dir;
  struct dirent *entry;
  moonbit_bytes_t *result = NULL;
  moonbit_bytes_t *items = NULL;
  size_t cap = VITRO_ENGINE_FS_READ_DIR_INITIAL_CAP;
  int count = 0;

  // open the directory
  dir = opendir((const char *)path);
  if (dir == NULL) {
    perror("opendir");
    return NULL;
  }

  items = (moonbit_bytes_t *)malloc(cap * sizeof(moonbit_bytes_t));
  if (items == NULL) {
    closedir(dir);
    return NULL;
  }

  // single traversal: collect into a growable buffer
  while ((entry = readdir(dir)) != NULL) {
    // ignore only . and ..
    if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
      continue;
    }
    if ((size_t)count == cap) {
      size_t new_cap = cap * 2;
      moonbit_bytes_t *grown =
          (moonbit_bytes_t *)realloc(items, new_cap * sizeof(moonbit_bytes_t));
      if (grown == NULL) {
        vitro_engine_fs_read_dir_drop_items((void **)items, count);
        closedir(dir);
        return NULL;
      }
      items = grown;
      cap = new_cap;
    }
    size_t name_len = strlen(entry->d_name);
    moonbit_bytes_t item = moonbit_make_bytes(name_len, 0);
    memcpy(item, entry->d_name, name_len);
    items[count++] = item;
  }

  closedir(dir);

  // create moonbit_ref_array sized by the actual count, then move items in
  result = (moonbit_bytes_t *)moonbit_make_ref_array(count, NULL);
  if (result == NULL) {
    vitro_engine_fs_read_dir_drop_items((void **)items, count);
    return NULL;
  }
  for (int i = 0; i < count; i++) {
    result[i] = items[i];
  }
  free(items);
  return result;
#endif
}

#ifdef __cplusplus
}
#endif
