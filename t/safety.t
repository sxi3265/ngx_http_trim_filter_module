use lib 'lib';
use Test::Nginx::Socket;

repeat_each(1);
no_shuffle();
plan 'no_plan';
run_tests();

__DATA__

=== TEST 1: preserve modern JavaScript and token boundaries
--- config
    default_type text/html;
    trim on;
    trim_js on;
--- user_files
>>> safety.html
<script>const x = `a // b ${`c ${x}`} d`;</script>
<script>var/**/x = 1;</script>
<script>return/*
*/x;</script>
<script>const r = /[/  ]x/;</script>
--- request
GET /safety.html
--- response_body
<script>const x = `a // b ${`c ${x}`} d`;</script>
<script>var/**/x = 1;</script>
<script>return/*
*/x;</script>
<script>const r = /[/  ]x/;</script>
--- no_error_log
[alert]

=== TEST 2: preserve RCDATA and raw text case insensitively
--- config
    trim on;
--- user_files
>>> safety.html
<TITLE>a <!--keep--> b</TiTlE>
<xmp>a  b<!--keep--></xmp>
<iframe>a  b<!--keep--></iframe>
<textarea>a  b<!--keep--></textarea>
--- request
GET /safety.html
--- response_body
<TITLE>a <!--keep--> b</TiTlE>
<xmp>a  b<!--keep--></xmp>
<iframe>a  b<!--keep--></iframe>
<textarea>a  b<!--keep--></textarea>

=== TEST 3: preserve whitespace controlled by inline or external CSS
--- config
    trim on;
--- user_files
>>> safety.html
<div style="white-space:pre-wrap">a  b
  c</div>
<div class=external-rule>a  b
  c</div>
<span>a</span> <span>b</span>
--- request
GET /safety.html
--- response_body
<div style="white-space:pre-wrap">a  b
  c</div>
<div class=external-rule>a  b
  c</div>
<span>a</span> <span>b</span>

=== TEST 4: weaken a static file ETag and clear range support
--- config
    trim on;
    sendfile on;
--- user_files
>>> safety.html
<p  >x</p><!--remove-->
--- request
GET /safety.html
--- response_body
<p>x</p>
--- raw_response_headers_like: (?mi)^ETag: W/"
--- response_headers
Accept-Ranges:

=== TEST 5: flush an unfinished tag at EOF
--- config
    default_type text/html;
    trim on;
    location /eof { return 200 '<p>x</p><'; }
--- request
GET /eof
--- response_body eval
'<p>x</p><'
--- no_error_log
[alert]

=== TEST 6: flush an unfinished comment at EOF
--- config
    default_type text/html;
    trim on;
    location /eof { return 200 '<p>x</p><!-'; }
--- request
GET /eof
--- response_body eval
'<p>x</p><!-'

=== TEST 7: an entirely removed body still terminates
--- config
    default_type text/html;
    trim on;
    location /empty { return 200 '<!--remove-->'; }
--- request
GET /empty
--- response_body eval
''
--- no_error_log
[alert]

=== TEST 8: safe JS and CSS separators with switches enabled
--- config
    trim on;
    trim_js on;
    trim_css on;
--- user_files
>>> safety.html
<script>var  x =  1;
return
  x;</script>
<style>.x  { color:  red; }</style>
<style>.x { --pair: a  b; }</style>
--- request
GET /safety.html
--- response_body
<script>var x = 1;
return
 x;</script>
<style>.x { color: red; }</style>
<style>.x { --pair: a  b; }</style>

=== TEST 9: preserve script escaped and double escaped data
--- config
    trim on;
    trim_js on;
--- user_files
>>> safety.html
<script><!--<script></script><!--keep--></script><p>a  b</p>
--- request
GET /safety.html
--- response_body
<script><!--<script></script><!--keep--></script><p>a  b</p>

=== TEST 10: keep foreign content and scripting dependent elements
--- config
    trim on;
--- user_files
>>> safety.html
<svg><![CDATA[a <!--keep--> b]]></svg>
<noscript><p>a  b<!--keep--></p></noscript>
--- request
GET /safety.html
--- response_body
<svg><![CDATA[a <!--keep--> b]]></svg>
<noscript><p>a  b<!--keep--></p></noscript>

=== TEST 11: preserve unquoted attribute value trailing slash
--- config
    trim on;
--- user_files
>>> safety.html
<p  a=b /><p  a=b/ ><p a=b/><p/>
--- request
GET /safety.html
--- response_body
<p a=b /><p a=b/ ><p a=b/><p/>

=== TEST 12: SSI subrequests complete without filtering twice
--- config
    default_type text/html;
    ssi on;
    trim on;
    location /part { return 200 '<span>a  b</span>'; }
--- user_files
>>> safety.html
<p  >before</p><!--# include virtual="/part" --><p>after</p>
--- request
GET /safety.html
--- response_body
<p>before</p><span>a  b</span><p>after</p>
--- no_error_log
[alert]
