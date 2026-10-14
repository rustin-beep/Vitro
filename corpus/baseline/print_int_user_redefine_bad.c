/* #79 误收负例（双侧编译失败等价）：用户重定义 print_int(int\*) 后传
 * int 实参——clang/gcc error: incompatible integer to pointer conversion
 * passing 'int' to parameter of type 'int *'；vitro 旧零诊断静默放行
 * （内置签名 print_int(int) 恰好匹配），修复后 E3054 对齐。 */
void print_int(int *p) { (void)*p; }
int main(void) {
    int v = 42;
    print_int(v);
    return 0;
}
