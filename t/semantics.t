#!/usr/bin/perl

# Response semantics through the installed HTTP filter.

use warnings;
use strict;
use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx qw/ :DEFAULT http_content /;

my @same = (
    ['text whitespace', "<p>hello   world\r\n\t</p>"],
    ['inline CSS whitespace',
        "<div style=\"white-space:pre-wrap\">a  b\n  c</div>"],
    ['external CSS whitespace',
        "<div class=from-external-css>a  b\n  c</div>"],
    ['title', '<title>a <!--keep--> b</title>'],
    ['uppercase title', '<TITLE>a <!--keep--> b</TITLE>'],
    ['xmp', '<xmp>a  b<!--keep--></xmp>'],
    ['iframe', '<iframe>a  b<!--keep--></iframe>'],
    ['noembed', '<noembed>a  b<!--keep--></noembed>'],
    ['noframes', '<noframes>a  b<!--keep--></noframes>'],
    ['textarea', '<textarea>a  b<!--keep--></textarea>'],
    ['pre', '<pre>a  b<!--keep--></pre>'],
    ['template literal', '<script>const x = `a  b`;</script>'],
    ['template comment', '<script>const x = `a // b`;</script>'],
    ['nested template', '<script>const x = `a ${`b ${x}`} c`;</script>'],
    ['JS comment separator', '<script>var/**/x = 1;</script>'],
    ['JS multiline comment', "<script>return/*\n*/x;</script>"],
    ['JS regexp character class', '<script>const r = /[/  ]x/;</script>'],
    ['JS regexp quotes', "<script>const r = /['\"]/; var x =  1;</script>"],
    ['JS string', "<script>const s = 'a  b';</script>"],
    ['JS escaped quote', '<script>const s = "a  \"  b";</script>'],
    ['JS line terminator', "<script>return\r\nx;</script>"],
    ['JS operator separation', '<script>a + +b; a - -b;</script>'],
    ['script escaped state',
        '<script><!--<script></script><!--keep--></script><p>a  b</p>'],
    ['malformed raw end tag', "<script>x</script a\"b=\"> <!--keep--> x'>"],
    ['JSON script', '<script type=application/json>{"x":  2}</script>'],
    ['non-JS script', '<script type=text/css>.x  {color:  red}</script>'],
    ['script language', '<script language=vbscript>MsgBox  x</script>'],
    ['non-CSS style', '<style type=text/javascript>var  x</style>'],
    ['CSS custom property', '<style>.x { --pair: a  b; }</style>'],
    ['CSS custom property comment', '<style>.x { --pair: a/**/b; }</style>'],
    ['CSS calc', '<style>.x { width: calc(100% - 2px); }</style>'],
    ['CSS content', '<style>.x::before { content: "a  b"; }</style>'],
    ['CSS escaped URL', '<style>.x { background: url(a\ b); }</style>'],
    ['unfinished opener', '<p>a</p><'],
    ['unfinished comment opener', '<p>a</p><!-'],
    ['unfinished comment', '<p>a</p><!--unfinished'],
    ['unfinished raw end tag', '<script>x</scrip'],
    ['unfinished attribute', "<p title='unfinished>"],
    ['inline element separation', '<span>a</span> <span>b</span>'],
    ['unquoted slash', '<p a=b/>'],
    ['unquoted slash before space', '<p a=b/ >'],
    ['self-closing attribute', '<p a=b />'],
    ['self-closing tag', '<p/>'],
    ['SVG', '<svg><![CDATA[a <!--keep--> b]]></svg>'],
    ['MathML', '<math><annotation-xml><!--keep--></annotation-xml></math>'],
    ['noscript', '<noscript><p>a <!--keep--> b</p></noscript>'],
    ['select', '<select><style>.x  { color:  red; }</style></select>'],
    ['plaintext', '<plaintext>a <!--keep--> b'],
    ['SSI comment', '<!--# include -->'],
    ['ESI comment', '<!--esi x -->'],
    ['IE comment', '<!--[if IE]>x<![endif]-->'],
    ['hydration markers', '<!--$--><p>x</p><!--/$-->'],
    ['oversized tag', "<p title='" . ('x' x 4116) . "'>a  b<!--keep--></p>"],
);

my @cases = (
    (map { [$_->[0], $_->[1], $_->[1], ''] } @same),
    ['tag whitespace', "<p  id = 'x'  disabled >a  b</p>",
        "<p id='x' disabled>a  b</p>", ''],
    ['comment removal', 'a<!-- remove -->b', 'ab', ''],
    ['comment whitespace', 'a <!-- remove --> b', 'a  b', ''],
    ['short comment terminators', '<!-->a<!--->b<!--x--!>c', 'abc', ''],
    ['doctype', '<!DOCTYPE html><p  >x</p><!--x-->',
        '<!DOCTYPE html><p>x</p>', ''],
    ['JS separators', "<script>var  x =  1;\nreturn\n  x;</script><!--x-->",
        "<script>var x = 1;\nreturn\n x;</script>", ''],
    ['JS disabled', '<script>var  x =  1;</script>',
        '<script>var  x =  1;</script>', 'js-off/'],
    ['CSS separators', '<style>.x  { color:  red; }</style>',
        '<style>.x { color: red; }</style>', ''],
    ['CSS disabled', '<style>.x  { color:  red; }</style>',
        '<style>.x  { color:  red; }</style>', 'css-off/'],
    ['mixed case raw end tag', '<TITLE>x</TiTlE ><p  >x</p><!--x-->',
        '<TITLE>x</TiTlE ><p>x</p>', ''],
    ['raw end tag prefix', '<textarea>x</textarea-not><!--keep--></textarea><!--x-->',
        '<textarea>x</textarea-not><!--keep--></textarea>', ''],
);

my $t = Test::Nginx->new()->has(qw/http trim_filter/)->plan(2 * @cases);

$t->write_file_expand('nginx.conf', <<'EOF');
%%TEST_GLOBALS%%
daemon off;
events {}
http {
    %%TEST_GLOBALS_HTTP%%
    default_type text/html;
    server {
        listen 127.0.0.1:8080;
        trim on;
        trim_js on;
        trim_css on;
        location /js-off/ {
            trim_js off;
            alias %%TESTDIR%%/;
        }
        location /css-off/ {
            trim_css off;
            alias %%TESTDIR%%/;
        }
    }
}
EOF

for my $i (0 .. $#cases) {
    $t->write_file("case-$i.html", $cases[$i][1]);
}
$t->run();

for my $i (0 .. $#cases) {
    my ($name, undef, $expected, $prefix) = @{$cases[$i]};
    my $response = http_get("/${prefix}case-$i.html");
    like($response, qr/^HTTP\/1\.[01] 200 /, "$name status");
    is(http_content($response), $expected, "$name body");
}
