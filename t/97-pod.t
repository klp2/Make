#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;
##no critic
eval "use Test::Pod 1.00";
if ($@) {
    plan skip_all => "Test::Pod 1.00 required for testing POD";
}

my @files = ( 'pmake', 'bmake', all_pod_files( ('lib') ) );

all_pod_files_ok(@files);
