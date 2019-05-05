#pragma once

// Huffmunch
// Brad Smith, 2019
// https://github.com/bbbradsmith/huffmunch

// CANONICAL format produces a slightly smaller dictionary tree structure
// but takes much, much longer to decode (not recommended)
#define HUFFMUNCH_CANONICAL 0

// huffmunch_compress return values
const int HUFFMUNCH_OK = 0;
const int HUFFMUNCH_OUTPUT_OVERFLOW = 1; // too much data for output buffer
const int HUFFMUNCH_VERIFY_FAIL = 2; // internal error: verify failed

// huffmunch_compress
//   data
//     data to be compressed
//   data_size
//     length of data to be compressed
//   output
//     buffer to be filled with compressed output
//     if NULL output_size will still be computed
//   output_size
//     in: size of buffer to be filled
//     out: number of bytes used for compressed output
//   splits
//     list of points to split the compressed data for access in split pieces
//     NULL implies a split_count of 0
//   split_count
//     number of entries in splits
extern int huffmunch_compress(
	const unsigned char* data,
	unsigned int data_size,
	unsigned char* output,
	unsigned int& output_size,
	const unsigned int *splits,
	unsigned int split_count);

// huffmunch_decompress
//   data
//     data to be uncompressed
//   data_size
//     length of data to be uncompressed
//   output
//     buffer to be filled with decompressed output
//   output_size
//     size of the decompressed output
//   splits
//     split list for the decompressed output
//     NULL implies a split count of 0
//   split_count
//     number of entries in splits
extern int huffmunch_decompress(
	const unsigned char* data,
	unsigned int data_size,
	unsigned char* output,
	unsigned int output_size,
	const unsigned int* splits,
	unsigned int split_count);

// huffmunch_debug diagnostic bitfield
const unsigned int HUFFMUNCH_DEBUG_OFF       = 0x00000000UL;
const unsigned int HUFFMUNCH_DEBUG_TREE      = 0x00000001UL;
const unsigned int HUFFMUNCH_DEBUG_MUNCH     = 0x00000002UL;
const unsigned int HUFFMUNCH_DEBUG_VERIFY    = 0x00000004UL;
const unsigned int HUFFMUNCH_DEBUG_FULL      = 0xFFFFFFFFUL;

// huffmunch_debug
//   debug_level
//     parameter for debug output
extern void huffmunch_debug(unsigned int debug_bits);

// end of file
