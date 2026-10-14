// @category: 审阅 2026-10-14 P1-c② 回归锚——enum 裸浮点初始化器双侧
// 编译失败等价（clang "integer constant expression" error；旧 vitro
// FloatLiteral 独立叶静默收 4.5→4——cast 形态 (int)4.0 合法路径见
// p2c_parser_lexer_batch.c 的 B = (int)4.0）。
enum E { A = 4.5 };
int main() { return A; }
