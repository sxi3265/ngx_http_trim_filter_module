#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use FindBin;

plan tests => 1;
is(system('python3', "$FindBin::Bin/stream.py"), 0,
    'chunked EOF, early output, and downstream backpressure');
