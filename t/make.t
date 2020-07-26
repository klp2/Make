use strict;
use warnings;
use Test::More;
use Make;
use File::Spec;
use File::Temp qw(tempfile);

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

my ( undef, $tempfile ) = tempfile;
my $FUNCTIONS = ['Make::Functions'];
my $VARS      = {
    k1    => 'k2',
    k2    => 'hello',
    files => 'a.o b.o c.o',
};
my @SUBs = (
    [ 'none',                                           'none' ],
    [ 'this $(k1) is',                                  'this k2 is' ],
    [ 'this ${k1} is',                                  'this k2 is' ],
    [ 'this $($(k1)) double',                           'this hello double' ],
    [ '$(subst .o,.c,$(files))',                        'a.c b.c c.c' ],
    [ 'not $(absent) is',                               'not  is' ],
    [ 'this $(files:.o=.c) is',                         'this a.c b.c c.c is' ],
    [ '$(shell echo hi; echo there)',                   'hi there' ],
    [ "\$(shell \"$^X\" -pe 1 \$(mktmp,$tempfile hi))", 'hi' ],
    [ "\$(shell \"$^X\" -pe 1 \$(mktmp hi))",           'hi' ],
    [ '$(wildcard Chan* RE*)',                          'Changes README' ],
    [ '$(addprefix x/,1 2)',                            'x/1 x/2' ],
    [ '$(notdir x/1 x/2)',                              '1 2' ],
    [ '$(dir x/1 y/2 3)',                               'x y ./' ],
);
for my $l (@SUBs) {
    my ( $in, $expected, $err ) = @$l;
    my ($got) = eval { Make::subsvars( $in, $FUNCTIONS, $VARS ) };
    like $@, $err || qr/^$/;
    is $got, $expected;
}

is ref($m), 'Make';
eval { $m->Make('all') };
is $@, '',;

$m = Make->new( Makefile => \sprintf <<'EOF', $tempfile );
var = value
tempfile = %s
targets = other

all: $(targets)

other:
	@echo $(var) >"$(tempfile)"
EOF
$m->Make('all');
my $contents = do { local $/; open my $fh, '<', $tempfile; <$fh> };
is $contents, "value\n";
my $other_rule = $m->Target('other')->colon;
my $got        = $other_rule->command;
is_deeply $got, ['@echo $(var) >"$(tempfile)"'] or diag explain $got;
my $all_rule = $m->Target('all')->colon;
$got = $all_rule->exp_depend;
is_deeply $got, ['other'] or diag explain $got;

done_testing;
