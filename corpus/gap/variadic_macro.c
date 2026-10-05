// @category: variadic_macro
#define LOG(fmt, ...) printf(fmt, __VA_ARGS__)\nint main() { LOG("%d", 42); return 0; }
