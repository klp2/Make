use strict;
use warnings;
use Test::More;
use Make;

my $m = Make->new( Makefile => "Makefile" );

my @LINES = ( [ "all : one \\\n  two\n", 'all : one two' ], );
for my $l (@LINES) {
    my ( $in, $expected ) = @$l;
    open my $fh, '+<', \$in or die "open: $!";
    is Make::get_full_line($fh), $expected;
}

is ref($m), 'Make';
eval { $m->Make('all') };
is $@, '',;

done_testing;
