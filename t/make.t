use strict;
use warnings;

use Test::More;

use Make;
my $m = Make->new( Makefile => "Makefile" );

is ref($m), 'Make';
eval { $m->Make('all') };
is $@, '',;

done_testing;
