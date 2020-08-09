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
    [ "vpath %.c src/%.c othersrc/%.c\n", [ [ 'vpath', '%.c', 'src/%.c', 'othersrc/%.c' ], ], ],
    [
        "\n.SUFFIXES: .o .c .y .h .sh .cps # comment\n\n.c.o :\n\t\$(CC) \$(CFLAGS) \$(CPPFLAGS) -c -o \$@ \$<\n\n",
        [
            [ 'rule', '.SUFFIXES', ':', '.o .c .y .h .sh .cps', [] ],
            [ 'rule', '.c.o',      ':', '',                     ['$(CC) $(CFLAGS) $(CPPFLAGS) -c -o $@ $<'] ],
        ],
    ],
    [
        "# header\n.c.o :\n\techo hi\n# comment\n\n\techo yo\n",
        [ [ 'comment', 'header' ], [ 'rule', '.c.o', ':', '', [ 'echo hi', 'echo yo' ] ], ],
    ],
    [ "all : other ; echo hi # keep\n", [ [ 'rule', 'all', ':', 'other', ['echo hi # keep'] ] ], ],
    [ "all : other # drop ; echo hi\n", [ [ 'rule', 'all', ':', 'other', [] ] ], ],
);
for my $l (@ASTs) {
    my ( $in, $expected ) = @$l;
    open my $fh, '+<', \$in or die "open: $!";
    my $got = Make::parse_makefile($fh);
    is_deeply $got, $expected, $in or diag explain $got;
}

my @TOKENs = ( [ "a b c", [qw(a b c)] ], [ " a b c", [qw(a b c)] ], [ " a: b c", [qw(a b c)] ], );
for my $l (@TOKENs) {
    my ( $in, $expected, $err ) = @$l;
    my ($got) = eval { Make::tokenize( $in, ':' ) };
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
my $fsmap = make_fsmap( { Changes => [ 1, 'hi' ], README => [ 1, 'there' ], NOT => [ 1, 'in' ] } );
my @SUBs  = (
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
    [ '$(wildcard Chan* RE* NO*)',            'Changes README NOT' ],
    [ '$(addprefix x/,1 2)',                  'x/1 x/2' ],
    [ '$(notdir x/1 x/2)',                    '1 2' ],
    [ '$(dir x/1 y/2 3)',                     'x y ./' ],
    [ ' a ${dir $(call}',                     undef, qr/Syntax error/ ],
    [ ' a ${dir $(k1)',                       undef, qr/Syntax error/ ],
);
for my $l (@SUBs) {
    my ( $in, $expected, $err ) = @$l;
    my ($got) = eval { Make::subsvars( $in, $FUNCTIONS, [$VARS], $fsmap ) };
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

my $m = Make->new;
$m->parse;
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
ok !$m->target('all')->has_recipe, 'all has no recipe';
ok $m->target('other')->has_recipe, 'other has recipe';
ok !$m->get_target('not_there'), 'get_target';
ok $m->get_target('all'), 'get_target existing';
$m->Make('all');
my $contents = do { local $/; open my $fh, '<', $tempfile; <$fh> };
is $contents, "other Changes README Changes value\n";
my ($other_rule) = @{ $m->target('other')->rules };
my $got = $other_rule->recipe;
is_deeply $got, ['@echo $@ $^ $< $(var) >"$(tempfile)"'] or diag explain $got;
my $all_target = $m->target('all');
my ($all_rule) = @{ $all_target->rules };
$got = $all_rule->prereqs;
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
ok $m->target('all')->phony,  'all is phony';
is $m->target('a.x.o')->Base, 'a.x';
$m->Make;
$contents = do { local $/; open my $fh, '<', $tempfile; <$fh> };
is $contents, " \n";

$got = [ Make::parse_args(qw(all VAR=value)) ];
is_deeply $got, [ [ [qw(VAR value)] ], ['all'] ] or diag explain $got;

truncate $tempfile, 0;
$fsmap = make_fsmap(
    {
        'a.c'       => [ 2, 'hi' ],
        'a.o'       => [ 1, 'yo' ],
        'b.c'       => [ 2, 'hi' ],
        'b.o'       => [ 1, 'yo' ],
        GNUmakefile => [ 1, "include inc.mk\n-include not.mk\n" ],
        'inc.mk'    => [ 1, sprintf( <<'EOF', $tempfile ) ] } );
objs = a.o b.o
tempfile = %s
CC = @echo COMPILE >>"$(tempfile)"
CFLAGS =
all: $(objs)
.PHONY: all
a.o : a.c # these are so [ab].c "can be made" so implicit rule matches
b.o : b.c
EOF
$m = Make->new( FSFunctionMap => $fsmap, GNU => 1 );
$m->parse;
$got = $m->target('all')->rules->[0]->prereqs;
is_deeply $got, [qw(a.o b.o)] or diag explain $got;
$got = $m->target('a.o')->rules->[0]->prereqs;
is_deeply $got, ['a.c'] or diag explain $got;
$m->Make('all');
$contents = do { local $/; open my $fh, '<', $tempfile; <$fh> };
is $contents, "COMPILE -c -o a.o a.c\nCOMPILE -c -o b.o b.c\n";

done_testing;

sub make_fsmap {
    my ($vfs) = @_;
    my %fh2file_tuple;
    return {
        glob => sub {
            my @results;
            for my $subpat ( split /\s+/, $_[0] ) {
                $subpat =~ s/\*/.*/g;    # ignore ?, [], {} for now
                ## no critic (BuiltinFunctions::RequireBlockGrep)
                push @results, grep /^$subpat$/, sort keys %$vfs;
                ## use critic
            }
            return @results;
        },
        fh_open => sub {
            die "@_: No such file or directory" unless exists $vfs->{ $_[1] };
            my $file_tuple = $vfs->{ $_[1] };
            open my $fh, "+$_[0]", \$file_tuple->[1];
            $fh2file_tuple{$fh} = $file_tuple;
            return $fh;
        },
        fh_write      => sub { my $fh = shift; $fh2file_tuple{$fh}[0] = time; print {$fh} @_ },
        file_readable => sub { exists $vfs->{ $_[0] } },
        mtime         => sub { ( $vfs->{ $_[0] } || [] )->[0] },
    };
}
