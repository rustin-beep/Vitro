// @category: static_local
// static 局部聚合/数组/嵌套初值 + 取址通路（DIFF-CODEGEN-STATIC-ADDR-01
// 销案语料，批四 2026-10-07）：
// - gen_addr/gen_member_addr 的 static_local_indices 分支（旧缺——
//   `struct S s2 = s1` 报"未声明的变量"）
// - emit_static_init 聚合初值按成员偏移（旧平铺标量数组——`{1,2}` 第二
//   元素写飞：static5 旧返回 1 vs Clang 3）
// - 嵌套 struct / static int 数组 / static char 数组字符串 / 聚合拷贝
struct Inner { int x; int y; };
struct Outer { struct Inner in; int z; };
int main() {
    static struct Outer o = {{1, 2}, 3};
    static int arr[3] = {10, 20, 30};
    static char msg[4] = "hi";
    static struct Inner direct = {7, 8};
    struct Inner copy = o.in;
    int *p = &arr[1];
    int s = o.in.x + o.in.y + o.z + arr[2] + msg[1] + copy.y;
    return s + direct.x + direct.y + *p;
}
