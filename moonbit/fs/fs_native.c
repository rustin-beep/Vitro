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
//   链接的 x 版本符号撞名); ② 文件头追加本标注。逻辑逐字未动。
// 上游漂移监控: go run ./scripts/moonbit/vendor_drift。

#ifdef __cplusplus
extern "C" {
#endif

#include <errno.h>
#include <stdio.h>
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

MOONBIT_FFI_EXPORT int
vitro_engine_fs_stat_ffi(vitro_engine_fs_os_string_t path) {
#ifdef _WIN32
  return GetFileAttributesW((LPCWSTR)path) == INVALID_FILE_ATTRIBUTES ? -1 : 0;
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

MOONBIT_FFI_EXPORT vitro_engine_fs_os_string_t *
vitro_engine_fs_read_dir_ffi(vitro_engine_fs_os_string_t path) {
#ifdef _WIN32
  WIN32_FIND_DATAW find_data;
  HANDLE dir;
  moonbit_string_t *result = NULL;
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
  if (dir == INVALID_HANDLE_VALUE) {
    DWORD error = GetLastError();
    fprintf(stderr, "Failed to open directory: error code %lu\n", error);
    free(search_path);
    return NULL;
  }

  do {
    if (wcscmp(find_data.cFileName, L".") != 0 &&
        wcscmp(find_data.cFileName, L"..") != 0) {
      count++;
    }
  } while (FindNextFileW(dir, &find_data));

  FindClose(dir);
  dir = FindFirstFileW(search_path, &find_data);
  free(search_path);

  result = (moonbit_string_t *)moonbit_make_ref_array(count, NULL);
  if (result == NULL) {
    FindClose(dir);
    return NULL;
  }

  int index = 0;
  do {
    if (wcscmp(find_data.cFileName, L".") != 0 &&
        wcscmp(find_data.cFileName, L"..") != 0) {
      size_t name_len = wcslen(find_data.cFileName);
      moonbit_string_t item = moonbit_make_string(name_len, 0);
      memcpy(item, find_data.cFileName, name_len * sizeof(WCHAR));
      result[index++] = item;
    }
  } while (FindNextFileW(dir, &find_data));

  FindClose(dir);
  return result;
#else

  DIR *dir;
  struct dirent *entry;
  moonbit_bytes_t *result = NULL;
  int count = 0;

  // open the directory
  dir = opendir((const char *)path);
  if (dir == NULL) {
    perror("opendir");
    return NULL;
  }

  // first traversal of the directory, calculate the number of items
  while ((entry = readdir(dir)) != NULL) {
    // ignore only . and ..
    if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
      continue;
    }
    count++;
  }

  // reset the directory stream
  rewinddir(dir);

  // create moonbit_ref_array to store the result
  result = (moonbit_bytes_t *)moonbit_make_ref_array(count, NULL);
  if (result == NULL) {
    closedir(dir);
    return NULL;
  }

  // second traversal of the directory, fill the array
  int index = 0;
  while ((entry = readdir(dir)) != NULL) {
    // ignore only . and ..
    if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
      continue;
    }
    size_t name_len = strlen(entry->d_name);
    moonbit_bytes_t item = moonbit_make_bytes(name_len, 0);
    memcpy(item, entry->d_name, name_len);
    result[index++] = item;
  }

  closedir(dir);
  return result;
#endif
}

#ifdef __cplusplus
}
#endif
