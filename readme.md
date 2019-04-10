LAB05
===

See [Lecture 05](http://www.nc.es.ncku.edu.tw/course/embedded/05) for more details.

HW05
===

### 實驗題目
將在 main 中的程式於 SRAM 中執行並驗證.
### 實驗步驟
1. 將 .text 搬至 SRAM 中

`stm32f4.ld`
```ASSEMBLY
MEMORY
{
	FLASH (rx) : ORIGIN = 0x00000000, LENGTH = 1M
	SRAM (rwx) : ORIGIN = 0x20000000, LENGTH = 128K
}

SECTIONS
{
	.mytext :
	{
		KEEP(*(.vector_table))
		_mytext_lma_start = .; /* LMA is equivalent to VMA in this section */
	} > FLASH

	.my_main_text : AT(_mytext_lma_start) /* tell linker whrere (LMA) this section should be put at */
	{
		_mytext_vma_start = .;
		*(.text)
		*(.rodata)
		_mytext_vma_end = .;
	} > SRAM

	.mydata :
	{
		_mydata_vma_start = .;
		*(.data)
		_mydata_vma_end = .;
	} > SRAM

	.mybss :
	{
		_mybss_vma_start = .;
		*(.bss)
		*(COMMON)
		_mybss_vma_end = .;
	} > SRAM

	_msp_init = ORIGIN(SRAM) + LENGTH(SRAM);
}
```
`startup.c`
```c
#include <stdint.h>

extern int main(void);

void reset_handler(void)
{
	//symbols defined in linker script
	extern uint32_t _mytext_lma_start;
	extern uint32_t _mytext_vma_start;
	extern uint32_t _mytext_vma_end;
	extern uint32_t _mydata_vma_start;
	extern uint32_t _mydata_vma_end;
	extern uint32_t _mybss_vma_start;
	extern uint32_t _mybss_vma_end;
	//note that for the variables above, "symbol value" is equivalent to the address we want
	//use "&" operator to get symbol values

	uint32_t *mytext_lstart_ptr = &_mytext_lma_start;
	uint32_t *mytext_vstart_ptr = &_mytext_vma_start;
	uint32_t *mytext_vend_ptr = &_mytext_vma_end;

	uint32_t *mydata_vstart_ptr = &_mydata_vma_start;
	uint32_t *mydata_vend_ptr = &_mydata_vma_end;

	uint32_t *mybss_vstart_ptr = &_mybss_vma_start;
	uint32_t *mybss_vend_ptr = &_mybss_vma_end;

	uint32_t *src_ptr, *dst_ptr;

	src_ptr = mytext_lstart_ptr;
	dst_ptr = mytext_vstart_ptr;

	while (dst_ptr < mytext_vend_ptr)
		*dst_ptr++ = *src_ptr++;

	dst_ptr = mydata_vstart_ptr;

	while (dst_ptr < mydata_vend_ptr)
		*dst_ptr++ = *src_ptr++;

	dst_ptr = mybss_vstart_ptr;

	while (dst_ptr < mybss_vend_ptr)
		*dst_ptr++ = 0;

	main();
}
```
`make clean` -> `make` -> `make flash`
燒錄進去後 stm32 毫無反應 why??

2. `objdump` 觀察
`arm-none-eabi-objdump -D -h blink.elf`
發現 my_main_text 的 VMA 確實在 SRAM 中
```ASSEMBLY
Sections:

Idx Name          Size      VMA       LMA       File off  Algn
  0 .mytext       00000008  00000000  00000000  000102a0  2**0
                  CONTENTS, READONLY
  1 .comment      00000031  00000000  00000000  000102a8  2**0
                  CONTENTS, READONLY
  2 .ARM.attributes 00000031  00000000  00000000  000102d9  2**0
                  CONTENTS, READONLY
  3 .my_main_text 00000294  20000000  00000008  00010000  2**2
                  CONTENTS, ALLOC, LOAD, READONLY, CODE
  4 .mydata       0000000c  20000294  0000029c  00010294  2**2
                  CONTENTS, ALLOC, LOAD, DATA
  5 .mybss        00000028  200002a0  000002a8  000102a0  2**2
                  ALLOC
```
觀察指令執行順序，`sp` 為 `0x20020000`， `pc` 為 `0x200001f1`
```
Disassembly of section .mytext:

00000000 <_mytext_lma_start-0x8>:
   0:   20020000        andcs   r0, r2, r0
   4:   200001f1        strdcs  r0, [r0], -r1
```
`0x200001f1` 是 `reset_handler`
```
200001f0 <reset_handler>:
200001f0:       b580            push    {r7, lr}
200001f2:       b08a            sub     sp, #40 ; 0x28
200001f4:       af00            add     r7, sp, #0
200001f6:       4b20            ldr     r3, [pc, #128]  ; (20000278 <reset_handler+0

x88>)
200001f8:       61fb            str     r3, [r7, #28]
200001fa:       4b20            ldr     r3, [pc, #128]  ; (2000027c <reset_handler+0
x8c>)
200001fc:       61bb            str     r3, [r7, #24]
200001fe:       4b20            ldr     r3, [pc, #128]  ; (20000280 <reset_handler+0
x90>)
```
`objdump` 出來結果看似正常，但回顧一下 LAB 內容，燒錄時將資料燒入至 Flash 中，`reset_handler` 中負責把 `.text`、`.data`、`.bss` 從 Flash 搬移至 SRAM 中，但上述程式卻是在 SRAM 中執行 `reset_handler`，此時尚未執行過 `reset_handler` ，SRAM 中應是 Unpredictable。
以 qemu 模擬觀察如下:
指令在 SRAM 中的確都是亂碼
![](https://github.com/vwxyzjimmy/ESEmbedded_LAB05/blob/master/2_global_var_text/picture/gdb.JPG)

3. 由上述可知，`reset_handler`，必須在 Flash 中執行，將其餘部分的如 main.c 、blink.c 的 `.text` 搬移至 SRAM 後才能夠在 SRAM 中執行程式。
因此分離 .text 中 startup.c 的部分至於 Flash 並且將其餘 .text 至於 SRAM 中。
使用 \_\_attribute__(section) ，用來修飾函數時，可以把代碼放在不同段，
如: \_\_attribute__((section(“new_section”))) void f(void);
函數 f(void) 將被放到 new_section 段中，而不是 .text 中。
    * 參考資料

    [linux2.6.11（內核基礎知識，更新中](https://blog.xuite.net/tzeng015/twblog/113272142-linux2.6.11%EF%BC%88%E5%85%A7%E6%A0%B8%E5%9F%BA%E7%A4%8E%E7%9F%A5%E8%AD%98%EF%BC%8C%E6%9B%B4%E6%96%B0%E4%B8%AD%EF%BC%89)

    [GNU C \_\_attribute__ 機制簡介](http://huenlil.pixnet.net/blog/post/26078382)

在 `startup.c` 中加入 \_\_attribute__ ，將 `startup.c` 的 `.text` 指定至 `.startuptext` section 中如下。
`startup.c`
```C
__attribute__ ((__section__ (".startuptext"))) void reset_handler(void)
{
...
```
並修改 `stm32f4.ld` 固定 `.startuptext` section 於 Flash 中。
`stm32f4.ld`
```ASSEMBLY
MEMORY
{
	FLASH (rx) : ORIGIN = 0x00000000, LENGTH = 1M
	SRAM (rwx) : ORIGIN = 0x20000000, LENGTH = 128K
}

SECTIONS
{
	.mytext :
	{
		KEEP(*(.vector_table))
		KEEP(*(.startuptext))
		_mytext_lma_start = .; /* LMA is equivalent to VMA in this section */
	} > FLASH

	.my_main_text : AT(_mytext_lma_start) /* tell linker whrere (LMA) this section should be put at */
	{
		_mytext_vma_start = .;
		*(.text)
		*(.rodata)
		_mytext_vma_end = .;
	} > SRAM

	.mydata :
	{
		_mydata_vma_start = .;
		*(.data)
		_mydata_vma_end = .;
	} > SRAM

	.mybss :
	{
		_mybss_vma_start = .;
		*(.bss)
		*(COMMON)
		_mybss_vma_end = .;
	} > SRAM

	_msp_init = ORIGIN(SRAM) + LENGTH(SRAM);
}
```
4. 驗證
`make clean` -> `make` -> `make flash`，LED 正常運作
以 objdump 觀察 `reset_handler` 於 Flash 中執行。
```
00000008 <reset_handler>:

   8:   b580            push    {r7, lr}
   a:   b08a            sub     sp, #40 ; 0x28
   c:   af00            add     r7, sp, #0
   e:   4b20            ldr     r3, [pc, #128]  ; (90 <reset_handler+0x88>)
  10:   61fb            str     r3, [r7, #28]
  12:   4b20            ldr     r3, [pc, #128]  ; (94 <reset_handler+0x8c>)
  14:   61bb            str     r3, [r7, #24]
  16:   4b20            ldr     r3, [pc, #128]  ; (98 <reset_handler+0x90>)
  18:   617b            str     r3, [r7, #20]
  1a:   4b20            ldr     r3, [pc, #128]  ; (9c <reset_handler+0x94>)
  1c:   613b            str     r3, [r7, #16]
  1e:   4b20            ldr     r3, [pc, #128]  ; (a0 <reset_handler+0x98>)
  20:   60fb            str     r3, [r7, #12]
  22:   4b20            ldr     r3, [pc, #128]  ; (a4 <reset_handler+0x9c>)
    .
    .
    .
```
除了 `reset_handler` 以外，如`main` 、`blink` 皆於 SRAM 中執行。
```
20000000 <main>:
20000000:       b580            push    {r7, lr}
20000002:       af00            add     r7, sp, #0
20000004:       210a            movs    r1, #10
20000006:       200c            movs    r0, #12
20000008:       f000 f8b4       bl      20000174 <blink_count>
2000000c:       210a            movs    r1, #10
2000000e:       200d            movs    r0, #13
    .
    .
    .
```
```
200000f8 <blink>:
200000f8:       b580            push    {r7, lr}
200000fa:       b082            sub     sp, #8
200000fc:       af00            add     r7, sp, #0
200000fe:       6078            str     r0, [r7, #4]
20000100:       6878            ldr     r0, [r7, #4]
20000102:       f7ff ff91       bl      20000028 <led_init>
    .
    .
    .
```
