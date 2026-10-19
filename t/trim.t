use lib 'lib';
use Test::Nginx::Socket;

log_level('debug');
plan tests => 2 * blocks();

$ENV{TEST_NGINX_TRIM_PORT} ||= "1984";

run_tests();

# etcproxy 1986 1984
# TEST_NGINX_TRIM_PORT=1986 prove ../cases/trim.t

__DATA__

=== TEST 1: do not trim within 'textarea' 'pre' 'ie-comment'
--- config
    trim on;
    trim_js on;
    trim_css on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html
<!DOCTYPE html>
<textarea>
   hello
        world!
</textarea>

     <pre>
  hello     world!
    </pre>

<!--[if IE]> hello    world    ! <![endif]-->
    <!-- hello     world   ! -->
<!--[if !IE ]>--> hello    world  ! <!--<![endif]-->
--- request
    GET /t/trim.html
--- response_body eval
"<!DOCTYPE html>\n"
. "<textarea>\n"
. "   hello\n"
. "        world!\n"
. "</textarea>\n"
. "\n"
. "     <pre>\n"
. "  hello     world!\n"
. "    </pre>\n"
. "\n"
. "<!--[if IE]> hello    world    ! <![endif]-->\n"
. "    \n"
. "<!--[if !IE ]>--> hello    world  ! <!--<![endif]-->\n"

=== TEST 2: preserve text whitespace in ordinary tags
--- config
    trim on;
    trim_js on;
    trim_css on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html
<!DOCTYPE html>
<body>hello   world,   it
is good  to     see you   </body>

<body>hello   world,   it
     is good  to     see you   </body>
--- request
    GET /t/trim.html
--- response_body eval
"<!DOCTYPE html>\n"
. "<body>hello   world,   it\n"
. "is good  to     see you   </body>\n"
. "\n"
. "<body>hello   world,   it\n"
. "     is good  to     see you   </body>\n"

=== TEST 3: trim within non-ie comment
--- config
    trim on;
    trim_js on;
    trim_css on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html
<!DOCTYPE html>
<body>hello <!--world--></body>
<!--[if IE]> hello    world    ! <![endif]-->
   <!-- hello world! -->
<!--[if !IE ]>--> hello    world  ! <!--<![endif]-->

--- request
    GET /t/trim.html
--- response_body eval
"<!DOCTYPE html>\n"
. "<body>hello </body>\n"
. "<!--[if IE]> hello    world    ! <![endif]-->\n"
. "   \n"
. "<!--[if !IE ]>--> hello    world  ! <!--<![endif]-->\n"

=== TEST 4: do not trim within tag quote
--- config
    trim on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html
<!DOCTYPE html>
<body
  style="text-align:   center;">hello   world,   it
   is good  to     see you   </body>
--- request
    GET /t/trim.html
--- response_body eval
"<!DOCTYPE html>\n"
. "<body style=\"text-align:   center;\">hello   world,   it\n"
. "   is good  to     see you   </body>\n"

=== TEST 5: preserve newlines and remove ordinary comments
--- config
    trim on;
    trim_js on;
    trim_css on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html



<!DOCTYPE html>

<html>


<body>hello   world!<body>         
   <!-- --->
         <html>


   

                  
--- request
    GET /t/trim.html
--- response_body eval
"\n"
. "\n"
. "\n"
. "<!DOCTYPE html>\n"
. "\n"
. "<html>\n"
. "\n"
. "\n"
. "<body>hello   world!<body>         \n"
. "   \n"
. "         <html>\n"

=== TEST 6: return zero size 
--- config
    trim on;
    trim_js on;
    trim_css on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html


--- request
    GET /t/trim.html
--- response_body eval
''

=== TEST 7: preserve malformed markup
--- config
    trim on;
    trim_js on;
    trim_css on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html
<!DOCTYPE html>
<      <PRE>hello     world  ! </pre>
<2     <pre>hello     world  ! </pre>
<<<    <pre>hello     world  ! </pre>
<   <  <pre>hello     world  ! </pre>
<     <<pre>hello     world  ! </pre>
<x    <<pre>hello     world  ! </pre>
<     <<<!doctype   html>
                  
--- request
    GET /t/trim.html
--- response_body eval
"<!DOCTYPE html>\n"
. "<      <PRE>hello     world  ! </pre>\n"
. "<2     <pre>hello     world  ! </pre>\n"
. "<<<    <pre>hello     world  ! </pre>\n"
. "<   <  <pre>hello     world  ! </pre>\n"
. "<     <<pre>hello     world  ! </pre>\n"
. "<x    <<pre>hello     world  ! </pre>\n"
. "<     <<<!doctype   html>\n"

=== TEST 8: preserve Chinese title text and spacing
--- config
    trim on;
    trim_js on;
    trim_css on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html
<title>世界      你好  !</title>
                  
--- request
    GET /t/trim.html
--- response_body eval
"<title>世界      你好  !</title>\n"

=== TEST 9: sendfile on
--- config
    sendfile on;
    trim on;
    trim_js on;
    trim_css on;
--- user_files
>>> trim.html
<!DOCTYPE html>
<body>hello   world,   it
   is good  to     see you   </body>
<!-- trimoff -->
--- request
    GET /trim.html
--- response_body eval
"<!DOCTYPE html>\n"
. "<body>hello   world,   it\n"
. "   is good  to     see you   </body>\n"
. "\n"

=== TEST 10: http_trim query parameter does not disable configured trim
--- config
    trim on;
    trim_js on;
    trim_css on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html
<!DOCTYPE html>
<body>hello   world,   it
   is good  to     see you   </body>
<!-- trimoff -->
--- request
    GET /t/trim.html?http_trim=off&hello=world
--- response_body eval
"<!DOCTYPE html>\n"
. "<body>hello   world,   it\n"
. "   is good  to     see you   </body>\n"
. "\n"

=== TEST 11: preserve JavaScript comments and token boundaries
--- config
    trim on;
    trim_js on;
    trim_css on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html
<!DOCTYPE html>
<script>
//// single comment
document.write("hello world");
</script>
<script type="text/javascript">
/***  muitl comment 
      !             ***/
</script>
<script type="text/vbscript">
/* no javscript code !*/
</script>
--- request
    GET /t/trim.html
--- response_body eval
"<!DOCTYPE html>\n"
. "<script>\n"
. "//// single comment\n"
. "document.write(\"hello world\");\n"
. "</script>\n"
. "<script type=\"text/javascript\">\n"
. "/***  muitl comment \n"
. "      !             ***/\n"
. "</script>\n"
. "<script type=\"text/vbscript\">\n"
. "/* no javscript code !*/\n"
. "</script>\n"

=== TEST 12: do not tirm javascript quote and RE 
--- config
    trim on;
    trim_js on;
    trim_css on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html
<!DOCTYPE html>
<script>
document.write("hello      world");
document.write("hello  \"  world");
var reg=/hello  \/   world /g;
var reg=  /hello  \/   world /g;
str.replace(/    /,"hello");
str.replace(  /    /,"hello");
</script>

--- request
    GET /t/trim.html
--- response_body eval
"<!DOCTYPE html>\n"
. "<script>\n"
. "document.write(\"hello      world\");\n"
. "document.write(\"hello  \\\"  world\");\n"
. "var reg=/hello  \\/   world /g;\n"
. "var reg=  /hello  \\/   world /g;\n"
. "str.replace(/    /,\"hello\");\n"
. "str.replace(  /    /,\"hello\");\n"
. "</script>\n"

=== TEST 13: preserve CSS comments and token boundaries
--- config
    trim on;
    trim_js on;
    trim_css on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html
<!DOCTYPE html>
<style type="text/css">
/*** css comment
                 ! ***/
body {
     background-color: black;
     }
</style>
--- request
    GET /t/trim.html
--- response_body eval
"<!DOCTYPE html>\n"
. "<style type=\"text/css\">\n"
. "/*** css comment\n"
. "                 ! ***/\n"
. "body {\n"
. "     background-color: black;\n"
. "     }\n"
. "</style>\n"

=== TEST 14: do not trim css quote
--- config
    trim on;
    trim_js on;
    trim_css on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html
<!DOCTYPE html>
<style type="text/css">
"hello      world");
"hello  \"  world");
"hello  \\\"  world");
</style>
--- request
    GET /t/trim.html
--- response_body eval
"<!DOCTYPE html>\n"
. "<style type=\"text/css\">\n"
. "\"hello      world\");\n"
. "\"hello  \\\"  world\");\n"
. "\"hello  \\\\\\\"  world\");\n"
. "</style>\n"

=== TEST 15 trim aplus.js
--- config
    trim on;
    trim_js on;
    trim_css on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html
<!DOCTYPE html>
<script type="text/javascript">
(function (d) {
var t=d.createElement("script");t.type="text/javascript";t.async=true;t.id="tb-beacon-aplus";
t.setAttribute("exparams","category=&userid=&aplus");
t.src=("https:"==d.location.protocol?"https://s":"http://a")+".tbcdn.cn/s/aplus_v2.js";
d.getElementsByTagName("head")[0].appendChild(t);
})(document);
</script>

--- request
    GET /t/trim.html
--- response_body eval
"<!DOCTYPE html>\n"
. "<script type=\"text/javascript\">\n"
. "(function (d) {\n"
. "var t=d.createElement(\"script\");t.type=\"text/javascript\";t.async=true;t.id=\"tb-beacon-aplus\";\n"
. "t.setAttribute(\"exparams\",\"category=&userid=&aplus\");\n"
. "t.src=(\"https:\"==d.location.protocol?\"https://s\":\"http://a\")+\".tbcdn.cn/s/aplus_v2.js\";\n"
. "d.getElementsByTagName(\"head\")[0].appendChild(t);\n"
. "})(document);\n"
. "</script>\n"

=== TEST 16: preserve CSS child selector hack comments
--- config
    trim on;
    trim_js on;
    trim_css on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html
<!DOCTYPE html>
<style type="text/css">
html >/**/ body p {
    color: blue;
}
</style>
--- request
    GET /t/trim.html
--- response_body eval
"<!DOCTYPE html>\n"
. "<style type=\"text/css\">\n"
. "html >/**/ body p {\n"
. "    color: blue;\n"
. "}\n"
. "</style>\n"

=== TEST 17: preserve CSS IE5/Mac hack comments
--- config
    trim on;
    trim_js on;
    trim_css on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html
<!DOCTYPE html>
<style type="text/css">
/* Ignore the next rule in IE mac \*/
.selector {
    color: khaki;
}
/* Stop ignoring in IE mac */
</style>
--- request
    GET /t/trim.html
--- response_body eval
"<!DOCTYPE html>\n"
. "<style type=\"text/css\">\n"
. "/* Ignore the next rule in IE mac \\*/\n"
. ".selector {\n"
. "    color: khaki;\n"
. "}\n"
. "/* Stop ignoring in IE mac */\n"
. "</style>\n"

=== TEST 18: comment of javascript
--- config
    trim on;
    trim_js on;
    trim_css on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html
<!DOCTYPE html>
<script type="text/javascript">// <![CDATA[
   return   true;
// ]]></script  ></head><body id="loginform"><div id="page_content">
--- request
    GET /t/trim.html
--- response_body eval
"<!DOCTYPE html>\n"
. "<script type=\"text/javascript\">// <![CDATA[\n"
. "   return   true;\n"
. "// ]]></script  ></head><body id=\"loginform\"><div id=\"page_content\">\n"

=== TEST 19: do not trim html comment of ssi/esi
--- config
    trim on;
    trim_js on;
    trim_css on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html
<!DOCTYPE html>
<!-- hello -->
<!--# ssi  -->
<!--esi    -->
<!-- world -->
<!---->
<!--e    -->
<!-------->
<!--[if  ie  <![endif]-->
--- request
    GET /t/trim.html
--- response_body eval
"<!DOCTYPE html>\n"
. "\n"
. "<!--# ssi  -->\n"
. "<!--esi    -->\n"
. "\n"
. "\n"
. "<!--e    -->\n"
. "\n"
. "<!--[if  ie  <![endif]-->\n"

=== TEST 20: trim tag
--- config
    trim on;
    trim_js on;
    trim_css on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html
<!DOCTYPE html>
<html>
<head>
<title    >Welcome to nginx!</title    >
<script       language="JavaScript"     type="   text/javascript"    >
    // comment </script  > <p> hello    world
<style    type="text/css"  language="css"   >
   /*     */
</style      >
</head>
<body>
<pre    style="color:blue">Welcome    to    nginx!</pre  >
<pre >Welcome    to    nginx!</pre>
<textarea    style="color:blue">Welcome    to    nginx!</textarea  >
<textarea >Welcome    to    nginx!</textarea>
<!-- hello world -->
</body>
</html>
--- request
    GET /t/trim.html
--- response_body eval
"<!DOCTYPE html>\n"
. "<html>\n"
. "<head>\n"
. "<title>Welcome to nginx!</title    >\n"
. "<script language=\"JavaScript\" type=\"   text/javascript\">\n"
. "    // comment </script  > <p> hello    world\n"
. "<style type=\"text/css\" language=\"css\">\n"
. "   /*     */\n"
. "</style      >\n"
. "</head>\n"
. "<body>\n"
. "<pre style=\"color:blue\">Welcome    to    nginx!</pre>\n"
. "<pre>Welcome    to    nginx!</pre>\n"
. "<textarea style=\"color:blue\">Welcome    to    nginx!</textarea  >\n"
. "<textarea>Welcome    to    nginx!</textarea>\n"
. "\n"
. "</body>\n"
. "</html>\n"

=== TEST 21: nest pre
--- config
    trim on;
    trim_js on;
    trim_css on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html
<!DOCTYPE html>
<pre    style="color:black">
a     a

<pre    style="color:blue"  >
b     b

<pre   style  =  "color:  red"   >
d     d

</pre    >

c     c

</pre   >


</pre     >

f     f
--- request
    GET /t/trim.html
--- response_body eval
"<!DOCTYPE html>\n"
. "<pre style=\"color:black\">\n"
. "a     a\n"
. "\n"
. "<pre style=\"color:blue\">\n"
. "b     b\n"
. "\n"
. "<pre style=\"color:  red\">\n"
. "d     d\n"
. "\n"
. "</pre>\n"
. "\n"
. "c     c\n"
. "\n"
. "</pre>\n"
. "\n"
. "\n"
. "</pre>\n"
. "\n"
. "f     f\n"

=== TEST 22: trim_js off
--- config
    trim on;
    trim_js off;
    trim_css on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html
<!DOCTYPE html>
<html>
<head>
<title    >Welcome to nginx!</title    >
<script       language="JavaScript"     type="   text/javascript"    >
    // comment </script  > <p> hello    world
<style    type="text/css"  language="css"   >
   /*     */
</style      >
</head>
--- request
    GET /t/trim.html
--- response_body eval
"<!DOCTYPE html>\n"
. "<html>\n"
. "<head>\n"
. "<title>Welcome to nginx!</title    >\n"
. "<script language=\"JavaScript\" type=\"   text/javascript\">\n"
. "    // comment </script  > <p> hello    world\n"
. "<style type=\"text/css\" language=\"css\">\n"
. "   /*     */\n"
. "</style      >\n"
. "</head>\n"

=== TEST 23: trim_css off
--- config
    trim on;
    trim_js on;
    trim_css off;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html
<!DOCTYPE html>
<html>
<head>
<title    >Welcome to nginx!</title    >
<script       language="JavaScript"     type="   text/javascript"    >
    // comment </script  > <p> hello    world
<style    type="text/css"  language="css"   >
   /*     */
</style      >
</head>
--- request
    GET /t/trim.html
--- response_body eval
"<!DOCTYPE html>\n"
. "<html>\n"
. "<head>\n"
. "<title>Welcome to nginx!</title    >\n"
. "<script language=\"JavaScript\" type=\"   text/javascript\">\n"
. "    // comment </script  > <p> hello    world\n"
. "<style type=\"text/css\" language=\"css\">\n"
. "   /*     */\n"
. "</style      >\n"
. "</head>\n"

=== TEST 24: trim_js off and trim_css off
--- config
    trim on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html
<!DOCTYPE html>
<html>
<head>
<title    >Welcome to nginx!</title    >
<script       language="JavaScript"     type="   text/javascript"    >
    // comment </script  > <p> hello    world
<style    type="text/css"  language="css"   >
   /*     */
</style      >
</head>
--- request
    GET /t/trim.html
--- response_body eval
"<!DOCTYPE html>\n"
. "<html>\n"
. "<head>\n"
. "<title>Welcome to nginx!</title    >\n"
. "<script language=\"JavaScript\" type=\"   text/javascript\">\n"
. "    // comment </script  > <p> hello    world\n"
. "<style type=\"text/css\" language=\"css\">\n"
. "   /*     */\n"
. "</style      >\n"
. "</head>\n"

=== TEST 25:  remove space around '=' in tag
--- config
    trim on;
    trim_js on;
    trim_css on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html
<!DOCTYPE html>
<html>
<head>
<title    >Welcome to nginx!</title    >
<script    language  =  "JavaScript"     type=   "   text/javascript"    >
    // comment </script  > <p> hello    world
<style    type   ="text/css"  language  ="css"   >
   /*     */
</style      >
</head>
<pre    style  =  "color:blue"  >Welcome    to    nginx!</pre  >
<pre    style= 
 "color:blue"  >Welcome    to    nginx!</pre  >
<textarea   style 
  ="color:blue">Welcome    to    nginx!</textarea  >
--- request
    GET /t/trim.html
--- response_body eval
"<!DOCTYPE html>\n"
. "<html>\n"
. "<head>\n"
. "<title>Welcome to nginx!</title    >\n"
. "<script language=\"JavaScript\" type=\"   text/javascript\">\n"
. "    // comment </script  > <p> hello    world\n"
. "<style type=\"text/css\" language=\"css\">\n"
. "   /*     */\n"
. "</style      >\n"
. "</head>\n"
. "<pre style=\"color:blue\">Welcome    to    nginx!</pre>\n"
. "<pre style=\"color:blue\">Welcome    to    nginx!</pre>\n"
. "<textarea style=\"color:blue\">Welcome    to    nginx!</textarea  >\n"

=== TEST 26: trim css
--- config
    trim on;
    trim_js on;
    trim_css on;
    location /t/ { proxy_buffering off; proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;}
    location /trim.html { trim off;}
--- user_files
>>> trim.html
<style>
body{font-size:20px;line-height:150%;}
body { font-size:20px; line-height:150%; }
body { font-size : 20px ; line-height : 150%; }
body
{
  font-size:  20px;
  line-height: 150%;
}


h1 > strong {  color : red  ; }
.skin-1388458850088 .nav .sm-item-list {
  border-bottom: 2px solid #ee5e80;
}
.skin-1388458850088 .nav .search-wrap a.local,
.skin-1388458850088 .nav .search-wrap a.local:hover {
  background: #ee5e80;
}
</style>
--- request
    GET /t/trim.html
--- response_body eval
"<style>\n"
. "body{font-size:20px;line-height:150%;}\n"
. "body { font-size:20px; line-height:150%; }\n"
. "body { font-size : 20px ; line-height : 150%; }\n"
. "body\n"
. "{\n"
. "  font-size:  20px;\n"
. "  line-height: 150%;\n"
. "}\n"
. "\n"
. "\n"
. "h1 > strong {  color : red  ; }\n"
. ".skin-1388458850088 .nav .sm-item-list {\n"
. "  border-bottom: 2px solid #ee5e80;\n"
. "}\n"
. ".skin-1388458850088 .nav .search-wrap a.local,\n"
. ".skin-1388458850088 .nav .search-wrap a.local:hover {\n"
. "  background: #ee5e80;\n"
. "}\n"
. "</style>\n"

=== TEST 27: conditional switches or variable value
--- config eval
$ENV{TEST_NGINX_EXPR} ? <<'EXPR_CONFIG' : <<'LEGACY_CONFIG';
    trim on;
    trim_js on;
    trim_css on;
    expr trim_disabled str_eq $arg_a 1;
    location /trim.html { trim off; }
    location /t/ {
        proxy_buffering off;
        proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;
        when trim_disabled {
            trim_js off;
            trim_css off;
        }
    }
EXPR_CONFIG
    trim on;
    trim_js on;
    trim_css on;
    set $trim "on";
    if ($arg_a = 1 ) {
        set $trim "off";
    }
    location /trim.html {trim off; }
    location /t/ {
        proxy_buffering off;
        proxy_pass http://127.0.0.1:$TEST_NGINX_TRIM_PORT/;

        trim_js $trim;
        trim_css $trim;
    }
LEGACY_CONFIG
--- user_files
>>> trim.html
<!DOCTYPE html>
<textarea  >
   trim
        module
</textarea  >
<!--remove all-->
<!--[if IE]> trim module <![endif]-->
<!--[if !IE ]>--> trim module  <!--<![endif]-->
<!--# ssi-->
<!--esi-->
<pre    style  =
    "color:   blue"  >Welcome    to    nginx!</pre  >
<script type="text/javascript">
/***  muitl comment
                   ***/
//// single comment
str.replace(/     /,"hello");
</script>
<style   type="text/css"  >
/*** css comment
                 ! ***/
body
{
  font-size:  20px ;
  line-height: 150% ;
}
</style>
--- request
    GET /t/trim.html?a=1
--- response_body eval
"<!DOCTYPE html>\n"
. "<textarea>\n"
. "   trim\n"
. "        module\n"
. "</textarea  >\n"
. "\n"
. "<!--[if IE]> trim module <![endif]-->\n"
. "<!--[if !IE ]>--> trim module  <!--<![endif]-->\n"
. "<!--# ssi-->\n"
. "<!--esi-->\n"
. "<pre style=\"color:   blue\">Welcome    to    nginx!</pre>\n"
. "<script type=\"text/javascript\">\n"
. "/***  muitl comment\n"
. "                   ***/\n"
. "//// single comment\n"
. "str.replace(/     /,\"hello\");\n"
. "</script>\n"
. "<style type=\"text/css\">\n"
. "/*** css comment\n"
. "                 ! ***/\n"
. "body\n"
. "{\n"
. "  font-size:  20px ;\n"
. "  line-height: 150% ;\n"
. "}\n"
. "</style>\n"

