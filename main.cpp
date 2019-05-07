// Huffmunch
// Brad Smith, 2019
// https://github.com/bbbradsmith/huffmunch

#define _CRT_SECURE_NO_WARNINGS
#include <cstdio>
#include <cstdlib>

#include "huffmunch.h"

int huffmunch_file(const char* file_in, const char* file_out)
{
	unsigned char* buffer_in = NULL;
	unsigned char* buffer_out = NULL;
	unsigned int size_in = 0;
	unsigned int size_out = 0;

	FILE* f = fopen(file_in, "rb");
	if (f == NULL)
	{
		printf("error: file %s not found.\n", file_in);
		return -1;
	}
	fseek(f,0,SEEK_END);
	size_in = ftell(f);
	size_out = size_in + 1024;
	fseek(f,0,SEEK_SET);

	buffer_in = (unsigned char*)malloc((size_in * 2) + 1024);
	buffer_out = buffer_in + size_in;

	if (buffer_in == NULL)
	{
		fclose(f);
		printf("error: out of memory.\n");
		return -1;
	}
	fread(buffer_in,1,size_in,f);
	fclose(f);
	printf("%6d bytes read from %s\n", size_in, file_in);

	int result = huffmunch_compress(buffer_in, size_in, buffer_out, size_out, NULL, 0);
	if (result != HUFFMUNCH_OK)
	{
		printf("error: compression error %d: %s\n", result, huffmunch_error_description(result));
		return result;
	}
	printf("%6d bytes compressed: %6.2f%%\n", size_out, (100.0 * size_out)/size_in);

	f = fopen(file_out, "wb");
	if (f == NULL)
	{
		free(buffer_in);
		printf("error: unable to open output file %s\n", file_out);
		return -1;
	}
	fwrite(buffer_out,1,size_out,f);
	fclose(f);
	printf("%6d bytes written to %s\n", size_out, file_out);
	free(buffer_in);

	return 0;
}

int main(int argc, char** argv)
{
	//huffmunch_debug(HUFFMUNCH_DEBUG_FULL);
	huffmunch_debug(HUFFMUNCH_DEBUG_MUNCH);

	#if HUFFMUNCH_CANONICAL
		#define TS ".hfc"
	#else
		#define TS ".hfm"
	#endif

	huffmunch_file("test/test0.bin", "test/test0" TS);
	huffmunch_file("test/test1.bin", "test/test1" TS);
	huffmunch_file("test/test2.bin", "test/test2" TS);
	huffmunch_file("test/Super Mario Bros. (JU) (PRG0) [!].chr", "test/Super Mario Bros. (JU) (PRG0) [!]" TS);
	huffmunch_file("test/count.htm", "test/count" TS);
	huffmunch_file("test/rando.bin", "test/rando" TS);
	huffmunch_file("test/lizard.chr", "test/lizard" TS);
	huffmunch_file("test/kinglear.txt", "test/kinglear" TS);

	return 0;
}

// end of file
