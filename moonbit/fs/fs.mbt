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
// ── vendored into vitro/engine/fs（唯一依赖清除 B 路线批，2026-09-28）──
// 来源：moonbitlang/x@0.5.5 的 fs/fs.mbt（上游 main 与 0.5.5 逐位一致，
// sha256 41d895c76d4694aaa80b3f93cdb456aa99a480f997c3282aab78421458baaa0e）。
// 改动：① read_file_to_bytes / is_file / remove_dir / remove_file 四函数去 pub
//   ——本仓消费面仅 cmd×5 的 7 函数（moonbit_surface 无主 pub 闸约束），
//   四函数保留 priv 形态由白盒测试全量覆盖，上游跟进时 diff 仍可读；
//   ② 文件头追加本标注。
// 上游漂移监控：go run ./scripts/moonbit/vendor_drift（基线
// scripts/moonbit/vendor_baseline.json；红 = 人工评估令，非自动同步令）。
// 许可：本文件为 Apache-2.0 许可的 vendored 衍生，模块级说明见 THIRD_PARTY.md。

///|
pub(all) suberror IOError {
  IOError(String)
} derive(Debug)

///|
/// Reads the content of a file specified by the given path and returns its
/// content as `Bytes`
///
/// # Parameters
///
/// - `path` : The path to the file to be read.
///
/// # Returns
///
/// - A `Bytes` representing the content of the file.
fn read_file_to_bytes(path : String) -> Bytes raise IOError {
  read_file_to_bytes_internal(path)
}

///|
/// Reads the content of a file specified by the given path and returns its
/// content as `String`.
///
/// # Parameters
///
/// - `path` : The path to the file to be read.
/// - `encoding~` : The encoding of the file. Only support `utf8` for now.
///
/// # Returns
///
/// - A `String` representing the content of the file.
pub fn read_file_to_string(
  path : String,
  encoding? : String = "utf8",
) -> String raise IOError {
  read_file_to_string_internal(path, encoding~)
}

///|
/// Writes a `Bytes` to a file at the specified path.
///
/// # Parameters
///
/// - `path` : The path to the file where the bytes will be written.
/// - `content` : A `Bytes` to be written to the file.
pub fn write_bytes_to_file(
  path : String,
  content : Bytes,
) -> Unit raise IOError {
  write_bytes_to_file_internal(path, content)
}

///|
/// Writes a `String` to a file at the specified path.
///
/// # Parameters
///
/// - `path` : The path to the file where the string will be written.
/// - `content` : A `String` to be written to the file.
/// - `encoding~` : The encoding of the file. Only support `utf8` for now.
pub fn write_string_to_file(
  path : String,
  content : String,
  encoding? : String = "utf8",
) -> Unit raise IOError {
  write_string_to_file_internal(path, content, encoding~)
}

///|
/// Checks if a path exists.
///
/// # Parameters
/// - `path`: A `String` representing the file path.
///
/// # Returns
/// A boolean indicating whether the path exists.
pub fn path_exists(path : String) -> Bool {
  path_exists_internal(path)
}

///|
/// Reads the contents of a directory and returns a read-only view of filenames.
///
/// # Parameters
///
/// - `path` : The path to the directory to be read.
///
/// # Returns
///
/// - A view of strings representing the file names and directory names in the directory.
///   Use `to_owned()` to copy the view into a mutable array.
pub fn read_dir(path : String) -> ArrayView[String] raise IOError {
  read_dir_internal(path)
}

///|
/// Creates a directory at the specified path.
/// Note: nested directories are not supported for native backend
///
/// # Parameters
///
/// - `path` : The path where the directory should be created.
/// - `mode~` : The mode of the directory. Default is `777`.
pub fn create_dir(path : String) -> Unit raise IOError {
  create_dir_internal(path)
}

///|
/// Checks if the given path is a directory.
///
/// # Parameters
///
/// - `path` : The string representing the path to be checked.
///
/// # Returns
///
/// - `Bool` : `true` if the path is a directory, `false` otherwise.
pub fn is_dir(path : String) -> Bool raise IOError {
  is_dir_internal(path)
}

///|
/// Check if the given path points to a file.
///
/// # Parameters
///
/// - `path` : The string representing the path to be checked.
///
/// # Returns
///
/// - `Bool` : `true` if the path points to a file, `false` otherwise.
fn is_file(path : String) -> Bool raise IOError {
  is_file_internal(path)
}

///|
/// Removes a directory at the specified path.
///
/// # Parameters
///
/// - `path` : The string path to the directory that needs to be removed.
fn remove_dir(path : String) -> Unit raise IOError {
  remove_dir_internal(path)
}

///|
/// Removes a file at the specified path.
///
/// # Parameters
///
/// - `path` : The path to the file that needs to be removed.
fn remove_file(path : String) -> Unit raise IOError {
  remove_file_internal(path)
}

///|
#deprecated
pub extend IOError with Debug::{to_repr}
