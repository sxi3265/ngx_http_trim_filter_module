
/*
 *  Copyright (C) 2010-2013 Alibaba Group Holding Limited
 */


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>

#if (NGX_RESTY_EXT && NGX_EXPR) && !defined(NGX_HTTP_TRIM_TEST)
#include <ngx_http_expr_module.h>
#endif


/* Only an unfinished tag/comment is held, never an entire response. */
#define NGX_HTTP_TRIM_PENDING  4096


typedef struct {
    u_char         pending[NGX_HTTP_TRIM_PENDING];
    size_t         len;
    const char    *raw;
    size_t         raw_len;
    ngx_uint_t     state;
    ngx_uint_t     pre;
    ngx_uint_t     js;
    ngx_uint_t     css;
    ngx_uint_t     compact;
    ngx_uint_t     quote;
    ngx_uint_t     escape;
    ngx_uint_t     space;
} ngx_http_trim_parser_t;


typedef enum {
    ngx_http_trim_state_data,
    ngx_http_trim_state_open,
    ngx_http_trim_state_tag,
    ngx_http_trim_state_comment,
    ngx_http_trim_state_declaration,
    ngx_http_trim_state_raw,
    ngx_http_trim_state_raw_close,
    ngx_http_trim_state_tail,
    ngx_http_trim_state_copy
} ngx_http_trim_state_e;


static ngx_uint_t
ngx_http_trim_is_alpha(u_char c)
{
    c = ngx_tolower(c);

    return c >= 'a' && c <= 'z';
}


static ngx_uint_t
ngx_http_trim_is_space(u_char c)
{
    return c == ' ' || c == '\t' || c == '\r' || c == '\n' || c == '\f';
}


static ngx_uint_t
ngx_http_trim_equal(const u_char *s, size_t n, const char *word)
{
    size_t  i;

    if (n != ngx_strlen(word)) {
        return 0;
    }

    for (i = 0; i < n; i++) {
        if (ngx_tolower(s[i]) != (u_char) word[i]) {
            return 0;
        }
    }

    return 1;
}


/*
 * Validate the complete tag before changing it. Attribute values (including
 * entities) and their order are preserved. A malformed or oversized token
 * makes the remainder pass through: later bytes may depend on its context.
 */
static ngx_uint_t
ngx_http_trim_tag_scan(ngx_http_trim_parser_t *ctx, u_char *dst, size_t *written)
{
    const u_char  *s;
    size_t         i, j, name, end, attr, value, value_len, out;
    ngx_uint_t     closing, quote, type_seen, language_seen, compatible;

    static const char  *raw[] = {
        "script", "style", "title", "textarea", "xmp", "iframe",
        "noembed", "noframes", NULL
    };

    s = ctx->pending;
    end = ctx->len - 1;
    i = 1;
    closing = (s[i] == '/');
    i += closing;
    name = i;
    if (i == end || !ngx_http_trim_is_alpha(s[i])) {
        return 0;
    }

    while (i < end && !ngx_http_trim_is_space(s[i]) && s[i] != '/') {
        if (!ngx_http_trim_is_alpha(s[i]) && !(s[i] >= '0' && s[i] <= '9')
            && s[i] != '-' && s[i] != ':')
        {
            return 0;
        }

        i++;
    }

    name = i - name;
    ngx_memcpy(dst, s, i);
    out = i;
    type_seen = 0;
    language_seen = 0;
    compatible = 1;

    while (i < end) {
        j = i;
        while (i < end && ngx_http_trim_is_space(s[i])) {
            i++;
        }

        if (i == end) {
            break;
        }

        if (s[i] == '/' && i + 1 == end) {
            if (i > j) {
                dst[out++] = ' ';
            }

            dst[out++] = '/';
            i++;
            break;
        }

        if (i == j || closing) {
            return 0;
        }

        attr = i;
        while (i < end && !ngx_http_trim_is_space(s[i])
               && s[i] != '=' && s[i] != '/')
        {
            if (s[i] == '"' || s[i] == '\'' || s[i] == '<'
                || s[i] == '`' || s[i] == 0)
            {
                return 0;
            }

            i++;
        }

        if (attr == i) {
            return 0;
        }

        j = i;
        dst[out++] = ' ';
        ngx_memcpy(dst + out, s + attr, i - attr);
        out += i - attr;
        while (i < end && ngx_http_trim_is_space(s[i])) {
            i++;
        }

        value = i;
        value_len = 0;
        if (i < end && s[i] == '=') {
            dst[out++] = s[i++];
            while (i < end && ngx_http_trim_is_space(s[i])) {
                i++;
            }

            if (i == end) {
                return 0;
            }

            quote = s[i] == '"' || s[i] == '\'' ? s[i] : 0;
            if (quote) {
                dst[out++] = s[i++];
            }

            value = i;
            while (i < end
                   && (quote ? s[i] != quote : !ngx_http_trim_is_space(s[i])))
            {
                if (!quote && (s[i] == '"' || s[i] == '\'' || s[i] == '<'
                               || s[i] == '=' || s[i] == '`'))
                {
                    return 0;
                }

                i++;
            }

            value_len = i - value;
            if ((quote && i == end) || (!quote && value_len == 0)) {
                return 0;
            }

            ngx_memcpy(dst + out, s + value, value_len);
            out += value_len;
            if (quote) {
                dst[out++] = s[i++];
            }

            /* An unquoted value ending in '/' must stay separated from '>'. */
            if (!quote && out && dst[out - 1] == '/' && i < end) {
                dst[out++] = ' ';
            }

        } else {
            /* Leave the separator for the next attribute to validate. */
            i = j;
        }

        if (ngx_http_trim_equal(s + attr, j - attr, "type") && !type_seen) {
            type_seen = 1;

            if (value_len
                && !ngx_http_trim_equal(s + value, value_len, "text/javascript")
                && !ngx_http_trim_equal(s + value, value_len,
                                       "application/javascript")
                && !ngx_http_trim_equal(s + value, value_len, "module")
                && !ngx_http_trim_equal(s + value, value_len, "text/css"))
            {
                compatible = 0;
            }

            /* CSS is not JavaScript, nor is a JavaScript type CSS. */
            if (value_len
                && (ngx_http_trim_equal(s + 1, name, "style")
                    != ngx_http_trim_equal(s + value, value_len, "text/css")))
            {
                compatible = 0;
            }
        }

        if (ngx_http_trim_equal(s + attr, j - attr, "language")
            && !language_seen)
        {
            language_seen = 1;

            if (!ngx_http_trim_equal(s + value, value_len, "javascript")) {
                compatible = 0;
            }
        }
    }

    dst[out++] = '>';
    *written = out;
    ctx->state = ngx_http_trim_state_data;
    if (ngx_http_trim_equal(s + 1 + closing, name, "pre")) {
        if (closing) {
            if (ctx->pre) {
                ctx->pre--;
            }

        } else {
            ctx->pre++;
            if (ctx->pre == NGX_HTTP_TRIM_PENDING) {
                ctx->state = ngx_http_trim_state_copy;

                return 1;
            }
        }
    }

    if (closing) {
        return 1;
    }

    /* Foreign content and scripting-dependent HTML require a tree builder. */
    if (ngx_http_trim_equal(s + 1, name, "svg")
        || ngx_http_trim_equal(s + 1, name, "math")
        || ngx_http_trim_equal(s + 1, name, "select")
        || ngx_http_trim_equal(s + 1, name, "noscript")
        || ngx_http_trim_equal(s + 1, name, "plaintext"))
    {
        ctx->state = ngx_http_trim_state_copy;

        return 1;
    }

    for (i = 0; raw[i]; i++) {
        if (ngx_http_trim_equal(s + 1, name, raw[i])) {
            ctx->raw = raw[i];
            ctx->raw_len = name;
            ctx->state = ngx_http_trim_state_raw;
            ctx->compact = compatible
                         && ((i == 0 && ctx->js) || (i == 1 && ctx->css));
            ctx->quote = 0;
            ctx->escape = 0;
            ctx->space = 0;
            break;
        }
    }

    return 1;
}


static ngx_uint_t
ngx_http_trim_keep_comment(ngx_http_trim_parser_t *ctx)
{
    size_t  i;

    if (ctx->pre) {
        return 1;
    }

    i = 4;
    while (i < ctx->len && ngx_http_trim_is_space(ctx->pending[i])) {
        i++;
    }

    if (i == ctx->len) {
        return 1;
    }

    /* Preserve SSI/ESI, conditional comments and common hydration markers. */
    switch (ctx->pending[i]) {
    case '[':
    case '<':
    case '#':
    case '!':
    case '$':
    case '/':
        return 1;

    case 'e':
    case 'E':
        return 1;

    default:
        return 0;
    }
}


static size_t
ngx_http_trim_raw_byte(ngx_http_trim_parser_t *ctx, u_char c, u_char *dst)
{
    if (ctx->compact) {
        if (ctx->quote) {
            if (ctx->escape) {
                ctx->escape = 0;

            } else if (c == '\\') {
                ctx->escape = 1;

            } else if (c == ctx->quote) {
                ctx->quote = 0;
            }

        } else if (c == '\'' || c == '"') {
            ctx->quote = c;
            ctx->space = 0;

        } else if (c == '/' || c == '`' || c == '\\'
                   || (ctx->raw[0] == 's' && ctx->raw[1] == 't' && c == '-'))
        {
            /*
             * Preserve ambiguous JS lexical goals, templates, escapes,
             * comments, and CSS custom properties until the end tag.
             */
            ctx->compact = 0;

        } else if (c == ' ' || c == '\t') {
            if (ctx->space) {
                return 0;
            }

            ctx->space = 1;

        } else {
            /* Never remove line terminators: they carry JavaScript ASI. */
            ctx->space = 0;
        }
    }

    *dst = c;

    return 1;
}


static size_t
ngx_http_trim_parse(ngx_http_trim_parser_t *ctx, const u_char *src, size_t len,
    u_char *dst)
{
    u_char  c;
    size_t  i, n, out, written;

    out = 0;
    for (i = 0; i < len; i++) {
        c = src[i];
        if (ctx->len == NGX_HTTP_TRIM_PENDING) {
            ngx_memcpy(dst + out, ctx->pending, ctx->len);
            out += ctx->len;
            ctx->len = 0;
            ctx->state = ngx_http_trim_state_copy;
        }

        switch (ctx->state) {
        case ngx_http_trim_state_copy:
            ngx_memcpy(dst + out, src + i, len - i);

            return out + len - i;

        case ngx_http_trim_state_data:
            if (c == '<') {
                ctx->pending[ctx->len++] = c;
                ctx->state = ngx_http_trim_state_open;

            } else {
                dst[out++] = c;
            }

            break;

        case ngx_http_trim_state_open:
            ctx->pending[ctx->len++] = c;
            if (ctx->len == 2 && (ngx_http_trim_is_alpha(c) || c == '/')) {
                ctx->state = ngx_http_trim_state_tag;
                ctx->quote = 0;

            } else if (ctx->len <= 4 && c == (u_char) "<!--"[ctx->len - 1]) {
                if (ctx->len == 4) {
                    ctx->state = ngx_http_trim_state_comment;
                }

            } else if (ctx->len == 3 && ngx_tolower(c) == 'd') {
                ctx->state = ngx_http_trim_state_declaration;
                ctx->quote = 0;

            } else {
                ngx_memcpy(dst + out, ctx->pending, ctx->len);
                out += ctx->len;
                ctx->len = 0;
                ctx->state = ngx_http_trim_state_copy;
            }

            break;

        case ngx_http_trim_state_tag:
        case ngx_http_trim_state_declaration:
            ctx->pending[ctx->len++] = c;
            if (ctx->quote) {
                if (c == ctx->quote) {
                    ctx->quote = 0;
                }

            } else if (c == '\'' || c == '"') {
                ctx->quote = c;

            } else if (c == '>') {
                written = 0;
                if (ctx->state == ngx_http_trim_state_tag
                    && ngx_http_trim_tag_scan(ctx, dst + out, &written))
                {
                    out += written;

                } else {
                    ngx_memcpy(dst + out, ctx->pending, ctx->len);
                    out += ctx->len;
                    /* Only the standard HTML doctype has a known context. */
                    if (ngx_http_trim_equal(ctx->pending, ctx->len,
                                            "<!doctype html>"))
                    {
                        ctx->state = ngx_http_trim_state_data;

                    } else {
                        ctx->state = ngx_http_trim_state_copy;
                    }
                }

                ctx->len = 0;
            }

            break;

        case ngx_http_trim_state_comment:
            ctx->pending[ctx->len++] = c;
            n = ctx->len;
            if (c == '>'
                && (n == 5
                    || (n >= 6 && ctx->pending[n - 2] == '-'
                        && ctx->pending[n - 3] == '-')
                    || (n >= 7
                        && ngx_memcmp(ctx->pending + n - 4, "--!>", 4) == 0)))
            {
                if (ngx_http_trim_keep_comment(ctx)) {
                    ngx_memcpy(dst + out, ctx->pending, n);
                    out += n;
                }

                ctx->len = 0;
                ctx->state = ngx_http_trim_state_data;
            }

            break;

        case ngx_http_trim_state_raw:
            if (c == '<') {
                ctx->pending[ctx->len++] = c;
                ctx->state = ngx_http_trim_state_raw_close;

            } else {
                out += ngx_http_trim_raw_byte(ctx, c, dst + out);
            }

            break;

        case ngx_http_trim_state_raw_close:
            n = ctx->len;
            if ((n == 1 && c == '/')
                || (n >= 2 && n < ctx->raw_len + 2
                    && ngx_tolower(c) == (u_char) ctx->raw[n - 2]))
            {
                ctx->pending[ctx->len++] = c;

            } else if (n == ctx->raw_len + 2
                       && (ngx_http_trim_is_space(c) || c == '/' || c == '>'))
            {
                ngx_memcpy(dst + out, ctx->pending, n);
                out += n;
                dst[out++] = c;
                ctx->len = 0;
                ctx->quote = 0;
                ctx->state = c == '>' ? ngx_http_trim_state_data
                                   : ngx_http_trim_state_tail;

            } else {
                ngx_memcpy(dst + out, ctx->pending, n);
                out += n;
                ctx->len = 0;
                /*
                 * Script escaped states need HTML's full tokenizer.
                 * Do not reinterpret subsequent bytes as markup.
                 */
                ctx->state = ngx_strcmp(ctx->raw, "script") == 0
                           ? ngx_http_trim_state_copy : ngx_http_trim_state_raw;
                ctx->compact = 0;
                i--;
            }

            break;

        case ngx_http_trim_state_tail:
            dst[out++] = c;
            if (c == '>') {
                ctx->state = ngx_http_trim_state_data;

            } else if (!ngx_http_trim_is_space(c) && c != '/') {
                /* End-tag attributes need the full HTML tokenizer. */
                ctx->state = ngx_http_trim_state_copy;
            }

            break;
        }
    }

    return out;
}


static size_t
ngx_http_trim_finish(ngx_http_trim_parser_t *ctx, u_char *dst)
{
    size_t  n;

    n = ctx->len;
    if (n) {
        ngx_memcpy(dst, ctx->pending, n);
    }

    ctx->len = 0;
    ctx->state = ngx_http_trim_state_copy;

    return n;
}


#ifndef NGX_HTTP_TRIM_TEST


typedef struct {
    ngx_hash_t                   types;
    ngx_array_t                 *types_keys;

#if (NGX_RESTY_EXT && NGX_EXPR)
    ngx_array_t                 *js;
    ngx_array_t                 *css;
    ngx_array_t                 *trim;
#else
    ngx_http_complex_value_t    *js;
    ngx_http_complex_value_t    *css;
    ngx_http_complex_value_t    *trim;
#endif
} ngx_http_trim_loc_conf_t;


typedef struct {
    ngx_http_trim_parser_t   parser;
    ngx_chain_t             *free;
    ngx_chain_t             *busy;
    off_t                   tin;
    off_t                   tout;
} ngx_http_trim_ctx_t;


static ngx_int_t ngx_http_trim_add_variables(ngx_conf_t *cf);
static ngx_int_t ngx_http_trim_bytes_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data);
static ngx_int_t ngx_http_trim_original_bytes_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data);

static void *ngx_http_trim_create_loc_conf(ngx_conf_t *cf);
static char *ngx_http_trim_merge_loc_conf(ngx_conf_t *cf,
    void *parent, void *child);
static ngx_int_t ngx_http_trim_filter_init(ngx_conf_t *cf);


static ngx_command_t  ngx_http_trim_commands[] = {

    { ngx_string("trim"),
#if (NGX_RESTY_EXT && NGX_EXPR)
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF
      |NGX_HTTP_MAIN_WHEN_CONF|NGX_HTTP_SRV_WHEN_CONF|NGX_HTTP_LOC_WHEN_CONF
      |NGX_CONF_FLAG,
      ngx_conf_set_conditional_flag_slot,
#else
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_http_set_complex_value_slot,
#endif
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_trim_loc_conf_t, trim),
      NULL },

    { ngx_string("trim_js"),
#if (NGX_RESTY_EXT && NGX_EXPR)
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF
      |NGX_HTTP_MAIN_WHEN_CONF|NGX_HTTP_SRV_WHEN_CONF|NGX_HTTP_LOC_WHEN_CONF
      |NGX_CONF_FLAG,
      ngx_conf_set_conditional_flag_slot,
#else
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_http_set_complex_value_slot,
#endif
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_trim_loc_conf_t, js),
      NULL },

    { ngx_string("trim_css"),
#if (NGX_RESTY_EXT && NGX_EXPR)
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF
      |NGX_HTTP_MAIN_WHEN_CONF|NGX_HTTP_SRV_WHEN_CONF|NGX_HTTP_LOC_WHEN_CONF
      |NGX_CONF_FLAG,
      ngx_conf_set_conditional_flag_slot,
#else
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
      ngx_http_set_complex_value_slot,
#endif
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_trim_loc_conf_t, css),
      NULL },

    { ngx_string("trim_types"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_1MORE,
      ngx_http_types_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_trim_loc_conf_t, types_keys),
      &ngx_http_html_default_types[0] },

      ngx_null_command
};


static ngx_http_module_t  ngx_http_trim_filter_module_ctx = {
    ngx_http_trim_add_variables,             /* preconfiguration */
    ngx_http_trim_filter_init,               /* postconfiguration */

    NULL,                                    /* create main configuration */
    NULL,                                    /* init main configuration */

    NULL,                                    /* create server configuration */
    NULL,                                    /* merge server configuration */

    ngx_http_trim_create_loc_conf,           /* create location configuration */
    ngx_http_trim_merge_loc_conf             /* merge location configuration */
};


ngx_module_t  ngx_http_trim_filter_module = {
    NGX_MODULE_V1,
    &ngx_http_trim_filter_module_ctx,        /* module context */
    ngx_http_trim_commands,                  /* module directives */
    NGX_HTTP_MODULE,                         /* module type */
    NULL,                                    /* init master */
    NULL,                                    /* init module */
    NULL,                                    /* init process */
    NULL,                                    /* init thread */
    NULL,                                    /* exit thread */
    NULL,                                    /* exit process */
    NULL,                                    /* exit master */
    NGX_MODULE_V1_PADDING
};


static ngx_http_output_header_filter_pt ngx_http_next_header_filter;
static ngx_http_output_body_filter_pt   ngx_http_next_body_filter;


static ngx_http_variable_t ngx_http_trim_vars[] = {

    { ngx_string("trim_bytes"), NULL,
      ngx_http_trim_bytes_variable, 0, 0, 0 },

    { ngx_string("trim_original_bytes"), NULL,
      ngx_http_trim_original_bytes_variable, 0, 0, 0 },

    { ngx_null_string, NULL, NULL, 0, 0, 0 }
};


static ngx_int_t
ngx_http_trim_header_filter(ngx_http_request_t *r)
{
#if !(NGX_RESTY_EXT && NGX_EXPR)
    ngx_str_t                  flag;
#endif
    ngx_http_trim_ctx_t       *ctx;
    ngx_http_trim_loc_conf_t  *conf;

    conf = ngx_http_get_module_loc_conf(r, ngx_http_trim_filter_module);

#if (NGX_RESTY_EXT && NGX_EXPR)
    if (ngx_http_get_expr_flag_value(r, conf->trim) != 1
#else
    if (!conf->trim
#endif
        || r->headers_out.status != NGX_HTTP_OK
        || r->header_only
        || (r->method & NGX_HTTP_HEAD)
        || r != r->main
        || r->headers_out.content_length_n == 0
        || (r->headers_out.content_encoding
            && r->headers_out.content_encoding->value.len)
        || ngx_http_test_content_type(r, &conf->types) == NULL)
    {
        return ngx_http_next_header_filter(r);
    }

#if !(NGX_RESTY_EXT && NGX_EXPR)
    if (ngx_http_complex_value(r, conf->trim, &flag) != NGX_OK) {
        return NGX_ERROR;
    }

    if (!(flag.len == sizeof("on") - 1
          && ngx_strncmp(flag.data, "on", sizeof("on") - 1) == 0))
    {
        return ngx_http_next_header_filter(r);
    }
#endif

    ctx = ngx_pcalloc(r->pool, sizeof(ngx_http_trim_ctx_t));
    if (ctx == NULL) {
        return NGX_ERROR;
    }

#if (NGX_RESTY_EXT && NGX_EXPR)
    ctx->parser.js = (ngx_http_get_expr_flag_value(r, conf->js) == 1);
    ctx->parser.css = (ngx_http_get_expr_flag_value(r, conf->css) == 1);
#else
    if (conf->js) {
        if (ngx_http_complex_value(r, conf->js, &flag) != NGX_OK) {
            return NGX_ERROR;
        }

        if (flag.len == sizeof("on") - 1
            && ngx_strncmp(flag.data, "on", sizeof("on") - 1) == 0)
        {
            ctx->parser.js = 1;
        }
    }

    if (conf->css) {
        if (ngx_http_complex_value(r, conf->css, &flag) != NGX_OK) {
            return NGX_ERROR;
        }

        if (flag.len == sizeof("on") - 1
            && ngx_strncmp(flag.data, "on", sizeof("on") - 1) == 0)
        {
            ctx->parser.css = 1;
        }
    }
#endif

    ngx_http_set_ctx(r, ctx, ngx_http_trim_filter_module);

    r->main_filter_need_in_memory = 1;

    ngx_http_clear_content_length(r);
    ngx_http_clear_accept_ranges(r);
    ngx_http_weak_etag(r);

    return ngx_http_next_header_filter(r);
}


/* Release a producer buffer only after its derived output was consumed. */
static void
ngx_http_trim_consume(ngx_chain_t *in)
{
    ngx_buf_t  *b;

    for ( ; in; in = in->next) {
        b = in->buf;
        if (ngx_buf_size(b) != 0) {
            break;
        }

        if (b->shadow) {
            b->shadow->pos = b->shadow->last;
            if (b->shadow->in_file) {
                b->shadow->file_pos = b->shadow->file_last;
            }
            b->shadow = NULL;
        }
    }
}


static ngx_int_t
ngx_http_trim_body_filter(ngx_http_request_t *r, ngx_chain_t *in)
{
    size_t                len, size, n;
    u_char               *start, *end;
    ngx_int_t             rc;
    ngx_buf_t            *b, *src;
    ngx_chain_t          *cl, *ln, *out, **ll;
    ngx_http_trim_ctx_t   *ctx;

    ctx = ngx_http_get_module_ctx(r, ngx_http_trim_filter_module);
    if (ctx == NULL) {
        return ngx_http_next_body_filter(r, in);
    }

    out = NULL;
    ll = &out;

    for (ln = in; ln; ln = ln->next) {
        src = ln->buf;
        len = ngx_buf_in_memory(src) ? (size_t) (src->last - src->pos) : 0;

        /* The copy filter must materialize file buffers before we parse. */
        if (src->in_file && !ngx_buf_in_memory(src) && ngx_buf_size(src)) {
            ngx_log_error(NGX_LOG_ALERT, r->connection->log, 0,
                          "trim received a file buffer without memory");
            return NGX_ERROR;
        }

        size = len + ctx->parser.len;
        if (size < len) {
            return NGX_ERROR;
        }
        if (size && size < 2 * NGX_HTTP_TRIM_PENDING) {
            size = 2 * NGX_HTTP_TRIM_PENDING;
        }

        cl = ngx_chain_get_free_buf(r->pool, &ctx->free);
        if (cl == NULL) {
            return NGX_ERROR;
        }
        b = cl->buf;
        start = b->start;
        end = b->end;
        if (size && (start == NULL || (size_t) (end - start) < size)) {
            /*
             * Free a reusable large allocation rather than retaining every
             * old capacity until the request pool is destroyed.
             */
            if (start) {
                (void) ngx_pfree(r->pool, start);
            }
            start = ngx_pnalloc(r->pool, size);
            if (start == NULL) {
                return NGX_ERROR;
            }
            end = start + size;
        }

        ngx_memzero(b, sizeof(ngx_buf_t));
        b->start = start;
        b->end = end;
        b->pos = start;
        b->last = start;
        b->tag = (ngx_buf_tag_t) &ngx_http_trim_filter_module;
        b->flush = src->flush;
        b->sync = src->sync;
        b->last_buf = src->last_buf;
        b->last_in_chain = src->last_in_chain;

        n = 0;
        if (len) {
            n = ngx_http_trim_parse(&ctx->parser, src->pos, len, start);
        }
        if (src->last_buf && ctx->parser.len) {
            n += ngx_http_trim_finish(&ctx->parser, start + n);
        }

        ctx->tin += len;
        ctx->tout += n;

        if (n) {
            b->last = start + n;
            b->temporary = 1;
            b->shadow = src;
            b->last_shadow = 1;
        } else {
            /*
             * The parser owns any unfinished prefix, so the producer can
             * refill its input even when no output has been generated.
             */
            src->pos = src->last;
            if (src->in_file) {
                src->file_pos = src->file_last;
            }
            b->sync = 1;
        }

        cl->next = NULL;
        *ll = cl;
        ll = &cl->next;
    }

    rc = ngx_http_next_body_filter(r, out);

    ngx_http_trim_consume(ctx->busy);
    ngx_http_trim_consume(out);
    ngx_chain_update_chains(r->pool, &ctx->free, &ctx->busy, &out,
                           (ngx_buf_tag_t) &ngx_http_trim_filter_module);

    return rc;
}


static ngx_int_t
ngx_http_trim_add_variables(ngx_conf_t *cf)
{
    ngx_http_variable_t   *var, *v;

    for (v = ngx_http_trim_vars; v->name.len; v++) {
        var = ngx_http_add_variable(cf, &v->name, v->flags);
        if (var == NULL) {
            return NGX_ERROR;
        }

        var->get_handler = v->get_handler;
        var->data = v->data;
    }

    return NGX_OK;
}


static ngx_int_t
ngx_http_trim_bytes_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data)
{
    ngx_http_trim_ctx_t   *ctx;

    ctx = ngx_http_get_module_ctx(r, ngx_http_trim_filter_module);

    if (ctx == NULL) {
        v->not_found = 1;
        return NGX_OK;
    }

    v->data = ngx_pnalloc(r->pool, NGX_OFF_T_LEN);
    if (v->data == NULL) {
        return NGX_ERROR;
    }

    v->len = ngx_sprintf(v->data, "%O", ctx->tin - ctx->tout) - v->data;
    v->valid = 1;
    v->no_cacheable = 0;
    v->not_found = 0;

    return NGX_OK;
}


static ngx_int_t
ngx_http_trim_original_bytes_variable(ngx_http_request_t *r,
    ngx_http_variable_value_t *v, uintptr_t data)
{
    ngx_http_trim_ctx_t   *ctx;

    ctx = ngx_http_get_module_ctx(r, ngx_http_trim_filter_module);

    if (ctx == NULL) {
        v->not_found = 1;
        return NGX_OK;
    }

    v->data = ngx_pnalloc(r->pool, NGX_OFF_T_LEN);
    if (v->data == NULL) {
        return NGX_ERROR;
    }

    v->len = ngx_sprintf(v->data, "%O", ctx->tin) - v->data;
    v->valid = 1;
    v->no_cacheable = 0;
    v->not_found = 0;

    return NGX_OK;
}


static void *
ngx_http_trim_create_loc_conf(ngx_conf_t *cf)
{
    ngx_http_trim_loc_conf_t *conf;

    conf = ngx_pcalloc(cf->pool, sizeof(ngx_http_trim_loc_conf_t));
    if (conf == NULL) {
        return NULL;
    }

    /*
     * set by ngx_pcalloc():
     *
     *     conf->types = { NULL };
     *     conf->types_keys = NULL;
     *     conf->trim = NULL;
     *     conf->js = NULL;
     *     conf->css = NULL;
     */

#if (NGX_RESTY_EXT && NGX_EXPR)
    conf->trim = NGX_CONF_UNSET_PTR;
    conf->js = NGX_CONF_UNSET_PTR;
    conf->css = NGX_CONF_UNSET_PTR;
#endif

    return conf;
}

static char *
ngx_http_trim_merge_loc_conf(ngx_conf_t *cf, void *parent, void *child)
{
    ngx_http_trim_loc_conf_t *prev = parent;
    ngx_http_trim_loc_conf_t *conf = child;

    if (ngx_http_merge_types(cf, &conf->types_keys, &conf->types,
                             &prev->types_keys, &prev->types,
                             ngx_http_html_default_types)
        != NGX_OK)
    {
        return NGX_CONF_ERROR;
    }

#if (NGX_RESTY_EXT && NGX_EXPR)
    if (ngx_conf_merge_expr_flag_value(cf, &conf->trim, prev->trim, 0) != NGX_OK
        || ngx_conf_merge_expr_flag_value(cf, &conf->js, prev->js, 0) != NGX_OK
        || ngx_conf_merge_expr_flag_value(cf, &conf->css, prev->css, 0) != NGX_OK)
    {
        return NGX_CONF_ERROR;
    }
#else
    if (conf->trim == NULL) {
        conf->trim = prev->trim;
    }

    if (conf->js == NULL) {
        conf->js = prev->js;
    }

    if (conf->css == NULL) {
        conf->css = prev->css;
    }
#endif

    return NGX_CONF_OK;
}


static ngx_int_t
ngx_http_trim_filter_init(ngx_conf_t *cf)
{
    ngx_http_next_header_filter = ngx_http_top_header_filter;
    ngx_http_top_header_filter = ngx_http_trim_header_filter;

    ngx_http_next_body_filter = ngx_http_top_body_filter;
    ngx_http_top_body_filter = ngx_http_trim_body_filter;

    return NGX_OK;
}

#endif /* NGX_HTTP_TRIM_TEST */
