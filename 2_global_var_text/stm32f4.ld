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
