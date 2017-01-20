#!/usr/bin/env perl

use Test::More;
eval "use Test::Pod 1.00";
if ($@) {
    plan skip_all => "Test::Pod 1.00 required for testing POD";
}

my @files = ('pmake','bmake', all_pod_files(('lib')));

all_pod_files_ok(@files);
