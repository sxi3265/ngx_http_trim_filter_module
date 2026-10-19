#!/usr/bin/env bash

set -euo pipefail

module_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
nginx_source="$module_root/.ci/nginx"
test_output="$module_root/.ci/test-output"
build_jobs="${TEST_BUILD_JOBS:-$(getconf _NPROCESSORS_ONLN)}"
expr="${TEST_EXPR:-disabled}"
link="${TEST_MODULE_LINK:-static}"

mkdir -p "$test_output"
exec > >(tee "$test_output/run.log") 2>&1
trap 'rc=$?; printf "%s\n" "$rc" > "$test_output/exit-code"' EXIT

case "$expr" in enabled|disabled) ;; *) echo 'Invalid TEST_EXPR' >&2; exit 1 ;; esac
case "$link" in static|dynamic) ;; *) echo 'Invalid TEST_MODULE_LINK' >&2; exit 1 ;; esac

for dependency in nginx nginx-tests test-nginx; do
    revision="$(git -C "$module_root/.ci/$dependency" rev-parse HEAD)"
    printf '%s %s\n' "$dependency" "$revision"
done > "$test_output/dependencies.txt"

configure_args=(
    --prefix="$nginx_source/test-prefix"
    --with-debug
    --with-http_ssl_module
    --with-http_v2_module
)

export TEST_NGINX_EXPR=0
if [[ "$expr" == enabled ]]; then
    configure_args+=(--with-http_json_module)
    configure_args+=(--add-module="$module_root/.ci/ngx_expr_module")
    revision="$(git -C "$module_root/.ci/ngx_expr_module" rev-parse HEAD)"
    printf 'ngx_expr_module %s\n' "$revision" >> "$test_output/dependencies.txt"
    export TEST_NGINX_EXPR=1
fi

if [[ "$link" == dynamic ]]; then
    configure_args+=(--with-compat --add-dynamic-module="$module_root")
else
    configure_args+=(--add-module="$module_root")
fi

cd "$nginx_source"
if [[ -f configure ]]; then
    sh ./configure "${configure_args[@]}"
else
    sh auto/configure "${configure_args[@]}"
fi
if [[ "$expr" == enabled ]]; then
    grep -q '^#define NGX_EXPR  *1$' objs/ngx_auto_config.h
    grep -q '^#define NGX_RESTY_EXT  *1$' objs/ngx_auto_config.h
fi
make -j"$build_jobs"

export TEST_NGINX_BINARY="$nginx_source/objs/nginx"
export TEST_NGINX_LEAVE=1
export TMPDIR="$test_output/tmp"
export TEST_NGINX_SERVROOT="$test_output/servroot"
mkdir -p "$TMPDIR"
"$TEST_NGINX_BINARY" -V 2> "$test_output/nginx-build.txt"
sha256sum "$TEST_NGINX_BINARY" > "$test_output/nginx.sha256.txt"
unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy
export NO_PROXY='*' no_proxy='*'

globals=''
if [[ "$(id -u)" == 0 ]]; then
    globals='user root;'
fi
module=''
if [[ "$link" == dynamic ]]; then
    module="$nginx_source/objs/ngx_http_trim_filter_module.so"
    test -f "$module"
fi

cd "$module_root"
official=()
openresty=()
for test_file in t/*.t; do
    if [[ "$expr" == disabled && "$test_file" == t/condition_trim*.t ]]; then
        echo "SKIP: $test_file (requires ngx_expr_module)"
        continue
    fi
    if grep -Eq '^use Test::Nginx::Socket' "$test_file"; then
        openresty+=("$test_file")
    else
        official+=("$test_file")
    fi
done
(( ${#official[@]} > 0 && ${#openresty[@]} > 0 ))

status=0
printf 'framework\tfiles\texit_code\n' > "$test_output/results.tsv"
for framework in official openresty; do
    if [[ "$framework" == official ]]; then
        tests=("${official[@]}")
        export PERL5LIB="$module_root/.ci/nginx-tests/lib"
        export TEST_NGINX_GLOBALS="$globals"
        unset TEST_NGINX_LOAD_MODULES
        if [[ -n "$module" ]]; then
            export TEST_NGINX_GLOBALS="$globals load_module $module;"
        fi
    else
        tests=("${openresty[@]}")
        export PERL5LIB="$module_root/.ci/test-nginx/lib"
        export TEST_NGINX_GLOBALS="$globals"
        export TEST_NGINX_LOAD_MODULES="$module"
    fi
    if prove -v "${tests[@]}" > "$test_output/$framework.log" 2>&1; then
        rc=0
    else
        rc=$?
        status=$rc
    fi
    cat "$test_output/$framework.log"
    printf '%s\t%s\t%s\n' "$framework" "${#tests[@]}" "$rc" \
        >> "$test_output/results.tsv"
done
exit "$status"
