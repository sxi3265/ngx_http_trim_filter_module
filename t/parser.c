/* Standalone semantic and chunk-boundary regressions. */
#define NGX_HTTP_TRIM_TEST  1
#include "../ngx_http_trim_filter_module.c"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned long checks;

static void
ngx_http_trim_test_case(const char *input, const char *expected,
    ngx_uint_t js, ngx_uint_t css)
{
    u_char                  *out;
    size_t                   len, want, cut, n, i;
    ngx_http_trim_parser_t    p;

    len = strlen(input);
    want = strlen(expected);
    out = malloc(len + NGX_HTTP_TRIM_PENDING + 1);
    assert(out);
    for (cut = 0; cut <= len; cut++) {
        memset(&p, 0, sizeof(p));
        p.js = js;
        p.css = css;
        n = ngx_http_trim_parse(&p, (const unsigned char *) input, cut, out);
        n += ngx_http_trim_parse(&p, (const unsigned char *) input + cut, len - cut, out + n);
        n += ngx_http_trim_finish(&p, out + n);
        out[n] = 0;
        if (n != want || memcmp(out, expected, want)) {
            fprintf(stderr, "split %lu\ninput: %s\nwant: %s\ngot: %s\n",
                    (unsigned long) cut, input, expected, out);
            abort();
        }
        checks++;
    }
    memset(&p, 0, sizeof(p));
    p.js = js;
    p.css = css;
    n = 0;
    for (i = 0; i < len; i++) {
        n += ngx_http_trim_parse(&p, (const unsigned char *) input + i, 1, out + n);
    }
    n += ngx_http_trim_finish(&p, out + n);
    assert(n == want && memcmp(out, expected, want) == 0);
    checks++;
    free(out);
}

int
main(void)
{
    char *long_tag;
    const char *same[] = {
        "<p>hello   world\r\n\t</p>",
        "<div style=\"white-space:pre-wrap\">a  b\n  c</div>",
        "<div class=from-external-css>a  b\n  c</div>",
        "<title>a <!--keep--> b</title>",
        "<TITLE>a <!--keep--> b</TITLE>",
        "<xmp>a  b<!--keep--></xmp>",
        "<iframe>a  b<!--keep--></iframe>",
        "<noembed>a  b<!--keep--></noembed>",
        "<noframes>a  b<!--keep--></noframes>",
        "<textarea>a  b<!--keep--></textarea>",
        "<pre>a  b<!--keep--></pre>",
        "<script>const x = `a  b`;</script>",
        "<script>const x = `a // b`;</script>",
        "<script>const x = `a ${`b ${x}`} c`;</script>",
        "<script>var/**/x = 1;</script>",
        "<script>return/*\n*/x;</script>",
        "<script>const r = /[/  ]x/;</script>",
        "<script>const r = /['\"]/; var x =  1;</script>",
        "<script>const s = 'a  b';</script>",
        "<script>const s = \"a  \\\"  b\";</script>",
        "<script>return\r\nx;</script>",
        "<script>a + +b; a - -b;</script>",
        "<script><!--<script></script><!--keep--></script><p>a  b</p>",
        "<script>x</script a\"b=\"> <!--keep--> x'>",
        "<script type=application/json>{\"x\":  2}</script>",
        "<script type=text/css>.x  {color:  red}</script>",
        "<script language=vbscript>MsgBox  x</script>",
        "<style type=text/javascript>var  x</style>",
        "<style>.x { --pair: a  b; }</style>",
        "<style>.x { --pair: a/**/b; }</style>",
        "<style>.x { width: calc(100% - 2px); }</style>",
        "<style>.x::before { content: \"a  b\"; }</style>",
        "<style>.x { background: url(a\\ b); }</style>",
        "<p>a</p><", "<p>a</p><!-", "<p>a</p><!--unfinished",
        "<script>x</scrip", "<p title='unfinished>",
        "<span>a</span> <span>b</span>",
        "<p a=b/>", "<p a=b/ >", "<p a=b />", "<p/>",
        "<svg><![CDATA[a <!--keep--> b]]></svg>",
        "<math><annotation-xml><!--keep--></annotation-xml></math>",
        "<noscript><p>a <!--keep--> b</p></noscript>",
        "<select><style>.x  { color:  red; }</style></select>",
        "<plaintext>a <!--keep--> b",
        "<!--# include -->", "<!--esi x -->", "<!--[if IE]>x<![endif]-->",
        "<!--$--><p>x</p><!--/$-->", NULL
    };
    unsigned i;

    for (i = 0; same[i]; i++) {
        ngx_http_trim_test_case(same[i], same[i], 1, 1);
    }
    ngx_http_trim_test_case("<p  id = 'x'  disabled >a  b</p>",
          "<p id='x' disabled>a  b</p>", 1, 1);
    ngx_http_trim_test_case("a<!-- remove -->b", "ab", 1, 1);
    ngx_http_trim_test_case("a <!-- remove --> b", "a  b", 1, 1);
    ngx_http_trim_test_case("<!-->a<!--->b<!--x--!>c", "abc", 1, 1);
    ngx_http_trim_test_case("<!DOCTYPE html><p  >x</p><!--x-->",
          "<!DOCTYPE html><p>x</p>", 1, 1);
    ngx_http_trim_test_case("<script>var  x =  1;\nreturn\n  x;</script><!--x-->",
          "<script>var x = 1;\nreturn\n x;</script>", 1, 1);
    ngx_http_trim_test_case("<script>var  x =  1;</script>",
          "<script>var  x =  1;</script>", 0, 1);
    ngx_http_trim_test_case("<style>.x  { color:  red; }</style>",
          "<style>.x { color: red; }</style>", 1, 1);
    ngx_http_trim_test_case("<style>.x  { color:  red; }</style>",
          "<style>.x  { color:  red; }</style>", 1, 0);
    ngx_http_trim_test_case("<TITLE>x</TiTlE ><p  >x</p><!--x-->",
          "<TITLE>x</TiTlE ><p>x</p>", 1, 1);
    ngx_http_trim_test_case("<textarea>x</textarea-not><!--keep--></textarea><!--x-->",
          "<textarea>x</textarea-not><!--keep--></textarea>", 1, 1);

    long_tag = malloc(NGX_HTTP_TRIM_PENDING + 100);
    assert(long_tag);
    strcpy(long_tag, "<p title='");
    memset(long_tag + 10, 'x', NGX_HTTP_TRIM_PENDING + 20);
    strcpy(long_tag + NGX_HTTP_TRIM_PENDING + 30, "'>a  b<!--keep--></p>");
    ngx_http_trim_test_case(long_tag, long_tag, 1, 1);
    free(long_tag);
    printf("parser: %lu semantic and chunk-boundary checks passed\n", checks);
    return 0;
}
