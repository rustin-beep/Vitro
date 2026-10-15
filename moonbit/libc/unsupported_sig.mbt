///|
/// 标准库「已知不支持」签名表（#96，2026-10-15）——与 bytecode_libc_sig
/// 的分工：那张表是**放行**（引擎已实现，typeck 按签名检查后放行到
/// codegen 预注册），本表是**显式拒绝**（引擎确定不实现，诊断须告知
/// 读者「加原型没用」而非「未定义函数」的无效建议）。
///
/// 收录口径 = 标准库支持矩阵 §5.5 排除项中**签名可表达**的函数（div 族
/// 返回 struct div_t、setjmp 需 jmp_buf 数组类型——类型面表达不了，
/// 留 #10 拍板后处置）。函数若日后实现（进 host 路由或 bytecode 表），
/// check_user_func 第四级在查本表之前已被上游命中，表内残留条目自然
/// 失效（dead entry 无害，删除时机随实现批）。
///
/// 签名按 C 标准（C11 各节标注）——返回**真实类型**而非 int 兜底：
/// E3073 之后的表达式类型链正常走（#8 单错口径延伸——int 兜底会让
/// char* 接收位级联 E3054、三目分支级联 E3004，全是与真因无关的假阳性）。

///|
/// 返回「已知不支持」的标准库函数签名 (return_type, param_types)；
/// 未收录名 None（调用方回落 E3036 未定义路径）。
pub fn unsupported_libc_sig(name : String) -> (@ast.Type, Array[@ast.Type])? {
  match name {
    // getenv：char *(const char *)——C11 7.22.4.6（沙盒无环境面）
    "getenv" => Some((c_ptr(), [Pointer(Char(false, true), false)]))
    // system：int (const char *)——C11 7.22.4.8（沙盒禁系统命令）
    "system" => Some((i_ty(), [Pointer(Char(false, true), false)]))
    // strtok：char *(char *, const char *)——C11 7.24.5.8（需全局静态
    // 状态，教学价值有限——支持矩阵 §5.6 注记）
    "strtok" => Some((c_ptr(), [c_ptr(), Pointer(Char(false, true), false)]))
    // atexit：int (void (*)(void))——C11 7.22.4.2（退出处理教学不用）
    "atexit" =>
      Some((i_ty(), [Pointer(Function(Void(false), [], false, false), false)]))
    // frexp：double (double, int *)——C11 7.12.6.4（数值分析专用）
    "frexp" => Some((@ast.Type::double(), [@ast.Type::double(), i_ptr()]))
    // ldexp：double (double, int)——C11 7.12.6.6
    "ldexp" => Some((@ast.Type::double(), [@ast.Type::double(), i_ty()]))
    // modf：double (double, double *)——C11 7.12.6.9
    "modf" =>
      Some(
        (
          @ast.Type::double(),
          [@ast.Type::double(), Pointer(Double(false), false)],
        ),
      )
    // scalbn：double (double, int)——C11 7.12.6.13
    "scalbn" => Some((@ast.Type::double(), [@ast.Type::double(), i_ty()]))
    _ => None
  }
}
