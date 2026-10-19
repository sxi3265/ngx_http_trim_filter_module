/* Build with clang -fsanitize=fuzzer,address,undefined. */
#define NGX_HTTP_TRIM_TEST  1
#include "../ngx_http_trim_filter_module.c"
#include <assert.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

int
LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    u_char                  *whole, *chunks;
    size_t                   i, n, m, step, part;
    ngx_http_trim_parser_t    a, b;

    if (size == 0) {
        return 0;
    }

    whole = malloc(size + NGX_HTTP_TRIM_PENDING);
    chunks = malloc(size + NGX_HTTP_TRIM_PENDING);
    if (whole == NULL || chunks == NULL) {
        free(whole);
        free(chunks);
        return 0;
    }

    memset(&a, 0, sizeof(a));
    a.js = data[0] & 1;
    a.css = data[0] & 2;
    b = a;
    n = ngx_http_trim_parse(&a, data + 1, size - 1, whole);
    n += ngx_http_trim_finish(&a, whole + n);
    step = 1 + (data[0] >> 2);
    m = 0;
    for (i = 1; i < size; i += part) {
        part = size - i < step ? size - i : step;
        m += ngx_http_trim_parse(&b, data + i, part, chunks + m);
        assert(m <= i + part - 1);
    }
    m += ngx_http_trim_finish(&b, chunks + m);
    assert(n <= size - 1 && n == m && memcmp(whole, chunks, n) == 0);
    free(whole);
    free(chunks);
    return 0;
}


#ifdef NGX_HTTP_TRIM_FUZZ_STANDALONE

static uint32_t
ngx_http_trim_test_random(uint32_t *state)
{
    *state ^= *state << 13;
    *state ^= *state >> 17;
    *state ^= *state << 5;

    return *state;
}


int
main(void)
{
    u_char    data[8192];
    size_t    i, j, n, pos, changes;
    uint32_t  state;

    static const char *seeds[] = {
        "<p  title='x'>a  b</p><!--comment-->",
        "<script>var  x = `a ${`b ${x}`}`;</script>",
        "<script>var/**/x = /['\"]/;</script>",
        "<style>.x { --x: a/**/b; content: 'a  b'; }</style>",
        "<title>a<!--keep--></title><textarea>x</textarea>",
        "<!--x--!><p  ><!--->x</p>",
        "<script><!--<script></script><!--x--></script>",
        "<pre><PRE>x</PRE></pre><p a=b/ >",
        "<!DOCTYPE html><svg><![CDATA[<!--x-->]]></svg>"
    };

    state = 0x763129ab;

    for (i = 0; i < 100000; i++) {
        data[0] = ngx_http_trim_test_random(&state) & 0xff;

        if (i % 8) {
            j = ngx_http_trim_test_random(&state)
                % (sizeof(seeds) / sizeof(seeds[0]));
            n = strlen(seeds[j]);
            memcpy(data + 1, seeds[j], n);
            changes = ngx_http_trim_test_random(&state) % 12;

            for (j = 0; j < changes; j++) {
                pos = 1 + ngx_http_trim_test_random(&state) % n;
                data[pos] = ngx_http_trim_test_random(&state) & 0xff;
            }

        } else {
            n = ngx_http_trim_test_random(&state) % (sizeof(data) - 1);

            for (j = 1; j <= n; j++) {
                data[j] = ngx_http_trim_test_random(&state) & 0xff;
            }
        }

        LLVMFuzzerTestOneInput(data, n + 1);
    }

    puts("parser: 100000 deterministic fuzz inputs passed");

    return 0;
}

#endif
