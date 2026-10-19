# Ngx_http_trim_filter module

The ngx_http_trim_filter module incrementally removes ordinary HTML comments
and redundant whitespace in tag syntax. Text, attribute values and line
terminators retain their meaning. Inline JavaScript and CSS can also have
redundant horizontal separators reduced.

The module automatically preserves content when its grammar cannot be
determined safely. Existing switches select which content to process; there
is no aggressive mode or additional safety setting.

## Example Configuration

    location / {
        trim on;
        trim_js on;
        trim_css on;
    }

## Conditional Configuration

When built with both `NGX_RESTY_EXT` and `ngx_expr_module`, `trim`, `trim_js`
and `trim_css` accept literal `on` or `off` values and can be used inside
`when` blocks at the `http`, `server` and `location` levels:

```nginx
expr compact str_eq $arg_compact 1;
when compact {
    trim on;
    trim_js on;
    trim_css on;
}
```

At each configuration level, the first matching setting is used. An
unconditional setting also matches, so place it after conditional settings
to use it as a fallback. If no setting matches, the parent setting is used.
Each switch is inherited independently, and a matching `off` disables that
switch. `trim_js` and `trim_css` take effect only when `trim` is enabled.

Variables are rejected in these builds. Without either extension,
complex values and variables retain their original behavior. `trim_types`
is unchanged.

## Directives

**trim** `on` | `off`

**Default:** `trim off`

**Context:** `http, server, location` 
     
Enable or disable HTML filtering. Text whitespace is preserved, including
whitespace affected by external CSS. Raw-text/RCDATA elements and IE/SSI/ESI
comments are protected.
Parameter value can contain variables in builds without conditional support.

Example for those builds:

    set $flag "off";
    if ($condition) {
        set $flag "on";
    }
    trim $flag;
<br/>


**trim_js** `on` | `off`

**Default:** `trim_js off`

**Context:** `http, server, location` 
     
Enable or disable reduction of repeated horizontal separators in recognized
inline JavaScript. Strings and all line terminators are preserved. Templates,
slashes and escapes automatically stop reduction for the remaining script;
comments are retained so tokens and automatic semicolon insertion are unchanged.
Parameter value can contain variables in builds without conditional support.
<br/>


**trim_css** `on` | `off`

**Default:** `trim_css off`

**Context:** `http, server, location` 
     
Enable or disable reduction of repeated horizontal separators in recognized
inline CSS. Strings are preserved. Comments, escapes and dashed names
(including custom properties) automatically preserve the remaining style body.
Parameter value can contain variables in builds without conditional support.
<br/>


**trim_types** `MIME types`

**Default:** `trim_types: text/html`

**Context:** `http, server, location`

Enable trim module for the specified MIME types in addition to "text/html". Responses with the “text/html” type are always processed.  
<br/>


## Processing rules

- HTML character data is preserved, including spaces between inline elements.
- Only validated tag syntax is compacted; quoted and unquoted attribute values
  remain unchanged. Attribute quotes and boolean values are not removed.
- Ordinary HTML comments are removed without inserting whitespace. Conditional,
  SSI/ESI and common hydration marker comments are retained.
- `title`, `textarea`, `xmp`, `iframe`, `noembed` and `noframes` bodies are
  preserved. Names and closing-tag boundaries are matched case insensitively.
- Inline JS/CSS processing never joins tokens or removes line terminators.
  Ambiguous constructs are preserved automatically, even with both switches on.
- Foreign content, tree-dependent markup and malformed structures cause
  the remaining response to pass through unchanged.
- At most 4 KiB of an unfinished tag or comment is retained. Larger tokens
  trigger pass-through. Incomplete tokens are emitted unchanged at EOF.
- Filtering weakens ETags and clears Content-Length and Accept-Ranges.
- Encoded bodies, HEAD/header-only responses, subrequests and non-200 responses
  are passed through. Main response processing remains incremental.

`trim_types` selects HTML response MIME types; it does not select a standalone
JavaScript, CSS, JSON or XML parser.

Compared with the original Tengine algorithm, text whitespace and ambiguous
script/style content may now be larger because their semantics are preserved.
Existing configuration, conditional selection and `$trim_bytes` /
`$trim_original_bytes` accounting remain supported.

## Tests

`t/trim.t` retains the original fixtures with semantics-preserving expectations.
`t/safety.t` covers the corrected response behavior with OpenResty's `test-nginx`.
Set `TEST_NGINX_EXPR=1` for conditional builds; leave it unset otherwise.
The `t/condition_trim*.t`, `t/semantics.t` and `t/stream.t` suites use the
official `nginx-tests` harness. They verify configuration, response semantics,
chunked upstream responses, incomplete tokens at EOF, early output and slow
downstream consumers through a running nginx instance.

Set `TEST_NGINX_BINARY` to the nginx binary built with this module and
`PERL5LIB` to the appropriate harness's `lib` directory. For a dynamic build,
add its `load_module` directive to `TEST_NGINX_GLOBALS` for `nginx-tests`,
or set `TEST_NGINX_LOAD_MODULES` for OpenResty's `test-nginx`.

GitHub Actions runs these suites on pushes, pull requests and manual dispatch.
The matrix builds nginx 1.31.7 with static and dynamic trim modules, plus
nginx-ext with `ngx_expr_module` for the conditional configuration tests.
Each job saves build details, dependency revisions and test logs as artifacts.
With the workflow's dependencies checked out under `.ci/`, run the same build
and tests locally with `bash util/run-tests.sh`; set `TEST_MODULE_LINK=dynamic`
for a dynamic build or `TEST_EXPR=enabled` for the nginx-ext configuration.
