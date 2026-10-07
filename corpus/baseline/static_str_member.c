// static 局部聚合的字符串指针成员初值（批五 ①表 9 号① 销案锚——首行结构同源：
// 初值走 pending_string_inits 通道在 Pass 3 执行时无人消费 → 成员 NULL →
// 解引用 TRAP；修 = Pass 3 尾再回填一次）。预期：stdout = "abc 7"，退出码 7。
struct S { const char* s; int n; };

int main() {
  static struct S t = {"abc", 7};
  printf("%s %d\n", t.s, t.n);
  return t.n;
}
