/* B10 #434 / M17b-A1：atoi 空白前缀全集——C11 §7.22.1.2 同 strtol 须跳
 * isspace 全集（\t\n\v\f\r+空格）；修前 Bytecode 段只认空格，其余全返 0
 * （真机三方一致：42 42 42 7 -9 13）。含饱和形态（UCRT 主判）。 */
#include <stdio.h>
#include <stdlib.h>
int main(){
  printf("%d %d %d %d %d %d\n",
    atoi(" 42"), atoi("\t42"), atoi("\n42"),
    atoi("\r\n+7"), atoi("\v-9"), atoi("\f13"));
  printf("sat %d %d %d %d\n",
    atoi("2147483648"), atoi("4294967296"), atoi("-2147483649"), atoi("-2147483648"));
  return 0;
}
