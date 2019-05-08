// Huffmunch
// Brad Smith, 2019
// https://github.com/bbbradsmith/huffmunch

#include <cassert>
#include <cstdint>
#include <algorithm>
#include <queue>
#include <set>
#include <string>
#include <unordered_map>
#include <vector>
using namespace std;

#include "huffmunch.h"

// setting this disables the effect of huffmunch_debug()
// and removes some redundant checks
#define HUFFMUNCH_DEBUG 1

// the longest allowed length of a dictionary symbol
const unsigned int MAX_SYMBOL_SIZE = 255;

// size of allowed offset splits
// 2 bytes = 64 KB maximum output size
// 3 bytes = 16 MB maximum output size
const unsigned int SPLIT_OFFSET_SIZE = 2;

// how many symbols can be combined into a larger one in a single pass (minimum 2)
// increasing this marginally increases the ability to get over local minima
// STEP_SIZE 3 is ~1% better compression tham 2, but takes roughly twice as long
// each subsequent step is about half as effective as the previous, but increases compression time linearly
// maximum effect is reached around STEP_SIZE 8 where compression gains get lost to estimation noise
const unsigned int STEP_SIZE = 3;

// how many attempts can be made in a single pass before minima is assumed (0 for no limit)
const unsigned int CUTOFF = 100;

//
// type definitions
//

typedef unsigned int uint;
typedef uint8_t u8;

typedef uint32_t elem;
typedef u32string Stri; // string of elem
const elem EMPTY = ~0U;

//
// debug output helper
//

const unsigned int DBT = HUFFMUNCH_DEBUG_TREE;
const unsigned int DBM = HUFFMUNCH_DEBUG_MUNCH;
const unsigned int DBV = HUFFMUNCH_DEBUG_VERIFY;
const unsigned int DBI = HUFFMUNCH_DEBUG_INTERNAL;
const unsigned int DBH = HUFFMUNCH_DEBUG_HEADER;
const unsigned int DBD = HUFFMUNCH_DEBUG_DOT;

#if HUFFMUNCH_DEBUG
static unsigned int debug_bits = 0;
static int debug_text = -1;
#define DEBUG_OUT(bits_,...) { if(debug_bits & (bits_)) { printf(__VA_ARGS__); } }
#else
#define DEBUG_OUT(...) {}
#endif

//
// BitReader and BitWriter for writing a bitstream to a vector<u8>
//

class BitReader
{
	const vector<u8>* v;
	uint pos;
	uint bit;

public:
	BitReader(const vector<u8>* v_) : v(v_), pos(0), bit(0) {}

	bool end() { return pos >= v->size(); }
	uint read()
	{
		if (end()) return 0;
		uint b = ((*v)[pos] >> bit) & 1;
		++bit;
		if (bit >= 8) { bit=0; ++pos; }
		return b;
	}
	void seek(uint byte, uint bit_ = 0)
	{
		pos = byte;
		bit = 0;
		for (uint i=0; i<bit_; ++i) read();
	}
	void skip_flush() // skip to next byte
	{
		if (end()) return;
		if (bit != 0)
		{
			bit = 0;
			pos += 1;
		}
	}
};

class BitWriter
{
	vector<u8>* v;
	u8 buffer;
	uint bit;

public:
	BitWriter(vector<u8>* v_) : v(v_), buffer(0), bit(0) {}

	void flush() // finish byte
	{
		if (bit>0)
		{
			v->push_back(buffer);
			bit = 0;
		}
		buffer = 0;
	}
	void write(uint b)
	{
		assert(b == (b&1));
		buffer |= (b << bit);
		++bit;
		if (bit >= 8) flush();
	}
	void write(uint bitstream, uint count)
	{
		while (count > 0)
		{
			--count;
			uint b = (bitstream >> count) & 1;
			write(b);
		}
	}
};

// for counting instances of a hash
template <typename T>
class Counter : public unordered_map<T,uint>
{
public:
	void count(T x) { (*this)[x] += 1; } // note: missing value is automatically zero-initialized
	void count(const vector<T>& s) { for (auto x : s) count(x); }
};

// variable width integer format, either 8-bit 0-254, or 255,low,high
uint write_intx(uint x, vector<u8>& output)
{
	if (x < 255)
	{
		output.push_back(x);
		return 1;
	}
	else
	{
		if (x >= (1<<16)) throw exception("Unexpectedly large output number?");
		output.push_back(255);
		output.push_back(x & 255);
		output.push_back(x >> 8);
		return 3;
	}
}

// reads variable width integer from packed data, returns new read position, read integer in out
uint read_intx(uint pos, const vector<u8>& packed, uint& out)
{
	u8 x = packed[pos];
	if (x != 255)
	{
		out = uint(x);
		return pos+1;
	}
	else
	{
		out = uint(packed[pos+1]) + (uint(packed[pos+2]) << 8);
		return pos+3;
	}

}

// for packing unsigned integers of SPLIT_OFFSET_SIZE into the header
bool pack_header(uint v, uint index, vector<u8>& header)
{
	uint ix = index * SPLIT_OFFSET_SIZE;
	if ((ix + SPLIT_OFFSET_SIZE) > header.size())
	{
		DEBUG_OUT(DBI,"no room for header?\n");
		return false;
	}
	uint vs = v;
	for (uint i=0; i<SPLIT_OFFSET_SIZE; ++i)
	{
		header[ix+i] = vs & 0xFF;
		vs >>= 8;
	}
	if (vs != 0)
	{
		DEBUG_OUT(DBH,"split value (%d) too large for SPLIT_OFFSET_SIZE\n",v);
		return false;
	}
	return true;
}

// for unpacking unsigned integers of SPLIT_OFFSET_SIZE from the header
uint unpack_header(uint index, const vector<u8>& header)
{
	uint ix = index * SPLIT_OFFSET_SIZE;
	if ((ix + SPLIT_OFFSET_SIZE) > header.size())
	{
		DEBUG_OUT(DBH,"header not large enough for requested data?\n");
		return ~0UL;
	}
	uint v = 0;
	uint s = 0;
	for (uint i=0; i<SPLIT_OFFSET_SIZE; ++i)
	{
		v |=  header[ix+i] << s;
		s += 8;
	}
	return v;
}

inline uint bytesize(uint bits)
{
	return (bits+7)/8;
}

#if HUFFMUNCH_DEBUG

struct DotNode
{
	string name;
	Stri symbol;
	Stri prefix;
	uint c0;
	uint c1;
};

// print a vector sequence
// simple heuristic to decide whether to display print_stri as text or integer sequence
static bool print_stri_text = false;

void print_stri_setup(Stri& v)
{
	if (debug_text == 0) { print_stri_text = false; return; }
	if (debug_text == 1) { print_stri_text = true;  return; }

	print_stri_text = true;
	if (v.size() == 0) { print_stri_text = false; return; }
	for (elem e : v)
	{
		if (e == EMPTY) continue;
		if (e <= 9 || e >= 128)
		{
			print_stri_text = false;
			return;
		}
	}
	return;
}

string string_stri(const Stri& v)
{
	string s = "[";
	char hex[3] = {0,0,0};

	for (uint i=0; i<v.size(); ++i)
	{
		auto c = v[i];
		if (!print_stri_text)
		{
			if (i != 0) s.push_back(',');
			do
			{
				snprintf(hex, 3, "%02X", uint(c & 255));
				s.append(hex);
				c >>= 8;
			} while (c > 0);
		}
		else
		{
			if (c < 32 || c >= 127) c = '*';
			s.push_back(u8(c));
		}
	}

	s.push_back(']');
	return s;
}

void print_stri(const Stri& v)
{
	printf(string_stri(v).c_str());
}

string string_escape(const string s)
{
	string o;
	for (char c : s)
	{
		switch (c)
		{
			case '\\':
				o.push_back('\\');
				o.push_back('\\');
				break;
			case '"':
				o.push_back('\\');
				o.push_back('"');
				break;
			default:
				o.push_back(c);
				break;
		}
	}
	return o;
}

#else

inline void print_stri_setup(Stri& v) { (void)v; }
inline void print_tri(const Stri& v) { (void)v; }

#endif

//
// Muncher data structures
//

// Input to the Huffmunch compressor is a string of data, and a set of symbols to use

struct MunchInput
{
	Stri data;
	vector<Stri> symbols;
};

struct MunchSize
{
	uint stream_bits; // size of generated bitstream
	uint table_bytes; // size of generated table
	uint bits() const { return stream_bits + (table_bytes * 8); }
	uint bytes() const { return bytesize(bits()); }
	operator uint() { return bits(); }

	MunchSize(uint stream_bits_, uint table_bytes_) : stream_bits(stream_bits_), table_bytes(table_bytes_) {}
};

// Huffman tree

struct HuffCode
{
	uint bitstream;
	uint count;
};

struct HuffNode
{
	uint count;
	elem leaf;
	HuffNode* c0;
	HuffNode* c1;

	HuffNode(elem leaf_, int count_) : leaf(leaf_), c0(NULL), c1(NULL), count(count_) {}
	HuffNode(HuffNode* c0_, HuffNode* c1_) : leaf(EMPTY), c0(c0_),  c1(c1_),  count(c0_->count + c1_->count) {}

	struct Compare // Comparator for priority_queue<HuffNode*>
	{
		bool operator() (const HuffNode* a, const HuffNode* b) { return a->count > b->count; } 
	};
};

struct HuffTree
{
	HuffNode* head;
	vector<HuffNode*> container;
	vector<bool> visited;
	uint visit_count;

	HuffNode* add(HuffNode n)
	{
		HuffNode* p = new HuffNode(n);
		container.push_back(p);
		return p;
	}

	void empty()
	{
		for (HuffNode* p : container) { delete p; }
		container.clear();
		head = NULL;
	}

	void reset(const MunchInput& in)
	{
		// delete all the old nodes
		empty();

		// clear the visited list, expand to current size (no need to free this while iterating)
		for (uint i=0; i<visited.size(); ++i) visited[i] = false;
		while (visited.size() < in.symbols.size()) visited.push_back(false);
		visit_count = 0;
	}

	HuffTree() : head(NULL) {}
	~HuffTree() { empty(); }

	// No deep-copy
	HuffTree& operator=(const HuffTree&) = delete;
	HuffTree(const HuffTree&) = delete;
};

struct Fixup
{
	uint position;
	elem e;
};

//
// Huffman tree encoding
//

// build HuffTree from MunchInput
void huffman_tree(const MunchInput& in, HuffTree& tree)
{
	tree.reset(in);

	// count frequencies
	vector<int> count(in.symbols.size(),0);
	for (auto c : in.data)
	{
		if (c == EMPTY) continue;
		count[c] += 1;
	}

	// build nodes and put into priority queue
	priority_queue<HuffNode*,vector<HuffNode*>,HuffNode::Compare> q;
	for (uint c=0; c<in.symbols.size(); ++c)
	{
		int frequency = count[c];
		if (frequency < 1) continue;
		tree.visited[c] = true;
		q.push(tree.add(HuffNode(c,frequency)));
	}
	tree.visit_count = q.size();

	// build huffman tree
	while (q.size() > 1)
	{
		HuffNode* a = q.top(); q.pop();
		HuffNode* b = q.top(); q.pop();
		q.push(tree.add(HuffNode(a,b)));
	}

	assert(q.size() == 1);
	tree.head = q.top();
}

// calculate bits to encode data belonging to subtree (recursive)
uint huffman_tree_bits_node(const HuffNode* node, uint depth)
{
	if (node->leaf != EMPTY) return node->count * depth;
	assert(node->c0 != NULL);
	assert(node->c1 != NULL);
	return huffman_tree_bits_node(node->c0,depth+1) + huffman_tree_bits_node(node->c1,depth+1);
}

// calculate bits to encode data belonging to tree
uint huffman_tree_bits(const HuffTree& tree)
{
	return huffman_tree_bits_node(tree.head,0);
}

// encode a bitstream given a huffman code map
void huffman_encode(const unordered_map<elem,HuffCode>& codes, const Stri& data, vector<u8>& output, vector<uint>& splits)
{
	BitWriter bitstream(&output);
	for (elem c : data)
	{
		if (c == EMPTY)
		{
			bitstream.flush(); // finish byte before starting new split
			splits.push_back(output.size());
			continue;
		}
		HuffCode code = codes.at(c);
		bitstream.write(code.bitstream, code.count);
	}
	bitstream.flush();
}

//
// Huffmunch tree data structure builder
// (the output manifestation of the huffman tree)
//

elem best_suffix(elem e, uint overhead, const vector<Stri>& symbols, const vector<bool>& visited)
{
	assert(symbols.size() <= visited.size());

	const Stri& s = symbols[e];
	if (s.size() < (overhead+2)) return EMPTY; // too short for suffix

	// could probably cache this but currently doesn't seem to be the performance bottleneck
	elem best = EMPTY;
	uint best_len = overhead;
	for (elem i=0; i<symbols.size(); ++i)
	{
		if (!visited[i]) continue; // symbol has been eliminated from the tree
		if (i == e) continue; // can't be your own suffix
		const Stri& ns = symbols[i];

		if (ns.size() < best_len) continue; // too short
		if (ns.size() >= s.size()) continue; // too long

		auto match = std::mismatch(s.begin()+(s.size()-ns.size()),s.end(),ns.begin());
		if (match.first == s.end() && match.second == ns.end())
		{
			best = i;
			best_len = ns.size();
		}
	}
	return best;
}

#if !HUFFMUNCH_CANONICAL

uint huffmunch_tree_bytes_node(const HuffTree& tree, const HuffNode* node, const vector<Stri>& symbols)
{
	if (node->leaf != EMPTY)
	{
		const Stri& s = symbols[node->leaf];

		static_assert(MAX_SYMBOL_SIZE <= 255, "huffmunch tree data structure does not support leaf strings longer than 255 bytes.");
		assert(s.size() <= MAX_SYMBOL_SIZE);

		// store single byte symbol
		if (s.size() == 1) return 1 + 1; // 0 to designate single-byte leaf, 1 byte string

		// search for potential suffix strings
		elem suffix = best_suffix(node->leaf, 2, symbols, tree.visited);
		if (suffix != EMPTY)
		{
			// 2 to indicate string with suffix reference, 1 byte length, string, 16-bit suffix pointer
			return 2 + (s.size() - symbols[suffix].size()) + 2;
		}

		// store whole string
		return 2 + s.length(); // 1 to indicate string, 1 byte length, string
	}

	assert(node->c0 != NULL);
	assert(node->c1 != NULL);
	uint ta = huffmunch_tree_bytes_node(tree, node->c0, symbols);
	uint tb = huffmunch_tree_bytes_node(tree, node->c1, symbols);
	uint tmin = min(ta,tb); // smaller node goes on left
	uint skip = tmin + 1; // skip distance is left node + 1 byte to store the distance
	assert (skip >= 3); // leaf must be at least 2 bytes
	if (skip < 255) return 1 + ta + tb;
	// skip distance is longer: stored as 255 + 2 bytes
	if ((skip+2) >= (1<<16)) throw exception("Huffman tree branch unexpectedly large!");
	return 3 + ta + tb;
}

uint huffmunch_tree_bytes(const HuffTree& tree, const vector<Stri>& symbols)
{
	return huffmunch_tree_bytes_node(tree, tree.head, symbols);
}

void huffmunch_tree_build_node(const HuffTree& tree, const HuffNode* node, const vector<Stri>& symbols,
	uint depth, uint code, unordered_map<elem,HuffCode>& codes,
	vector<Fixup>& fixup, unordered_map<elem,uint>& string_position,
	vector<u8>& output)
{
	#if HUFFMUNCH_DEBUG
	if (debug_bits & DBT)
	{
		for(uint i=0;i<depth;++i) printf("+---"); printf("code %d/%d at %d\n",code,depth,output.size());
	}
	#endif

	if(node->leaf != EMPTY)
	{
		uint bitstream = code;
		assert(bitstream <= (1U<<depth)); // can't be more than 2^d leaves at level d
		HuffCode code = { bitstream, depth };

		elem e = node->leaf;
		assert(codes.find(e) == codes.end()); // don't add duplicates
		codes[e] = code;

		string_position[e] = output.size();
		Stri s = symbols[e];
		assert(s.size() < 256); // this format doesn't support larger symbols
		uint emit = s.size();

		elem suffix = best_suffix(e,2,symbols,tree.visited);

		if (emit == 1)
		{
			output.push_back(0); // 0 prefix signifies 1 byte symbol
			assert (suffix == EMPTY); suffix = EMPTY; // should be guaranteed by best_suffix anyway
		}
		else
		{
			if (suffix != EMPTY)
			{
				assert(symbols[suffix].size() < s.size());
				emit = s.size() - symbols[suffix].size();
				output.push_back(2); // 2 prefix signifies string with suffix
			}
			else
			{
				output.push_back(1); // 1 prefix signifies string
			}

			// emitted string length (if not 1)
			assert (emit > 0 && emit < 256);
			output.push_back(emit);
		}

		// emit the string
		for (uint i=0; i<emit; ++i)
		{
			assert(s[i]<256);
			output.push_back(u8(s[i]));
		}

		// placeholder 16-bit reference for suffix, to be fixed up later
		if (suffix != EMPTY)
		{
			Fixup f = { output.size(), suffix };
			fixup.push_back(f);
			output.push_back(42); // symbol chosen just to be identifiable
			output.push_back(43);
		}

		return;
	}

	assert(node->c0 != NULL);
	assert(node->c1 != NULL);

	// determine size of 2 branches
	uint ta = huffmunch_tree_bytes_node(tree, node->c0, symbols);
	uint tb = huffmunch_tree_bytes_node(tree, node->c1, symbols);

	// put lowest branch on left
	const HuffNode* na = node->c0;
	const HuffNode* nb = node->c1;
	if (tb < ta)
	{
		const HuffNode* nt = na;
		na = nb;
		nb = nt;
		uint tt = ta;
		ta = tb;
		tb = tt;
	}

	// emit size to skip to right branch
	uint p0 = output.size();
	uint skip = ta + 1; // +1 because minimum skip length is 2, but need to make room for 1 more string length
	assert(skip >= 3); // ta should never be less than 2 (single byte string leaf)
	if (skip < 255)
	{
		output.push_back(skip); // single byte skip+1
	}
	else
	{
		skip -= 1; // double byte skip
		if (skip >= (1<<16)) throw exception("Huffman tree branch unexpectedly large!");
		output.push_back(255);
		output.push_back(skip & 255);
		output.push_back(skip >> 8);
	}

	uint pa = output.size(); // position of left branch
	uint pb = pa + ta; // position of right branch

	huffmunch_tree_build_node(tree, na, symbols, depth+1, (code<<1)|0, codes, fixup, string_position, output);
	assert (output.size() == pb); // verify huffmunch_tree_bytes_node size precalculation
	huffmunch_tree_build_node(tree, nb, symbols, depth+1, (code<<1)|1, codes, fixup, string_position, output);
	assert (output.size() == pb+tb); // verify huffmunch_tree_bytes_node size precalculation

	assert ((output.size() - p0) == huffmunch_tree_bytes_node(tree,node,symbols));
}

void huffmunch_tree_build(const HuffTree& tree, const vector<Stri>& symbols, unordered_map<elem,HuffCode>& codes, vector<u8>& output)
{
	uint tree_pos = output.size();

	vector<Fixup> fixup;
	unordered_map<elem,uint> string_position;
	huffmunch_tree_build_node(tree, tree.head, symbols, 0, 0, codes, fixup, string_position, output);

	for (Fixup f : fixup)
	{
		assert (string_position.find(f.e) != string_position.end());
		uint link = string_position[f.e];
		if (link >= (1<<16)) throw exception("Unexpectedly large dictionary suffix reference.");
		assert (output[f.position+0] == 42);
		assert (output[f.position+1] == 43);
		output[f.position+0] = link & 255;
		output[f.position+1] = link >> 8;
	}

	assert((output.size()-tree_pos) == huffmunch_tree_bytes(tree, symbols));
}

// unpacks packed into unpacked, false on error
bool huffmunch_decode(const vector<u8>& packed, Stri& unpacked)
{
	// header
	vector<uint> split_start;
	vector<uint> split_size;
	uint split_count = unpack_header(0,packed);
	for (unsigned int i=0; i<split_count; ++i)
	{
		split_start.push_back(unpack_header(1+i, packed));
		split_size.push_back(unpack_header(1+i+split_count,packed));
	}
	const uint table_pos = (1 + (split_count * 2)) * SPLIT_OFFSET_SIZE;

	BitReader bitstream(&packed);

	#if HUFFMUNCH_DEBUG
	if (debug_bits & DBV)
	{
		printf("bitstream split 0 position: %d\n",split_start[0]);
		bitstream.seek(split_start[0]);
		while (!bitstream.end())
		{
			printf("%d",bitstream.read());
		}
		printf("\n");
	}
	#endif

	for (uint s=0; s<split_count; ++s)
	{
		uint length = split_size[s];
		bitstream.seek(split_start[s]);
		unpacked.push_back(EMPTY);
		DEBUG_OUT(DBV,"split %d: %X (%d bytes)\n",s,split_start[s],length);

		while (length)
		{
			uint pos = table_pos;
			uint b = 0;
			uint d = 0;

			DEBUG_OUT(DBV,"read: ");

			uint skip = packed[pos]; ++pos;
			if (skip == 255)
			{
				skip = (packed[pos+0] + (packed[pos+1]<<8)) + 1; pos += 2;
			}

			while (skip > 2)
			{
				if (bitstream.read() != 0)
				{
					pos += skip - 1; // take right node
					b = (b << 1) | 1;
					DEBUG_OUT(DBV,"1");
				}
				else
				{
					pos += 0; // take left node
					b = (b << 1) | 0;
					DEBUG_OUT(DBV,"0");
				}
				d += 1;

				// read next node header
				skip = packed[pos]; ++pos;
				if (skip == 255)
				{
					skip = (packed[pos+0] + (packed[pos+1]<<8)) + 1; pos += 2;
				}
			};
			DEBUG_OUT(DBV,"\n");

			DEBUG_OUT(DBV,"decode: %d/%d [",b,d);
			uint slen = 1;
			while (slen > 0)
			{
				if (skip > 0)
				{
					slen = packed[pos]; ++pos;
				}
			
				while (slen > 0)
				{
					elem c = packed[pos]; ++pos;
					DEBUG_OUT(DBV,"%d,",c);
					unpacked.push_back(c);
					--length;
					--slen;
				}

				if (skip == 2)
				{
					uint suffix_pos = packed[pos+0] + (packed[pos+1] << 8);
					pos = suffix_pos;
					DEBUG_OUT(DBV,"(%d),",pos);
					skip = packed[pos]; ++pos;
					if (skip > 2)
					{
						DEBUG_OUT(DBV," --- Invalid suffix?\n");
						return false;
					}
					slen = 1;
				}
			}
			DEBUG_OUT(DBV,"]\n");
		}
	}

	return true;
}

#if HUFFMUNCH_DEBUG
uint huffmunch_dot_node(uint pos, uint root, vector<u8>& data, string bits, vector<DotNode>& pool)
{
	uint index = pool.size();
	pool.push_back(DotNode());
	DotNode& node = pool.back();

	node.name = (bits.length() > 0) ? bits : "root";
	node.c0 = 0;
	node.c1 = 0;

	u8 t = data[pos];

	if (t >= 3)
	{
		uint l = 1;
		uint r = l + t - 1;
		if (t == 255)
		{
			l = 3;
			r = l + (data[pos+1] + (data[pos+2] << 8));
		}
		uint c0 = huffmunch_dot_node(pos+l, root, data, bits+"0", pool);
		uint c1 = huffmunch_dot_node(pos+r, root, data, bits+"1", pool);
		// note: node's address has been invalidated
		pool[index].c0 = c0;
		pool[index].c1 = c1;
		return index;
	}

	if (t == 0)
	{
		node.symbol.assign(data.begin()+pos+1, data.begin()+pos+2);
		return index;
	}
	else if (t == 1)
	{
		u8 len = data[pos+1];
		node.symbol.assign(data.begin()+pos+2, data.begin()+pos+2+len);
		return index;
	}

	u8 len = data[pos+1];
	uint next = data[pos+2+len] + (data[pos+3+len] << 8);
	node.prefix.assign(data.begin()+pos+2, data.begin()+pos+2+len);
	node.symbol.assign(node.prefix);
	do
	{
		pos = next;
		t = data[pos];
		assert(t < 3);
		if (t == 0)
		{
			node.symbol.push_back(data[pos+1]);
			break;
		}
		else if (t == 1)
		{
			len = data[pos+1];
			node.symbol.append(data.begin()+pos+2, data.begin()+pos+2+len);
			break;
		}
		else if (t == 2)
		{
			len = data[pos+1];
			next = data[pos+2+len] + (data[pos+3+len] << 8);
			node.symbol.append(data.begin()+pos+2, data.begin()+pos+2+len);
		}
		else break; // shouldn't happen
	} while (t == 2);

	return index;
}
#endif // HUFFMUNCH_DEBUG

#else // else if HUFFMUNCH_CANONICAL

void huffmunch_tree_bytes_node(const HuffNode* node, uint depth, vector<uint>& leaf_count)
{
	while (leaf_count.size() < (depth+1)) leaf_count.push_back(0);
	if (node->leaf != EMPTY)
	{
		leaf_count[depth] += 1;
		return;
	}

	assert(node->c0 != NULL);
	assert(node->c1 != NULL);
	huffmunch_tree_bytes_node(node->c0, depth+1, leaf_count);
	huffmunch_tree_bytes_node(node->c1, depth+1, leaf_count);
}

uint huffmunch_tree_bytes(const HuffTree& tree, const vector<Stri>& symbols)
{
	uint bytes = 0;

	// generate the leaf count list
	vector<uint> leaf_count;
	huffmunch_tree_bytes_node(tree.head, 0, leaf_count);
	for (uint c : leaf_count)
	{
		bytes += 1;
		if (c > 255) bytes += 2; // if many leaves on this level write 255 + 16-bit number
		if (c >= (1<<16)) throw exception("Huffman tree level unexpectedly large!");
	}
	auto tree_depth = leaf_count.size();
	if (tree_depth >= (1<<16)) throw exception("Huffman tree unexpectedly deep!");

	// generate the string table
	for (elem j=0; j<symbols.size(); ++j)
	{
		if (!tree.visited[j]) continue;
		Stri s = symbols[j];

		static_assert(MAX_SYMBOL_SIZE <= 255, "huffmunch tree data structure does not support leaf strings longer than 255 bytes.");
		assert(s.size() <= MAX_SYMBOL_SIZE);

		// search for potential suffix strings
		elem suffix = best_suffix(j,3,symbols,tree.visited);
		if (suffix != EMPTY)
		{
			// 0 to indicate suffix, 1 byte length, prefix, 16-bit reference
			bytes += 1 + 1 + (s.size() - symbols[suffix].size()) + 2;
			continue;
		}

		// 1 byte length, string
		bytes += 1 + s.size();
	}

	bytes += 1; // store depth of tree
	if (tree_depth >= 256) bytes += 2; // stored as 0, 16-bit for very deep trees

	return bytes;
}

void huffmunch_tree_build_node(const HuffNode* node, uint depth, vector<vector<elem>>& leaves)
{
	// add new level of leaves as encountered
	while (leaves.size() < (depth+1))
	{
		vector<elem> n;
		leaves.push_back(n);
	}

	if (node->leaf != EMPTY)
	{
		leaves[depth].push_back(node->leaf);
		return;
	}

	assert(node->c0 != NULL);
	assert(node->c1 != NULL);
	huffmunch_tree_build_node(node->c0, depth+1, leaves);
	huffmunch_tree_build_node(node->c1, depth+1, leaves);
}

void huffmunch_tree_build(const HuffTree& tree, const vector<Stri>& symbols, unordered_map<elem,HuffCode>& codes, vector<u8>& output)
{
	uint tree_pos = output.size();

	vector<vector<elem>> leaves;
	huffmunch_tree_build_node(tree.head, 0, leaves);

	// write count table
	if (leaves.size() >= 255) throw exception("Huffman tree unexpectedly deep!");
	write_intx(leaves.size(),output); // length of table
	for (uint d=0; d < leaves.size(); ++d)
	{
		write_intx(leaves[d].size(), output); // nodes at each level
		assert(leaves[d].size() <= (1U<<d)); // level has more nodes than possible for a binary tree
	}

	// write string table, generate canonical codes

	// keep track of addresses to fixup for suffix pointers
	struct Fixup { uint position; elem e; };
	vector<Fixup> fixup;
	unordered_map<elem,uint> string_position;

	uint bitcode = 0;
	for (uint d=0; d < leaves.size(); ++d)
	{
		vector<elem>& level = leaves[d];
		for (uint c=0; c < level.size(); ++c)
		{
			assert(bitcode < (1U<<d)); // can't be more than 2^d leaves at level d
			HuffCode code = { bitcode, d };
			DEBUG_OUT(DBT,"symbol %d/%d: ",bitcode,d);
			++bitcode; // next available leaf on this layer

			elem e = level[c];
			assert(codes.find(e) == codes.end()); // don't add duplicates
			codes[e] = code;

			string_position[e] = output.size();
			Stri s = symbols[e];
			assert(s.size() < 256); // this format doesn't support larger symbols
			uint emit = s.size();

			#if HUFFMUNCH_DEBUG
			if (debug_bits & DBT) print_stri(s);
			#endif

			elem suffix = best_suffix(e,3,symbols,tree.visited);
			if (suffix != EMPTY)
			{
				assert(symbols[suffix].size() < s.size());
				emit = s.size() - symbols[suffix].size();
				output.push_back(0); // 0 prefix signifies string with suffix
			}

			// emit the string
			assert (emit > 0 && emit < 256);
			output.push_back(emit);
			for (uint i=0; i<emit; ++i)
			{
				assert(s[i]<256);
				output.push_back(u8(s[i]));
			}

			// placeholder 16-bit reference for suffix, to be fixed up later
			if (suffix != EMPTY)
			{
				Fixup f = { output.size(), suffix };
				fixup.push_back(f);
				output.push_back(42); // symbol chosen just to be identifiable
				output.push_back(43);
				DEBUG_OUT(DBT," (%d)",suffix);
			}
			DEBUG_OUT(DBT,"\n");
		}
		bitcode *= 2; // next available leaf node on next layer will be at 2x index
	}

	for (Fixup f : fixup)
	{
		assert (string_position.find(f.e) != string_position.end());
		uint link = string_position[f.e];
		if (link >= (1<<16)) throw exception("Unexpectedly large canonical dictionary suffix reference.");
		assert (output[f.position+0] == 42);
		assert (output[f.position+1] == 43);
		output[f.position+0] = link & 255;
		output[f.position+1] = link >> 8;
	}

	assert((output.size()-tree_pos) == huffmunch_tree_bytes(tree, symbols));
}

// unpacks packed into unpacked, false on error
bool huffmunch_decode(const vector<u8>& packed, Stri& unpacked)
{
	// header
	vector<uint> split_start;
	vector<uint> split_size;
	uint split_count = unpack_header(0,packed);
	for (unsigned int i=0; i<split_count; ++i)
	{
		split_start.push_back(unpack_header(1+i, packed));
		split_size.push_back(unpack_header(1+i+split_count,packed));
	}
	const uint table_pos = (1 + (split_count * 2)) * SPLIT_OFFSET_SIZE;

	uint pos = table_pos;

	// read depth of tree
	uint depth;
	pos = read_intx(table_pos, packed, depth);
	DEBUG_OUT(DBV,"depth: %d\n", depth);

	// read leaf counts from tree
	uint string_count = 0;
	vector<uint> leaf_count;
	for (uint i=0; i<depth; ++i)
	{
		uint leaves;
		pos = read_intx(pos, packed, leaves);
		leaf_count.push_back(leaves);
		string_count += leaves;
		DEBUG_OUT(DBV,"leaves %d: %d\n",i,leaves);
	}
	DEBUG_OUT(DBV,"string count: %d\n",string_count);
	const uint string_table_pos = pos;

	BitReader bitstream(&packed);

	#if HUFFMUNCH_DEBUG
	if (debug_bits & DBV)
	{
		printf("bitstream split 0 position: %d\n",split_start[0]);
		bitstream.seek(split_start[0]);
		while (!bitstream.end())
		{
			printf("%d",bitstream.read());
		}
		printf("\n");
	}
	#endif

	for (uint s=0; s<split_count; ++s)
	{
		uint length = split_size[s];
		bitstream.seek(split_start[s]);
		unpacked.push_back(EMPTY);
		DEBUG_OUT(DBV,"split %d: %X (%d bytes)\n",s,split_start[s],length);

		while (length)
		{
			uint fc = 0; // first code at current depth
			uint fs = 0; // first symbol at current depth
			uint b = 0; // current bitcode

			uint s = 0; // symbol to decode
			uint d;
			for (d=0; d <= depth; ++d)
			{
				uint ds = leaf_count[d]; // symbols on current layer
				uint dc = b - fc; // relative code at current depth

				//if (verbose_debug) printf("decode: %d/%d (%d,%d,%d,%d)\n",b,d,ds,dc,fs,fc);

				if (dc < ds)
				{
					// symbol is matched
					s = fs + dc;
					break;
				}
				fs += ds; // advance first symbol to next layer
				fc += ds; // advance code to first non-leaf on layer...
				fc *= 2;  // ...then make room for a new bit on next layer

				// read a new bit
				b = (b << 1) | bitstream.read();
			}
			if (d > depth) return false; // break was not reached, should be impossible?
			if (s >= string_count) return false; // should also be impossible
			DEBUG_OUT(DBV,"(%d) decode: %d/%d > %d [",unpacked.size(),b,d,s);

			// find the start of symbol
			pos = string_table_pos;
			for (uint is = 0; is < s; ++is)
			{
				uint slen = packed[pos]; ++pos;
				if (slen != 0)
				{
					pos += slen;
				}
				else
				{
					slen = packed[pos]; ++pos;
					pos += slen + 2;
				}
			}
			// emit symbol
			bool remains = true;
			while (remains)
			{
				uint slen = packed[pos]; ++pos;
				if (slen != 0)
				{
					for (uint i=0; i<slen; ++i)
					{
						elem c = packed[pos]; ++pos;
						DEBUG_OUT(DBV,"%d,",c);
						unpacked.push_back(c);
						--length;
					}
					remains = false; // no suffix
				}
				else
				{
					slen = packed[pos]; ++pos;
					if (slen < 1) return false; // malformed symbol
					for (uint i=0; i<slen; ++i)
					{
						elem c = packed[pos]; ++pos;
						DEBUG_OUT(DBV,"%d,",c);
						unpacked.push_back(c);
						--length;
					}
					// repeat loop from new suffix string
					uint suffix_pos = packed[pos+0] + (packed[pos+1] << 8);
					pos = suffix_pos;
					remains = true;
					DEBUG_OUT(DBV,"(%d),",pos);
				}
			}
			DEBUG_OUT(DBV,"]\n");
		}
	}

	return true;
}

#endif // end (!HUFFMUNCH_CANONICAL else HUFFMUNCH_CANONICAL)

//
// the "muncher" that gradually compresses the data by building up its dictionary
//

// compute the size of the data with a given dictionary
MunchSize huffmunch_size(const MunchInput& in)
{
	MunchSize size = {0,0};
	if (in.data.size() < 1) return size;

	HuffTree tree;
	huffman_tree(in,tree);
	size.stream_bits = huffman_tree_bits(tree);
	size.table_bytes = huffmunch_tree_bytes(tree, in.symbols);
	return size;
}

MunchInput huffmunch_munch(const Stri& data)
{
	const uint data_total = data.size() * 8;

	// setup initial best
	MunchInput best;
	best.data = data;
	elem n = 0;
	for (elem v : data)
	{
		if (v == EMPTY) continue;
		if (v > n) n = v;
	}
	best.symbols.clear();
	for (elem i=0; i<=n; ++i)
	{
		Stri s;
		s.push_back(i);
		best.symbols.push_back(s);
	}
	MunchSize best_size = huffmunch_size(best);

	// buffers for storing Rabin-Karp style hashes of various widths for repeated string detection
	vector<elem> rk[STEP_SIZE-1];
	Counter<elem> rk_freq[STEP_SIZE-1];
	const uint RK_PRIME = 467; // rolling hash prime, not a factor of (2^32)-1, "nice" binary representation 111010011
	uint RK_ERASE[STEP_SIZE-1] = {RK_PRIME};
	for (int i=1; i<(STEP_SIZE-1); ++i)
		RK_ERASE[i] = RK_ERASE[i-1] * RK_PRIME;

	Stri last_symbol;
	uint last_bits_saved = 0;
	uint last_symbol_count = 0;
	uint last_symbol_len = 0;
	uint last_attempt = 0;
	uint last_attempt_size = 0;
	uint last_visit_count = 0;
	uint symbols_added = 0;
	bool minima = false;

	set<pair<elem, uint>> hash_tried;
	set<Stri> hash_strings;

	while (!minima)
	{
		// each step:
		// - analyze current best.data for repeated strings
		// - make a prioritized list of the repeated strings (guess priority based on frequency/length)
		// - trial each string until one that decreases the data size is found
		// - if the data was reduced, repeat the next step

		#if HUFFMUNCH_DEBUG
		if (debug_bits & DBM)
		{
			printf("%d: %d of %d (%d + %d/%d) => %5.2f%% ",
				symbols_added, best_size.bytes(), bytesize(data_total), bytesize(best_size.stream_bits), best_size.table_bytes, last_visit_count, (100.0 * best_size) / data_total);
			printf("%5db/%3d*%1d %4d>%4d ", last_bits_saved, last_symbol_count, last_symbol_len, last_attempt_size, last_attempt);
			print_stri(last_symbol);
			printf("\n");
		}
		#endif

		// generate rolling hash for several string widths, count their frequency

		for (uint ss=2; ss<=STEP_SIZE; ++ss)
		{
			const uint si = ss-2; // index to rk
			const uint su = ss-1;
			const uint erase = RK_ERASE[si];
			const uint rksize = (best.data.size() >= su) ? (best.data.size() - su) : 0;
			rk[si].resize(rksize);
			rk_freq[si].clear();

			elem hash = 0;
			for (uint i=0; i<su; ++i)
			{
				hash = (hash * RK_PRIME) + best.data[i];
			}
			for (uint i=0; i<rksize; ++i)
			{
				hash = (hash * RK_PRIME) + best.data[i+su];
				rk[si][i] = hash;
				rk_freq[si].count(hash);
				hash -= best.data[i] * erase; // roll off
			}
		}

		// prioritize hashes by potential bytes replaced (rough estimate of size saved, not accounting for the huffman coding/dictionary)

		typedef tuple<uint, uint, elem> Task; // < bytes saved, string length, hash >
		auto task_less = [](const Task& a, const Task& b)
		{
			return (get<0>(a) != get<0>(b)) ?
				(get<0>(a) < get<0>(b)) : // favour more bytes saved
				(get<1>(a) > get<1>(b)) ; // otherwise favour shorter strings
		};
		priority_queue<Task, std::vector<Task>, decltype(task_less)> task_queue(task_less);
		task_queue.empty();

		for (uint ss=2; ss<=STEP_SIZE; ++ss)
		{
			const uint si = ss-2; // index to rk
			const uint su = ss-1;
			for (pair<elem, uint> rkf : rk_freq[si])
			{
				elem hash = rkf.first;
				uint count = rkf.second;
				if (count < 1) continue;
				Task task = Task(count*su, si, hash);
				if (0 == hash_tried.count(pair<elem,uint>(hash,si)))
				{
					task_queue.push(task);
				}
			}
		}

		// trial each task in order of priority

		minima = true;
		last_attempt = 0;
		last_attempt_size = task_queue.size();

		while (task_queue.size() > 0)
		{
			Task task = task_queue.top();
			task_queue.pop();
			const uint bsave = get<0>(task);
			const uint si = get<1>(task);
			const elem hash = get<2>(task);
			const uint su = si+1;
			const uint ss = si+2;

			// hashes can have collisions, so find all strings with this hash
			hash_strings.clear();
			for (uint i=su; i<rk[si].size(); ++i)
			{
				if (rk[si][i] == hash)
				{
					Stri s = Stri(best.data.c_str()+i,ss);
					hash_strings.insert(s);
				}
			}

			// try each of these strings
			for (Stri s : hash_strings)
			{
				if (string::npos != s.find(EMPTY)) continue; // don't allow splits to be included in compression

				Stri next_symbol = best.symbols[s[0]];
				for (uint i=1; i<s.size(); ++i)
					next_symbol = next_symbol + best.symbols[s[i]];
				if (next_symbol.size() >= MAX_SYMBOL_SIZE) continue;
				// really MAX_SYMBOL_SIZE applies to the finished tree symbol, which could be shortened as a prefix
				// but it's probably "good enough" to enforce this here instead.

				#if HUFFMUNCH_DEBUG
				if ((debug_bits & DBM) && false) // for debugging all attempts
				{
					printf("%4d: %5d (%4d*%1d) %08X ",last_attempt, bsave, bsave/su, ss, hash);
					print_stri(next_symbol);
					printf("\n");
				}
				#endif

				MunchInput next;

				// add a new symbol to the tree
				next.symbols = best.symbols;
				elem n = next.symbols.size();
				next.symbols.push_back(next_symbol);

				// create the data, replacing the matched string with the new symbol
				next.data.reserve(best.data.size());
				uint i=0;
				for (; i<rk[si].size(); ++i)
				{
					const elem o = best.data[i];
					if(rk[si][i] == hash && Stri(best.data.c_str()+i,ss) == s)
					{
						next.data.push_back(n);
						i += su;
					}
					else
					{
						next.data.push_back(o);
					}
				}
				for (; i < best.data.size(); ++i) // trailing bytes of the last unmatched symbol
				{
					next.data.push_back(best.data[i]);
				}

				last_symbol = next_symbol;
				last_symbol_count = bsave / su;
				last_symbol_len = ss;

				// test the actual finished size of the new data and tree
				MunchSize next_size = huffmunch_size(next);
				if (next_size < best_size)
				{
					minima = false;
					best = next;
					last_bits_saved = best_size - next_size;
					best_size = next_size;
					++symbols_added;
					break;
				}
			}

			if (!minima) break;

			// all strings of this hash have been tried, add it to the exhausted list
			// (this could be a false positive if the a new symbol causes a hash collision,
			// but that has low probability and the speed gain by ignoring this seems worthwhile)
			hash_tried.insert(pair<elem,uint>(hash,si));

			++last_attempt;
			if (CUTOFF && last_attempt >= CUTOFF) break;

		} // while (task_queue.size() > 0)
	} // while (minima)

	return best;
}

//
// public interface
//

const unsigned int SPLITS_DEFAULT[1] = { 0 };

bool splits_valid(const unsigned int* splits, unsigned int split_count)
{
	if (split_count < 1) return false;
	if (splits[0] != 0)
	{
		DEBUG_OUT(DBV,"splits must begin with 0");
		return false;
	}
	for (unsigned int i=1; i<split_count; ++i)
	{
		if (splits[i] < splits[i+1])
		{
			DEBUG_OUT(DBV,"splits must be in increasing order");
			return false;
		}
	}
	return true;
}

const char* huffmunch_error_description(int e)
{
	switch (e)
	{
	case HUFFMUNCH_OK: return "No error.";
	case HUFFMUNCH_OUTPUT_OVERFLOW: return "Output data too large for buffer.";
	case HUFFMUNCH_VERIFY_FAIL: return "Internal verification error.";
	case HUFFMUNCH_INTERNAL_ERROR: return "Internal error.";
	case HUFFMUNCH_INVALID_SPLITS: return "Splits must only increase in valid, beginning with 0.";
	case HUFFMUNCH_SPLIT_OVERFLOW: return "Split offset or data size too large for SPLIT_OFFSET_SIZE.";
	default: return "Unknown error value.";
	}
}

int huffmunch_compress(
	const unsigned char* data,
	unsigned int data_size,
	unsigned char* output,
	unsigned int& output_size,
	const unsigned int *splits,
	unsigned int split_count)
{
	if (splits == NULL)
	{
		splits = SPLITS_DEFAULT;
		split_count = 1;
	}
	if (!splits_valid(splits, split_count)) return HUFFMUNCH_INVALID_SPLITS;

	try
	{
		Stri sdata;
		unsigned int s=0;
		for (unsigned int i=0; i<data_size; ++i)
		{
			if (s < split_count && i == splits[s])
			{
				sdata.push_back(EMPTY);
				++s;
			}
			sdata.push_back(elem(data[i]));
		}
		for (; s < split_count; ++s) sdata.push_back(EMPTY);

		#if HUFFMUNCH_DEBUG
		print_stri_setup(sdata);
		#endif

		MunchInput best = huffmunch_munch(sdata);

		HuffTree tree;
		unordered_map<elem,HuffCode> codes;
		vector<u8> packed;
		vector<uint> packed_splits;

		// header containing:
		// 1 x split count
		// split_count x split data offset
		// split_count x split data size
		uint prefix_size = ((split_count * 2) + 1) * SPLIT_OFFSET_SIZE;
		for (uint i=0; i<prefix_size; ++i) packed.push_back(44); // reserve space for header

		huffman_tree(best, tree);
		huffmunch_tree_build(tree, best.symbols, codes, packed);
		huffman_encode(codes, best.data, packed, packed_splits);

		DEBUG_OUT(DBH,"split_count: %d\n",split_count);
		if (!pack_header(split_count, 0, packed)) return HUFFMUNCH_SPLIT_OVERFLOW;

		#if HUFFMUNCH_DEBUG
		if (debug_bits & DBD) huffmunch_dot(&packed[0],packed.size(),print_stri_text);
		#endif

		for (unsigned int i=0; i<split_count; ++i)
		{
			uint split_packed_start = packed_splits[i];
			uint split_start = splits[i];
			uint split_end = data_size;
			if ((i+1) < split_count) split_end = splits[i+1];
			uint split_size = split_end - split_start;

			DEBUG_OUT(DBH,"split %d: %X (%X, %d bytes)\n",i,split_packed_start,split_start,split_size);
			if (!pack_header(split_packed_start, 1+i, packed)) return HUFFMUNCH_SPLIT_OVERFLOW;
			if (!pack_header(split_size, 1+split_count+i, packed)) return HUFFMUNCH_SPLIT_OVERFLOW;
		}

		#if HUFFMUNCH_DEBUG
		Stri verify;
		if (huffmunch_decode(packed, verify))
		{
			if (verify != sdata)
			{
				DEBUG_OUT(DBV,"error: verify failed, %d bytes decoded\n",verify.size());
				return HUFFMUNCH_VERIFY_FAIL;
			}
		}
		else
		{
			DEBUG_OUT(DBV,"error: verify unable to decode\n");
			return HUFFMUNCH_VERIFY_FAIL;
		}
		#endif

		if (packed.size() > output_size)
		{
			output_size = packed.size();
			return HUFFMUNCH_OUTPUT_OVERFLOW;
		}
		output_size = packed.size();
		if (output)
		{
			for (unsigned int i=0; i < packed.size(); ++i)
				output[i] = packed[i];
		}
	}
	catch (exception e)
	{
		DEBUG_OUT(DBI,"error: internal error: %s\n",e.what());
		return HUFFMUNCH_INTERNAL_ERROR;
	}

	return HUFFMUNCH_OK;
}

int huffmunch_decompress(
	const unsigned char* data,
	unsigned int data_size,
	unsigned char* output,
	unsigned int& output_size)
{
	try
	{
		vector<u8> packed;
		for (unsigned int i=0; i<data_size; ++i) packed.push_back(data[i]);
		assert(packed.size() == data_size);

		Stri unpacked;
		huffmunch_decode(packed, unpacked);

		unsigned int pos = 0;
		for (unsigned int i=0; i < unpacked.size(); ++i)
		{
			elem v = unpacked[i];
			if (v != EMPTY)
			{
				if (output && pos < output_size) output[pos] = v;
				++pos;
			}
		}
		if (pos > output_size) return HUFFMUNCH_OUTPUT_OVERFLOW;
	}
	catch (exception e)
	{
		DEBUG_OUT(DBI,"error: internal error: %s\n",e.what());
		return HUFFMUNCH_INTERNAL_ERROR;
	}

	return HUFFMUNCH_OK;
}

void huffmunch_debug(unsigned int debug_bits_, int text)
{
	debug_bits = debug_bits_;
	debug_text = text;
}

void huffmunch_dot(
	const unsigned char* data,
	unsigned int data_size,
	bool text)
{
	#if HUFFMUNCH_DEBUG
	vector<u8> packed;
	for (unsigned int i=0; i<data_size; ++i) packed.push_back(data[i]);
	assert(packed.size() == data_size);

	printf("digraph G {\n");
	printf("\tnode [shape=box style=filled]\n");

	uint count = unpack_header(0,packed);
	uint tree_pos = ((count * 2) + 1) * SPLIT_OFFSET_SIZE;
	vector<DotNode> tree;
	huffmunch_dot_node(tree_pos, tree_pos, packed, "", tree);
	for (const DotNode& node : tree)
	{
		string colour = "#EEEEEE";
		char ne = node.name[node.name.length()-1];
		if (ne == '0') colour = "#FFDDDD";
		if (ne == '1') colour = "#DDFFCC";

		string label = node.name;
		if (node.symbol.length() > 0)
		{
			colour = "#FFEE88";
			label += "\\n";
			label += string_escape(string_stri(node.symbol));
			label += "";
		}
		if (node.prefix.length() > 0)
		{
			colour = "#FFEEBB";
			label += "\\n";
			label += string_escape(string_stri(node.prefix));
			label += "...";
		}

		printf("\t%s [label=\"%s\" fillcolor=\"%s\"]\n",
			node.name.c_str(),
			label.c_str(),
			colour.c_str());

		if (node.c0) printf("\t%s -> %s\n",node.name.c_str(),tree[node.c0].name.c_str());
		if (node.c1) printf("\t%s -> %s\n",node.name.c_str(),tree[node.c1].name.c_str());

		if (node.prefix.length() > 0)
		{
			assert(node.prefix.length() < node.symbol.length());
			Stri suffix(node.symbol.begin() + node.prefix.length(), node.symbol.end());
			for (const DotNode& match : tree)
			{
				if (match.symbol == suffix)
				{
					colour = "#CCCCCC";
					printf("\t%s -> %s [color=\"%s\" constraint=false]\n",
						node.name.c_str(),
						match.name.c_str(),
						colour.c_str());
				}
			}
		}
	}
	
	printf("}\n");
	#endif
}

// end of file
