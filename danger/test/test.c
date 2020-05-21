/* Unit test for huffmunch, using dangerous game as source. */

#include <stdio.h>
#include "../../huffmunch_c.h"

extern char story[]; // from test.s

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

	block_count = huffmunch_init(story);
	printf("%u blocks to compare against: " STORY_FILE "\n", block_count);

	for (block=0; block<block_count; ++block)
	{
		printf("Block %u...", block);
		block_length = huffmunch_load(block);
		for (b=0; b<block_length; ++b)
		{
			ca = huffmunch_read();
			cb = fgetc(f);
			if (cb == EOF)
			{
				printf(" failed with end of file at byte %u!\n", b);
				fclose(f);
				return 2;
			}
			if (ca != cb)
			{
				printf(" failed at byte %u! (read %02X != expected %02X)\n", b, ca, cb);
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
