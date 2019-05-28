/* Unit test for huffmunch, using dangerous game as source. */

#include <stdio.h>

extern unsigned int fastcall test_init(void);
extern unsigned int fastcall test_begin_block(unsigned int index);
extern unsigned int fastcall test_read_byte(void);

#define STORY_FILE "../output/danger.bin"

int main()
{
	static FILE* f;
	static unsigned int block_count;
	static unsigned int block_length;
	static unsigned int block;
	static unsigned int b;
	static unsigned int ca;
	static unsigned int cb;

	f = fopen(STORY_FILE,"rb");
	if (f == NULL)
	{
		printf("Unable to open: " STORY_FILE "\n");
		return 1;
	}

	block_count = test_init();
	printf("%u blocks to compare against: " STORY_FILE "\n", block_count);

	for (block=0; block<block_count; ++block)
	{
		printf("Block %u...", block);
		block_length = test_begin_block(block);
		for (b=0; b<block_length; ++b)
		{
			ca = test_read_byte();
			cb = fgetc(f);
			if (cb == EOF)
			{
				printf(" failed with end of file at byte %u!\n", b);
				fclose(f);
				return 2;
			}
			if (ca != cb)
			{
				printf(" failed at byte %u! (%02X != %02X)\n", b, ca, cb);
				fclose(f);
				return 3;
			}
		}
		printf(" verified %d bytes.\n",block_length);
	}
	if (fgetc(f) != EOF)
	{
		printf("There is remaining data in the comparison file!\n");
		return 4;
	}

	printf("Success!\n");
	fclose(f);
	return 0;
}
