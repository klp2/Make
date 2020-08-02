use strict;
use warnings;
use Test::More;
use Make;
use File::Spec;
use File::Temp qw(tempfile);

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
            [ 'rule', '.SUFFIXES', ':', '.o .c .y .h .sh .cps', [] ],
            [ 'rule', '.c.o ',     ':', '',                     ['$(CC) $(CFLAGS) $(CPPFLAGS) -c -o $@ $<'] ],
        ],
    ],
    [
        "# header\n.c.o :\n\techo hi\n# comment\n\n\techo yo\n",
        [ [ 'comment', 'header' ], [ 'rule', '.c.o ', ':', '', [ 'echo hi', 'echo yo' ] ], ],
    ],
);
for my $l (@ASTs) {
    my ( $in, $expected ) = @$l;
    open my $fh, '+<', \$in or die "open: $!";
    my $got = Make::parse_makefile($fh);
    is_deeply $got, $expected or diag explain $got;
}

my @TOKENs = ( [ "a b c", [qw(a b c)] ], [ " a b c", [qw(a b c)] ], );
for my $l (@TOKENs) {
    my ( $in, $expected, $err ) = @$l;
    my ($got) = eval { Make::tokenize($in) };
    like $@,        $err || qr/^$/;
    is_deeply $got, $expected or diag explain $got;
}

my $FUNCTIONS = ['Make::Functions'];
my $VARS      = {
    k1    => 'k2',
    k2    => 'hello',
    files => 'a.o b.o c.o',
    empty => '',
    space => ' ',
    comma => ',',
};
my @SUBs = (
    [ 'none',                                 'none' ],
    [ 'this $(k1) is',                        'this k2 is' ],
    [ 'this $$(k1) is not',                   'this $(k1) is not' ],
    [ 'this ${k1} is',                        'this k2 is' ],
    [ 'this $($(k1)) double',                 'this hello double' ],
    [ '$(empty)',                             '' ],
    [ '$(empty) $(empty)',                    ' ' ],
    [ '$(subst .o,.c,$(files))',              'a.c b.c c.c' ],
    [ '$(subst $(space),$(comma),$(files))',  'a.o,b.o,c.o' ],
    [ 'not $(absent) is',                     'not  is' ],
    [ 'this $(files:.o=.c) is',               'this a.c b.c c.c is' ],
    [ '$(shell echo hi; echo there)',         'hi there' ],
    [ "\$(shell \"$^X\" -pe 1 \$(mktmp hi))", 'hi' ],
    [ '$(wildcard Chan* RE*)',                'Changes README' ],
    [ '$(addprefix x/,1 2)',                  'x/1 x/2' ],
    [ '$(notdir x/1 x/2)',                    '1 2' ],
    [ '$(dir x/1 y/2 3)',                     'x y ./' ],
    [ ' a ${dir $(call}',                     undef, qr/Syntax error/ ],
    [ ' a ${dir $(k1)',                       undef, qr/Syntax error/ ],
);
for my $l (@SUBs) {
    my ( $in, $expected, $err ) = @$l;
    my ($got) = eval { Make::subsvars( $in, $FUNCTIONS, [$VARS] ) };
    like $@, $err || qr/^$/;
    is $got, $expected;
}

my @CMDs = (
    [ ' a line', { line => 'a line' } ],
    [ 'a line',  { line => 'a line' } ],
    [ '@echo shhh',   { line => 'echo shhh',  silent   => 1 } ],
    [ '- @echo hush', { line => 'echo hush',  silent   => 1, can_fail => 1 } ],
    [ '-just do it',  { line => 'just do it', can_fail => 1 } ],
);
for my $l (@CMDs) {
    my ( $in, $expected, $err ) = @$l;
    my ($got) = eval { Make::parse_cmdline($in) };
    like $@,        $err || qr/^$/;
    is_deeply $got, $expected;
}

my $m = Make->new( Makefile => "Makefile" );
$m->parse("Makefile");
is ref($m), 'Make';
eval { $m->Make('all') };
is $@, '',;

my ( undef, $tempfile ) = tempfile;
$m = Make->new;
$m->parse( \sprintf <<'EOF', $tempfile );
var = value
tempfile = %s
targets = other

all: $(targets)

other: Changes README
	@echo $@ $^ $< $(var) >"$(tempfile)"
EOF
$m->Make('all');
my $contents = do { local $/; open my $fh, '<', $tempfile; <$fh> };
is $contents, "other Changes README Changes value\n";
my ($other_rule) = @{ $m->Target('other')->rules };
my $got = $other_rule->command;
is_deeply $got, ['@echo $@ $^ $< $(var) >"$(tempfile)"'] or diag explain $got;
my $all_target = $m->Target('all');
my ($all_rule) = @{ $all_target->rules };
$got = $all_rule->depend;
is_deeply $got, ['other'] or diag explain $got;
$got = $all_rule->auto_vars($all_target);
ok exists $got->{'@'}, 'Rules.Vars.EXISTS';
is_deeply [ keys %$got ], [qw( @ * ^ ? < )] or diag explain $got;

$m = Make->new;
$m->parse( \sprintf <<'EOF', $tempfile );
space = $() $()
tempfile = %s
all: ; @echo "$(space)" >"$(tempfile)"
.PHONY: all
EOF
ok $m->Target('all')->phony,  'all is phony';
is $m->Target('a.x.o')->Base, 'a.x';
$m->Make;
$contents = do { local $/; open my $fh, '<', $tempfile; <$fh> };
is $contents, " \n";

$got = [ Make::parse_args(qw(all VAR=value)) ];
is_deeply $got, [ [ [qw(VAR value)] ], ['all'] ] or diag explain $got;

done_testing;
