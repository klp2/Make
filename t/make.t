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
    [
        "# header\n.c.o :\n\techo hi\n# comment\n\n\techo yo\n",
        [ [ 'comment', 'header' ], [ 'rule', ['.c.o'], ':', [], [ 'echo hi', 'echo yo' ] ], ],
    ],
);
for my $l (@ASTs) {
    my ( $in, $expected ) = @$l;
    open my $fh, '+<', \$in or die "open: $!";
    my $got = Make::parse_makefile($fh);
    is_deeply $got, $expected or diag explain $got;
}

my @TOKENs = (
    [ "a b c",    [qw(a b c)] ],
    [ " a b c",   [qw(a b c)] ],
    [ ' a ${hi}', [qw(a ${hi})] ],
    [ ' a $(hi)', [qw(a $(hi))] ],
    [ ' a $(hi there)',        [ 'a', '$(hi there)' ] ],
    [ ' a ${hi $(call)} b',    [ 'a', '${hi $(call)}', 'b' ] ],
    [ ' a ${hi $(func call)}', [ 'a', '${hi $(func call)}' ] ],
    [ ' a ${hi func(call)} b', [ 'a', '${hi func(call)}', 'b' ] ],
    [ ' a ${hi func(call} b',  [ 'a', '${hi func(call}', 'b' ] ],
    [ ' a ${hi $(call} b',    undef, qr/Unexpected '}'/ ],
    [ ' a ${hi $(func call)', undef, qr/Expected '}'/ ],
);
for my $l (@TOKENs) {
    my ( $in, $expected, $err ) = @$l;
    my ($got) = eval { Make::tokenize($in) };
    like $@,        $err || qr/^$/;
    is_deeply $got, $expected or diag explain $got;
}

my $VARS = {
    k1 => 'k2',
    k2 => 'hello',
};
my @SUBs = (
    [ 'none',                       'none' ],
    [ 'this $(k1) is',              'this k2 is' ],
    [ 'this $($(k1)) double',       'this hello double' ],
    [ '$(subst .o,.c,a.o b.o c.o)', 'a.c b.c c.c' ],
    [ 'not $(absent) is',           'not  is' ],
);
for my $l (@SUBs) {
    my ( $in, $expected, $err ) = @$l;
    my ($got) = eval { Make::subsvars( $in, $VARS ) };
    like $@, $err || qr/^$/;
    is $got, $expected;
}

is ref($m), 'Make';
eval { $m->Make('all') };
is $@, '',;

done_testing;
