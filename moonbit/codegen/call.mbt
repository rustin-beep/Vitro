///|
/// 函数调用生成（S5 扩展批·CallPtr——**VarDecl 接线后重测**（2026-09-21）
/// 首要阻塞 174 例/363；含阻塞总面更大（口径：每文件最小行号首错统计））——
/// Rust `expr/call.rs::gen_call_ptr` 的 C only 子集照搬：
/// - `gen_call` 本体不迁移（Expr::Call 仅 C++ ctor 路径构造，C 输入
///   不可达——parser 后缀位统一产 CallPtr，两侧同构）；
/// - std__move / reference 实参 / 临时对象析构（temp_cleanups）/ 拷贝
///   构造 / lambda 地址传参不迁移（C++ 专有）；
/// - struct 按值传参的 words 展开 / SplitD/SplitQ 拆分 / 变参 CallVar
///   （U3#2 修复后的 8 字节专用槽形态）/ printf 的 float→double 提升 /
///   host 路由 CallHost / 函数指针间接调用尾部全部保留。
fn BytecodeGen::gen_call_ptr(
  self : BytecodeGen,
  callee : @ast.Expr,
  args : Array[@ast.Expr],
  ret_ty : @ast.Type,
  loc : @source.SourceLoc,
) -> Unit {
  let ret_temp_offset : Int? = if ret_ty.kind() is TK_Struct {
    let sz = {
      let raw = self.type_size(ret_ty)
      if raw % 4 == 0 {
        raw
      } else {
        raw + 4 - raw % 4
      }
    }
    let offset = self.next_local_offset
    self.next_local_offset += sz
    Some(offset)
  } else {
    None
  }
  // 本 CallPtr 解析为用户函数调用（需 SplitD/SplitQ）还是 host/builtin
  // 调用（64 位值直传）
  let is_user_call = match callee {
    Identifier(name, _, _) =>
      self.func_index.contains(name) ||
      @bytecode.host_func_id_by_user_name(name) is None
    _ => true // 间接调用恒为用户调用
  }
  let is_variadic_callee = match callee {
    Identifier(name, _, _) =>
      self.func_index.contains(name) &&
      (match self.func_table.get(name) {
        Some(m) => m.is_variadic
        None => false
      })
    _ => false
  }
  // 实参逆序求值（C 调用约定：从右到左入栈）
  let mut i = args.length() - 1
  while i >= 0 {
    let arg = args[i]
    let arg_ty = arg.ty()
    if arg_ty.kind() is TK_Struct {
      let sz = self.type_size(arg_ty)
      let words = (sz + 3) / 4
      match arg {
        Identifier(arg_name, _, _) =>
          match self.local_indices.get(arg_name) {
            Some(offset) =>
              for w in 0..<words {
                self.emit(@opcode.OpCode::LoadLocal, offset + w * 4, loc)
              }
            None =>
              match self.static_local_indices.get(arg_name) {
                Some(offset) =>
                  for w in 0..<words {
                    self.emit(@opcode.OpCode::LoadGlobal, offset + w * 4, loc)
                  }
                None =>
                  match self.global_indices.get(arg_name) {
                    Some(offset) =>
                      for w in 0..<words {
                        self.emit(
                          @opcode.OpCode::LoadGlobal,
                          offset + w * 4,
                          loc,
                        )
                      }
                    None =>
                      // P1（2026-09-21 审阅修复）：调用返回的 struct 临时对象
                      // ——Rust 的第 4 子路径（call.rs:324-335：gen_expr 存地址
                      // 到 temp_slot0 后逐字 LoadMem；此前误落"零填充"分支，
                      // latent——struct-return 生成批接线前不可达，但接线后
                      // 会以静默错值暴露，随本批先行补齐）
                      if arg is CallPtr(_, _, _, _) {
                        self.gen_expr(arg)
                        let addr_temp = self.get_temp_slot(0)
                        self.emit(@opcode.OpCode::StoreLocal, addr_temp, loc)
                        for w in 0..<words {
                          self.emit(@opcode.OpCode::LoadLocal, addr_temp, loc)
                          if w > 0 {
                            self.emit(@opcode.OpCode::PushConst, w * 4, loc)
                            self.emit(@opcode.OpCode::Add, 0, loc)
                          }
                          self.emit(@opcode.OpCode::LoadMem, 0, loc)
                        }
                      } else {
                        self.gen_expr(arg)
                        for w2 in 1..<words {
                          self.emit(@opcode.OpCode::PushConst, 0, loc)
                        }
                      }
                  }
              }
          }
        _ =>
          // P1 同款：非 Identifier 的调用返回临时对象（use(make()+…) 形态）
          if arg is CallPtr(_, _, _, _) {
            self.gen_expr(arg)
            let addr_temp = self.get_temp_slot(0)
            self.emit(@opcode.OpCode::StoreLocal, addr_temp, loc)
            for w in 0..<words {
              self.emit(@opcode.OpCode::LoadLocal, addr_temp, loc)
              if w > 0 {
                self.emit(@opcode.OpCode::PushConst, w * 4, loc)
                self.emit(@opcode.OpCode::Add, 0, loc)
              }
              self.emit(@opcode.OpCode::LoadMem, 0, loc)
            }
          } else {
            self.gen_expr(arg)
            for w2 in 1..<words {
              self.emit(@opcode.OpCode::PushConst, 0, loc)
            }
          }
      }
    } else if arg_ty.kind() is TK_Double {
      self.gen_expr(arg)
      if is_user_call {
        if is_variadic_callee {
          // 变参函数：按 VM 变参循环顺序 push（低地址在前），先压高 32 位
          // 再压低 32 位。U3#2：8 字节位模式中转必须走 8 字节专用槽
          let temp64 = self.get_temp_slot_64()
          self.emit(@opcode.OpCode::StoreLocalD, temp64, loc)
          self.emit(@opcode.OpCode::LoadLocal, temp64 + 4, loc)
          self.emit(@opcode.OpCode::LoadLocal, temp64, loc)
        } else {
          self.emit(@opcode.OpCode::SplitD, 0, loc)
        }
      }
    } else if arg_ty.kind() is TK_LongLong {
      self.gen_expr(arg)
      if is_user_call {
        if is_variadic_callee {
          let temp64 = self.get_temp_slot_64()
          self.emit(@opcode.OpCode::StoreLocalQ, temp64, loc)
          self.emit(@opcode.OpCode::LoadLocal, temp64 + 4, loc)
          self.emit(@opcode.OpCode::LoadLocal, temp64, loc)
        } else {
          self.emit(@opcode.OpCode::SplitQ, 0, loc)
        }
      }
    } else {
      self.gen_expr(arg)
      // printf/fprintf 的 float 实参提升 double（可变参数默认实参提升）
      match callee {
        Identifier(name, _, _) =>
          if (name == "printf" || name == "fprintf") &&
            arg_ty.kind() is TK_Float {
            self.emit(@opcode.OpCode::CastF2D, 0, loc)
          }
        _ => ()
      }
    }
    i -= 1
  }
  match ret_temp_offset {
    Some(offset) => {
      self.emit(@opcode.OpCode::GetFrameBase, 0, loc)
      self.emit(@opcode.OpCode::PushConst, offset, loc)
      self.emit(@opcode.OpCode::Add, 0, loc)
    }
    None => ()
  }
  match callee {
    Identifier(name, _, _) => {
      match self.func_index.get(name) {
        Some(idx) => {
          match self.func_table.get(name) {
            Some(meta) =>
              if meta.is_variadic {
                let mut named_words = 0
                for w in meta.param_sizes {
                  named_words += w
                }
                let user_named_count = if meta.return_type.kind() is TK_Struct {
                  if meta.param_count - 1 > 0 {
                    meta.param_count - 1
                  } else {
                    0
                  }
                } else {
                  meta.param_count
                }
                let mut extra_variadic_words = 0
                for j in user_named_count..<args.length() {
                  extra_variadic_words += (self.type_size(args[j].ty()) + 3) / 4
                }
                let total_arg_words = named_words + extra_variadic_words
                self.emit(@opcode.OpCode::PushConst, total_arg_words, loc)
                self.emit(@opcode.OpCode::CallVar, idx, loc)
              } else {
                self.emit(@opcode.OpCode::Call, idx, loc)
              }
            None => self.emit(@opcode.OpCode::Call, idx, loc)
          }
          match ret_temp_offset {
            Some(offset) => {
              self.emit(@opcode.OpCode::GetFrameBase, 0, loc)
              self.emit(@opcode.OpCode::PushConst, offset, loc)
              self.emit(@opcode.OpCode::Add, 0, loc)
            }
            None => ()
          }
          return
        }
        None => ()
      }
      // Host 函数：直接 CallHost（bytecode libc 纯函数已在预注册段走
      // func_index，到不了这里）
      match @bytecode.host_func_id_by_user_name(name) {
        Some(host_id) => {
          self.emit(@opcode.OpCode::CallHost, host_id, loc)
          match ret_temp_offset {
            Some(offset) => {
              self.emit(@opcode.OpCode::GetFrameBase, 0, loc)
              self.emit(@opcode.OpCode::PushConst, offset, loc)
              self.emit(@opcode.OpCode::Add, 0, loc)
            }
            None => ()
          }
          return
        }
        None => ()
      }
    }
    _ => ()
  }
  // 函数指针间接调用：callee 求值压栈 + CallPtr
  self.gen_expr(callee)
  self.emit(@opcode.OpCode::CallPtr, args.length(), loc)
  match ret_temp_offset {
    Some(offset) => {
      self.emit(@opcode.OpCode::GetFrameBase, 0, loc)
      self.emit(@opcode.OpCode::PushConst, offset, loc)
      self.emit(@opcode.OpCode::Add, 0, loc)
    }
    None => ()
  }
}
