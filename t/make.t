use strict;
use warnings;
use Test::More;
use Make;
use File::Spec;

my $m = Make->new( Makefile => "Makefile" );

my @LINES = ( [ "all : one \\\n  two\n", 'all : one two' ], );
for my $l (@LINES) {
    my ( $in, $expected ) = @$l;
    open my $fh, '+<', \$in or die "open: $!";
    is Make::get_full_line($fh), $expected;
}

my @ASTs = (
    [
        "\n.SUFFIXES: .o .c .y .h .sh .cps\n\n.c.o :\n\t\$(CC) \$(CFLAGS) \$(CPPFLAGS) -c -o \$@ \$<\n\n",
        [
            [ 'rule', ['.SUFFIXES'], ':', [ '.o', '.c', '.y', '.h', '.sh', '.cps' ], [] ],
            [ 'rule', ['.c.o'], ':', [], ['$(CC) $(CFLAGS) $(CPPFLAGS) -c -o $@ $<'] ],
        ],
    ],
);
for my $l (@ASTs) {
    my ( $in, $expected ) = @$l;
    open my $fh, '+<', \$in or die "open: $!";
    my $got = Make::parse_makefile( $fh, 'name' );
    is_deeply $got, $expected or diag explain $got;
}

is ref($m), 'Make';
eval { $m->Make('all') };
is $@, '',;

done_testing;
