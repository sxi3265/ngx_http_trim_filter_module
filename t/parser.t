#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use File::Temp qw/tempdir/;
use FindBin;

my $cc = $ENV{CC} || 'cc';
my $dir = tempdir(CLEANUP => 1);
my $root = "$FindBin::Bin/..";
my $binary = "$dir/trim-parser";

my $source = $ENV{NGINX_SOURCE};
plan skip_all => 'set NGINX_SOURCE to the configured nginx source tree'
    unless $source && -f "$source/objs/ngx_auto_config.h";
my @includes = map { "-I$source/$_" }
    qw(objs src/core src/event src/event/modules src/os/unix src/http
       src/http/modules src/http/v2 src/http/v3);
plan tests => 4;
is(system($cc, '-std=c99', '-Wall', '-Wextra', '-Werror', @includes,
    "$FindBin::Bin/parser.c", '-o', $binary),
    0, 'compile standalone incremental parser') or BAIL_OUT('compiler failed');
is(system($binary), 0, 'semantic and every-split regressions');
is(system($cc, '-std=c99', '-Wall', '-Wextra', '-Werror', @includes,
    '-DNGX_HTTP_TRIM_FUZZ_STANDALONE', "$FindBin::Bin/fuzz_parser.c",
    '-o', "$binary-fuzz"), 0, 'compile deterministic fuzz runner')
    or BAIL_OUT('compiler failed');
is(system("$binary-fuzz"), 0, 'binary inputs are bounded and chunk independent');
