// Huffmunch
// Brad Smith, 2019
// https://github.com/bbbradsmith/huffmunch

#define _CRT_SECURE_NO_WARNINGS
#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

const int VERSION_MAJOR = 1;
const int VERSION_MINOR = 2;

#include "huffmunch.h"

bool verbose = false;
bool canonical = false;
unsigned int header_width = 2;

int huffmunch_file(const char* file_in, const char* file_out)
{
	unsigned char* buffer_in = NULL;
	unsigned char* buffer_out = NULL;
	unsigned int size_in = 0;
	unsigned int size_out = 0;

	FILE* f = fopen(file_in, "rb");
	if (f == NULL)
	{
		printf("error: file %s not found\n", file_in);
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
		printf("error: out of memory\n");
		return -1;
	}
	fread(buffer_in,1,size_in,f);
	fclose(f);
	printf("%6d bytes read from %s\n", size_in, file_in);

	int result = huffmunch_compress(buffer_in, size_in, buffer_out, size_out, NULL, 0, canonical);
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

int huffmunch_list(const char* list_file, const char* out_file)
{
	using namespace std;

	struct Entry {
		int line_number;
		int start;
		int end;
		string path;
	};

	unsigned int bank_size;
	unsigned int bank_max;
	vector<Entry> entries;
	vector<unsigned char> data;
	vector<unsigned int> splits;

	// parse list file

	char line[1024];
	FILE *fl = fopen(list_file, "rt");
	if (fl == NULL)
	{
		printf("error: list file %s not found\n", list_file);
		return -1;
	}
	if (!fgets(line,sizeof(line),fl))
	{
		printf("error: empty list file\n");
		fclose(fl);
		return -1;
	}
	char* next;
	errno = 0;
	bank_max = strtoul(line, &next, 0);
	if (errno)
	{
		printf("error: unable to read bank count from list file line 1\n");
		fclose(fl);
		return -1;
	}
	errno = 0;
	bank_size = strtoul(next, &next, 0);
	if (errno)
	{
		printf("error: unable to read bank size from list file line 1\n");
		fclose(fl);
		return -1;
	}
	int line_number = 1;
	while (fgets(line,sizeof(line),fl))
	{
		++line_number;

		// trim trailing whitespace (includes newline)
		int i = strlen(line) - 1;
		while (i > 0 && isspace(line[i]))
		{
			line[i] = 0;
			--i;
		}
		if (line[0] == 0) continue; // blank lines skipped

		errno = 0;
		int start = strtol(line, &next, 0);
		if (errno)
		{
			printf("error: unable to read start position on list file line %d\n",line_number);
			fclose(fl);
			return -1;
		}

		errno = 0;
		int end = strtol(next, &next, 0);
		if (errno)
		{
			printf("error: unable to read end position on list file line %d\n",line_number);
			fclose(fl);
			return -1;
		}

		while (isspace(*next)) ++next; // trim leading whitespace

		Entry e;
		e.line_number = line_number;
		e.start = start;
		e.end = end;
		e.path = string(next);
		entries.push_back(e);
	}
	fclose(fl);
	printf("%d entries read from %s\n", entries.size(), list_file);
	printf("bank size: %d\n", bank_size);
	if (bank_max < 1) bank_max = 1<<16; // "unlimited"

	// collect data

	for (unsigned int i=0; i<entries.size(); ++i)
	{
		const Entry& e = entries[i];

		splits.push_back(data.size());

		const char* path = e.path.c_str();
		FILE* fb = fopen(path, "rb");
		if (fb == NULL)
		{
			printf("error: source file %s not found\n",path);
			return -1;
		}
		fseek(fb,0,SEEK_END);
		long fb_size = ftell(fb);

		int start = (e.start < 0) ? 0 : e.start;
		int end = (e.end < 0) ? fb_size : e.end;
		if (start < 0 || end > fb_size)
		{
			printf("error: source start and end (%d, %d) out of range for file %s\n",e.start,e.end,path);
			fclose(fb);
			return -1;
		}
		fseek(fb,e.start,SEEK_SET);
		for (int i=start; i<end; ++i) data.push_back(fgetc(fb));
		fclose(fb);

		unsigned int entry_size = end - start;
		if (end < start) entry_size = 0;
		if(verbose) printf("%4d: %5d bytes read from %s (%d,%d)\n", i, entry_size, path, e.start, e.end);
	}
	printf("%d bytes read from %d source entries\n", data.size(), entries.size());
	assert(entries.size() == splits.size());

	// compress and output banks

	// This will compress many times, adding one source entry to the bank each time,
	// until the bank overflows and it begins a new one. Could do this faster with
	// a more intelligent search (e.g. starting estimate at ~60% of input size and
	// binary search for a split-point from there), but this linear search was simple
	// to implement.

	const char* out_ext = strrchr(out_file, '.');
	if (out_ext == NULL) out_ext = out_file + strlen(out_file);
	string out_prefix = string(out_file, out_ext-out_file);

	vector<unsigned char> bank;
	vector<unsigned int> bank_splits;
	vector<string> bank_stat;
	bank.resize(bank_size);
	unsigned int bank_split_index = 0;

	unsigned int total_used = 0;
	unsigned int total_unused = 0;
	unsigned int last_used = 0;
	unsigned int last_unused = 0;

	strcpy(line,"no bank generated\n");

	for (unsigned int i=0; i<entries.size(); ++i)
	{
		const Entry& e = entries[i];
		unsigned int current_bank = bank_splits.size();

		if (bank_max == 1) i = entries.size() - 1; // accelerate single bank

		unsigned int data_start = splits[bank_split_index];
		unsigned int data_end = data.size();
		if ((i+1) < entries.size()) data_end = splits[i+1];

		vector<unsigned int> temp_splits;
		for (unsigned int j=bank_split_index; j<=i; ++j)
		{
			temp_splits.push_back(splits[j] - data_start);
		}

		unsigned int result_size = bank_size;

		int result = huffmunch_compress(
			data.data()+data_start,data_end-data_start,
			bank.data(),result_size,
			temp_splits.data(),temp_splits.size(),
			canonical);

		if (result == HUFFMUNCH_OUTPUT_OVERFLOW) // start a new bank if it doesn't fit
		{
			if (!verbose) printf(line);

			total_used += last_used;
			total_unused += last_unused;

			++current_bank;
			bank_split_index = i;
			bank_splits.push_back(i);
			data_start = splits[bank_split_index];

			if (current_bank >= bank_max)
			{
				printf("error: out of available banks\n");
				return -1;
			}

			result = huffmunch_compress(
				data.data()+data_start,data_end-data_start,
				bank.data(),result_size,
				NULL,1,
				canonical);
		}

		if (result != HUFFMUNCH_OK)
		{
			printf("error: compression error %d: %s\n", result, huffmunch_error_description(result));
			return result;
		}

		char bank_file[1024];
		if (snprintf(bank_file, sizeof(bank_file)-1, "%s%04d%s", out_prefix.c_str(), current_bank, out_ext) < 0)
		{
			printf("internal error: unable to create bank filename\n");
			return -1;
		}

		FILE *fb = fopen(bank_file, "wb");
		if (fb == NULL)
		{
			printf("error: unable to open bank output file %s\n",bank_file);
			return -1;
		}
		fwrite(bank.data(),1,result_size,fb);
		fclose(fb);

		snprintf(line, sizeof(line), "%s: %d - %d (%d bytes)\n", bank_file, bank_split_index, i, result_size);
		if (verbose) printf(line);

		last_used = result_size;
		last_unused = bank_size - result_size;
	}
	if (!verbose) printf(line);
	total_used += last_used;
	total_unused += last_unused;
	bank_splits.push_back(entries.size());
	printf("%d banks output\n", bank_splits.size());

	// output bank split table

	FILE *fo = fopen(out_file, "wb");
	if (fo == NULL)
	{
		printf("error: unable to open bank table output file %s\n",out_file);
		return -1;
	}
	for (unsigned int v: bank_splits)
	{
		for (unsigned int i=0; i<header_width; ++i)
		{
			fputc(v & 0xFF,fo);
			v >>= 8;
		}
		if (v != 0)
		{
			printf("error: entry count exceeds representable size by header width.\n");
			fclose(fo);
			return -1;
		}
	}
	fclose(fo);
	printf("bank end table written to %s\n", out_file);

	unsigned int total_size = total_used + total_unused;
	printf("%7d bytes input\n", data.size());
	printf("%7d bytes output   %6.2f%%\n", total_used, (100.0 * total_used) / data.size());
	printf("%7d bytes in banks %6.2f%% (%d unused in %d banks)\n", total_size, (100.0 * total_size) / data.size(), total_unused, bank_splits.size());

	return 0;
}

int print_usage()
{
	printf(
		"usage:\n"
		"    huffmunch -B in.bin out.hfm\n"
		"        Compress a single file.\n"
		"    huffmunch -L in.lst out.hfm\n"
		"        Compress a set of files together from a list file.\n"
		"\n"
		"optional arguments:\n"
		"    -C\n"
		"        Canonical tree format, slightly smaller, much slower to decompress.\n"
		"    -V\n"
		"        Verbose output.\n"
		"    -S (width)\n"
		"        Wider search is slower, but marginally increases compression, default 3 (range: 2-16).\n"
		"    -X (cutoff)\n"
		"        Number of missed attempts before halting compression, default 100, 0 unlimited.\n"
		"    -H (width)\n"
		"        Bytes per integer entry in output header, default 2.\n"
		"    -T (depth)\n"
		"        Maximum allowed depth of canonical tree, default 24.\n"
		#if HUFFMUNCH_DEBUG
		"    -D[T/B]\n"
		"        Debug output. (-DT text, -DB binary, -D auto)\n"
		#endif
		"\n");
	printf(
		"List files are a simple text format:\n"
		"    Line 1: (banks) (size)\n"
		"        banks (int) - maximum number of banks to split output into\n"
		"                      use 0 for unlimited banks\n"
		"                      use 1 if multiple banks are not needed (faster)\n"
		"        size (int) - how many bytes allowed in each bank\n"
		"    Lines 2+: (start) (end) (file)\n"
		"        start (int) - first byte to read from file\n"
		"        end (int) - last byte to read from file + 1\n"
		"                    use -1 to read the whole file\n"
		"        file - name of file extends to end of line\n"
		"    The input sources will be compressed together and packed into banks.\n"
		"    Integers can be decimal, hexadecimal (0x prefix), or octal (0 prefix).\n"
		"    Example output:\n"
		"        out.hfm - a table of %d-byte integers giving the end index of each bank\n"
		"        out0000.hfm - the first bank\n"
		"        out0001.hfm - the second bank\n"
		"\n", header_width);
	printf("huffmunch version %d.%d\n",
		VERSION_MAJOR, VERSION_MINOR);
	return -1;
}

int main(int argc, const char** argv)
{
	const char* outfile = NULL;
	const char* infile = NULL;
	int mode = -1;
	const int MODE_BIN = 0;
	const int MODE_LIST = 1;

	huffmunch_configure(HUFFMUNCH_HEADER_WIDTH, header_width); // just to ensure it matches print_usage()

	bool valid_args = true;
	for (int i=1; i<argc; ++i)
	{
		const char* arg = argv[i];
		if (arg[0] == '-')
		{
			switch (arg[1])
			{
			case 'c':
			case 'C':
				if (strlen(arg) > 2) valid_args = false;
				canonical = true;
				break;
			case 'v':
			case 'V':
				if (strlen(arg) > 2) valid_args = false;
				verbose   = true;
				break;
			case 'd':
			case 'D':
				huffmunch_debug(HUFFMUNCH_DEBUG_FULL);
				switch (arg[2])
				{
				case 't':
				case 'T':
					huffmunch_debug(HUFFMUNCH_DEBUG_FULL,1);
					break;
				case 'b':
				case 'B':
					huffmunch_debug(HUFFMUNCH_DEBUG_FULL,0);
					break;
				case 0:
					break;
				default:
					valid_args = false;
					break;
				}
				break;
			case 'b':
			case 'B':
				if (strlen(arg) > 2) valid_args = false;
				if ((i+1) >= argc) { valid_args = false; break; }
				mode = MODE_BIN;
				infile = argv[i+1]; ++i;
				break;
			case 'l':
			case 'L':
				if (strlen(arg) > 2) valid_args = false;
				if ((i+1) >= argc) { valid_args = false; break; }
				mode = MODE_LIST;
				infile = argv[i+1]; ++i;
				break;
			case 's':
			case 'S':
				if (strlen(arg) > 2) valid_args = false;
				if ((i+1) >= argc) { valid_args = false; break; }
				huffmunch_configure(HUFFMUNCH_SEARCH_WIDTH, strtoul(argv[i+1],NULL,0)); ++i;
				break;
			case 'x':
			case 'X':
				if (strlen(arg) > 2) valid_args = false;
				if ((i+1) >= argc) { valid_args = false; break; }
				huffmunch_configure(HUFFMUNCH_SEARCH_CUTOFF, strtoul(argv[i+1],NULL,0)); ++i;
				break;
			case 'h':
			case 'H':
				if (strlen(arg) > 2) valid_args = false;
				if ((i+1) >= argc) { valid_args = false; break; }
				huffmunch_configure(HUFFMUNCH_HEADER_WIDTH, strtoul(argv[i+1],NULL,0)); ++i;
				break;
			case 't':
			case 'T':
				if (strlen(arg) > 2) valid_args = false;
				if ((i+1) >= argc) { valid_args = false; break; }
				huffmunch_configure(HUFFMUNCH_CANONICAL_DEPTH, strtoul(argv[i+1],NULL,0)); ++i;
				break;
			default:
				valid_args = false;
				break;
			}
			if (!valid_args) break;
		}
		else
		{
			if (outfile == NULL) 
			{
				outfile = arg;
			}
			else
			{
				valid_args = false;
				break;
			}
		}
	}
	if (!valid_args || infile == NULL || outfile == NULL)
	{
		return print_usage();
	}

	if (mode == MODE_BIN)
	{
		return huffmunch_file(infile,outfile);
	}
	else if (mode == MODE_LIST)
	{
		return huffmunch_list(infile,outfile);
	}

	return print_usage();
}

// end of file
