// @category: baseline
// #223 红锚（2026-10-25）：纯原型声明（无定义体）被调用——Vitro 一体化
// 报 E3089「函数已声明但未定义」（旧 E0 无码兜底，本批立码——下游按码
// 查卡 / 挂 fix_suggestion）；clang 编译期放行声明（-c 语义合法）、全链
// 构建在链接期报 undefined reference。双侧构建失败判 match：vitro 拒在
// 编译期 / clang 拒在链接期，失败阶段差异为 #205（如实文案）与 #223
//（立码）登记在案的有意收严——一体化教学引擎不等链接期才告诉学生。
// 码级锚：gateway/issue223_e3089_wbtest（error_code/列/fix 三断言）+
// codegen_wbtest #205 锚的 code==3089 连坐。
int proto_only(int x);

int main(void) {
    return proto_only(1);
}
