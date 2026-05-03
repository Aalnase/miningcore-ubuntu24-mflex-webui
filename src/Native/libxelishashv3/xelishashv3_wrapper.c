#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define XELIS_INPUT_LEN 112
#define XELIS_HASH_SIZE 32
#define XELIS_MEMSIZE (531 * 128)

/*
 * Official function from xelis_hash_v3.c:
 * void xelis_hash_v3(uint8_t in[112], uint8_t hash[32], uint64_t scratch[531 * 128]);
 */
void xelis_hash_v3(uint8_t in[XELIS_INPUT_LEN], uint8_t hash[XELIS_HASH_SIZE], uint64_t scratch[XELIS_MEMSIZE]);

/*
 * Miningcore-compatible export.
 * Signature matches C#:
 * void xelishashv3(byte* input, byte* output, uint inputLength)
 */
__attribute__((visibility("default")))
void xelishashv3(uint8_t* input, uint8_t* output, uint32_t inputLength)
{
    uint8_t in[XELIS_INPUT_LEN];
    memset(in, 0, sizeof(in));

    if(inputLength >= XELIS_INPUT_LEN)
        memcpy(in, input, XELIS_INPUT_LEN);
    else
        memcpy(in, input, inputLength);

    uint64_t* scratch = (uint64_t*) calloc(XELIS_MEMSIZE, sizeof(uint64_t));

    if(scratch == NULL)
    {
        memset(output, 0, XELIS_HASH_SIZE);
        return;
    }

    xelis_hash_v3(in, output, scratch);

    free(scratch);
}
