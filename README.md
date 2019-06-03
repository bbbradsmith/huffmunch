# huffmunch

A practical generic compression library for the NES or other 6502 platforms.

## Usage

### Compression

A command line tool is provided as a Windows binary: **huffmunch.exe**

It can be used to compress a single binary file,
 or it can operate on a list of files (or list of segments of a single file)
 so that several pieces of correlated data can be compressed together
 in a single package.

```
basic usage:
    huffmunch -B in.bin out.hfm
        Compress a single file.
    huffmunch -L in.lst out.hfm
        Compress a set of files together from a list file.
```

More detailed usage information can be found by running the utility with no arguments.

C++ source code for the command line utility is included, and is not platform specific.
 The compression library itself is separated, and could be integrated into other tools.

* **main.cpp** - command line utility
* **huffmunch.cpp** - compression library
* **huffmunch.h** - compression library public interface

A Visual Studio 2017 _.sln_ is included to build the Windows version.
 A simple _makefile_ is included to build with GCC.

### Decompression

The decompression library is provided as 6502 assembly in ca65 ([cc65](https://cc65.github.io/)) syntax.

1. Allocate 9 bytes of RAM and .export as **huffmunch_zpblock**.
2. Fill the first 2 bytes of _huffmunch_zpblock_ with the address of the binary output of the compressor tool.
3. Set Y:X equal to the index of the data you want to decompress from the binary.
4. Call **huffmunch_load** to prepare to begin decompressing the stream.
5. The length of the data will be returned from _huffmunch_load_ in Y:X.
6. The total number of data blocks will also be returned in the first 2 bytes of _huffmunch_zpblock_.
7. Call **huffmunch_read** once to reach each byte of uncompressed data.
8. Once the data has been read out, the bytes of _huffmunch_zpblock_ are not needed and can be freely used until another data block is needed.

There are two versions of the decompression library:

* **huffmunch.s** - standard version
* **huffmunch_canonical.s** - canonical version (much slower, slightly better compression)

See the **danger** folder for an example NES project.

## Method

Huffmunch is directly inspired by the
 [DEFLATE](https://en.wikipedia.org/wiki/DEFLATE)
 algorithm widely known for its use in the ZIP file format,
 but with an interest in making something suitable for the NES.

Goals:
* Provides serial decompression of a stream of data, one byte at a time.
* Uses an extremely small amount of RAM.
* Takes advantage of random access to ROM for the compressed data.
* Has reasonable performance on the low-powered 6502 CPU.

At a high level, DEFLATE uses two major compression techniques in tandem:
* An [LZ algorithm](https://en.wikipedia.org/wiki/LZ77_and_LZ78)
  builds a dictionary of commonly repeated substrings of symbols as the data is decompressed,
  and allows further repetitions of these dictionary entries to be replaced by a much smaller reference symbol.
* A [Huffman tree](https://en.wikipedia.org/wiki/Huffman_coding)
  uses distribution of symbol frequency to find an optimal way to store
  the stream of symbols and references.

The main problem with LZ techniques here is that they require the decompressor
 to build up a dictionary out of the decompressed data, meaning it the decompressed
 data has to be stored in RAM so that it can be accessed.

Huffmunch takes a similar approach:
* A Huffman tree is used to encode symbols optimally according to frequency.
* Each symbol may represent a single byte, or a longer string.
* A symbol may additionally reference another symbol as a suffix.

Here the dictionary is stored directly in the Huffman tree structure,
 and the suffix ability allows longer symbols to combine their data with shorter ones
 for some added efficiency. Because the tree structure explicitly contains
 all the symbols to be decoded, it can reside in ROM, and only a trivial amount of RAM
 is needed to traverse the tree.

The compression algorithm itself is currently a fairly naïve
 [hill climbing](https://en.wikipedia.org/wiki/Hill_climbing) method:
1. Assign every byte in the stream a symbol in the huffman tree/dictionary.
2. Look for any short substrings that are repeated and prioritize them by frequency/length.
3. Try replacing the best repeating substring with a new symbol, and add it to the dictionary.
4. If the resulting compressed data (tree + bitstream) is smaller, keep the new symbol and return to 2.
5. Otherwise try the next most likely substring, until one that successfully shrinks
   the data is found (return to 2), or after enough attempts end the search.

Longer repeated strings will gradually be built up from shorter ones that can combine.
 Eventually the tree will grow large enough that adding a new symbol requires more
 tree data than can be saved by that symbol's repetition; at that point compression will cease.

There may be more optimal ways to do this, but this was relatively simple to implement,
 and seems to perform well enough on data sets that are a reasonable size for the NES.
 I'm open to suggestions for improvement here.

## Performance

The performance of this compression method is measured here on the
 data used for the Dangerous Game example. The average decompression
 speed is fairly consistent, but there is a lot of variation in the
 time it takes to read each individual byte, as substrings that are
 either more common or longer will spend less time traversing the
 huffman tree structure that compresses the data.

| Method       | Average Speed    | Code Size | RAM Required  | Compressed Data Size |
| ------------ | ---------------- | --------- | ------------- | -------------------- |
| Uncompressed |   26 cycles/byte |  10 bytes |      2 bytes  | 45418 bytes (100.0%) |
| Standard     |  260 cycles/byte | 330 bytes |      9 bytes  | 21520 bytes (47.69%) |
| Canonical    | 1000 cycles/byte | 578 bytes |     24 bytes  | 20751 bytes (45.99%) |

The compressed size performance will also vary a lot depending on
 the type of data used. Plain text seems to regularly do better
 than 50%. True random data may reverse-compress to slightly larger than 100%.
 Typically huffmunch does not do as well as the DEFLATE algorithm
 which inspired it, but does at least reach the same ballpark.

The canonical variation of the technique represents the compression tree structure in a
 [more compact way](https://en.wikipedia.org/wiki/Canonical_Huffman_code),
 but takes much longer to decode (and more RAM).

## Other Reference

Compression of NES CHR graphics tiles is adequate, though I would
 recommend the [donut CHR compressor](https://github.com/jroatch/donut-nes)
 by [jroatch](https://github.com/jroatch) which is slightly more effective
 for that specific purpose.

Another useful reference is bregalad's
 [Compress Tools](https://www.romhacking.net/utilities/882/)
 which demonstrate several NES-viable compression methods.

## License

This library may be used, reused, and modified for any purpose, commercial or non-commercial.
 If distributing source code, do not remove the attribution to its original author,
 and document any modifications with attribution to their new author as well.

Attribution in released binaries or documentation is appreciated but not required.

If you'd like to support this project or its author, please visit:
 [Patreon](https://www.patreon.com/rainwarrior)
