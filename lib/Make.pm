package Make;

use strict;
use warnings;

our $VERSION = '1.2.0';

use Carp qw(confess croak);
use Config;
use Cwd;
use File::Spec;
use Make::Target ();
use Make::Rule   ();
use File::Temp;
use Text::Balanced qw(extract_bracketed);
## no critic (ValuesAndExpressions::ProhibitConstantPragma)
use constant DEBUG => $ENV{MAKE_DEBUG};
## use critic
require Make::Functions;

my $DEFAULTS_AST;
my %date;
my %fs_function_map = (
    glob          => sub { glob $_[0] },
    fh_open       => sub { open my $fh, $_[0], $_[1] or die "open @_: $!"; $fh },
    fh_write      => sub { my $fh = shift; print {$fh} @_ },
    file_readable => sub { -r $_[0] },
    mtime         => sub { ( stat $_[0] )[9] },
);

## no critic (Subroutines::RequireArgUnpacking Subroutines::RequireFinalReturn)
sub load_modules {
    for (@_) {
        my $pkg = $_;    # to not mutate inputs
        $pkg =~ s#::#/#g;
        ## no critic (Modules::RequireBarewordIncludes)
        eval { require "$pkg.pm"; 1 } or die;
        ## use critic
    }
}

sub phony {
    my ( $self, $name ) = @_;
    return exists $self->{PHONY}{$name};
}

sub suffixes {
    my ($self) = @_;
    ## no critic (Subroutines::ProhibitReturnSort)
    return sort keys %{ $self->{'SUFFIXES'} };
    ## use critic
}

sub target {
    my ( $self, $target ) = @_;
    unless ( exists $self->{Depend}{$target} ) {
        my $t = $self->{Depend}{$target} = Make::Target->new( $target, $self );
        if ( $target =~ /%/ ) {
            $self->{Pattern}{$target} = $t;
        }
        elsif ( $target =~ /^\./ ) {
            $self->{Dot}{$target} = $t;
        }
        else {
            $self->{Vars}{'.DEFAULT_GOAL'} ||= $target;
        }
    }
    return $self->{Depend}{$target};
}

sub get_target {
    my ( $self, $target ) = @_;
    return exists $self->{Depend}{$target};
}

# Utility routine for patching %.o type 'patterns'
my %pattern_cache;

sub patmatch {
    my ( $pat, $target ) = @_;
    return $target if $pat eq '%';
    ## no critic (BuiltinFunctions::RequireBlockMap)
    $pattern_cache{$pat} = join '(.*)', map quotemeta, split /%/, $pat
        if !exists $pattern_cache{$pat};
    ## use critic
    $pat = $pattern_cache{$pat};
    if ( $target =~ /^$pat$/ ) {
        return $1;
    }
    return;
}

#
# old vpath lookup routine
#
sub locate {
    my $self = shift;
    local $_ = shift;
    my $readable = $self->fsmap->{file_readable};
    return $_ if $readable->($_);
    foreach my $key ( sort keys %{ $self->{vpath} } ) {
        my $Pat;
        if ( defined( $Pat = patmatch( $key, $_ ) ) ) {
            foreach my $dir ( split( /:/, $self->{vpath}{$key} ) ) {
                return "$dir/$_" if $readable->("$dir/$_");
            }
        }
    }
    return;
}

#
# Convert traditional .c.o rules into GNU-like into %.o : %.c
#
sub dotrules {
    my ($self) = @_;
    my @suffix = $self->suffixes;
    my $Dot    = delete $self->{Dot};
    foreach my $f (@suffix) {
        foreach my $t ( '', @suffix ) {
            delete $self->{Depend}{ $f . $t };
            next unless my $r = delete $Dot->{ $f . $t };
            DEBUG and print STDERR "Pattern %$t : %$f\n";
            my $target   = $self->target( '%' . $t );
            my @dotrules = @{ $r->rules };
            die "Failed on pattern rule for '$f$t', too many rules"
                if @dotrules != 1;
            my $thisrule = $dotrules[0];
            die "Failed on pattern rule for '$f$t', no prereqs allowed"
                if @{ $thisrule->prereqs };
            my $rule = Make::Rule->new( '::', [ '%' . $f ], $thisrule->recipe );
            $self->target( '%' . $t )->add_rule($rule);
        }
    }
    return;
}

#
# Return modified date of name if it exists
#
sub date {
    my ( $self, $name ) = @_;
    unless ( exists $date{$name} ) {
        $date{$name} = $self->fsmap->{mtime}->($name);
    }
    return $date{$name};
}

#
# See if we can find a %.o : %.c rule for target
# .c.o rules are already converted to this form
#
sub patrule {
    my ( $self, $target, $kind ) = @_;
    DEBUG and print STDERR "Trying pattern for $target\n";
    foreach my $key ( sort keys %{ $self->{Pattern} } ) {
        DEBUG and print STDERR " Pattern $key trying\n";
        next unless defined( my $Pat = patmatch( $key, $target ) );
        DEBUG and print STDERR " Pattern $key matched ($Pat)\n";
        my $t = $self->{Pattern}{$key};
        foreach my $rule ( @{ $t->rules } ) {
            my @dep = @{ $rule->prereqs };
            DEBUG and print STDERR "  Try rule : @dep\n";
            next unless @dep;
            s/%/$Pat/g for @dep;
            ## no critic (BuiltinFunctions::RequireBlockGrep)
            my @failed = grep !( $self->date($_) or $self->get_target($_) ), @dep;
            ## use critic
            DEBUG and print STDERR "  " . ( @failed ? "Failed: (@failed)" : "Matched (@dep)" ) . "\n";
            next if @failed;
            return Make::Rule->new( $kind, \@dep, $rule->recipe );
        }
    }
    return;
}

#
# Old code to handle vpath stuff - not used yet
#
sub needs {
    my ( $self, $target ) = @_;
    unless ( $self->{Done}{$target} ) {
        if ( exists $self->{Depend}{$target} ) {
            my @prereqs = tokenize( $self->expand( $self->{Depend}{$target} ) );
            foreach (@prereqs) {
                $self->needs($_);
            }
        }
        else {
            my $vtarget = $self->locate($target);
            if ( defined $vtarget ) {
                $self->{Need}{$vtarget} = $target;
            }
            else {
                $self->{Need}{$target} = $target;
            }
        }
    }
    return;
}

sub evaluate_macro {
    my ( $key, @args ) = @_;
    my ( $function_packages, $vars_search_list, $fsmap ) = @args;
    my $value;
    return '' if !length $key;
    if ( $key =~ /^([\w._]+|\S)(?::(.*))?$/ ) {
        my ( $var, $subst ) = ( $1, $2 );
        foreach my $hash (@$vars_search_list) {
            last if defined( $value = $hash->{$var} );
        }
        $value = '' if !defined $value;
        if ( defined $subst ) {
            my @parts = split /=/, $subst, 2;
            die "Syntax error: expected form x=y in '$subst'" if @parts != 2;
            $value = join ' ', Make::Functions::patsubst( $fsmap, @parts, $value );
        }
    }
    elsif ( $key =~ /([\w._]+)\s+(.*)$/ ) {
        my ( $func, $args ) = ( $1, $2 );
        my $code;
        foreach my $package (@$function_packages) {
            last if $code = $package->can($func);
        }
        die "'$func' not found in (@$function_packages)" if !defined $code;
        ## no critic (BuiltinFunctions::RequireBlockMap)
        $value = join ' ', $code->( $fsmap, map subsvars( $_, @args ), split /\s*,\s*/, $args );
        ## use critic
    }
    elsif ( $key =~ /^\S*\$/ ) {

        # something clever, expand it
        $key = subsvars( $key, @args );
        return evaluate_macro( $key, @args );
    }
    return subsvars( $value, @args );
}

sub subsvars {
    my ( $remaining, $function_packages, $vars_search_list, $fsmap ) = @_;
    confess "Trying to expand undef value" unless defined $remaining;
    my $ret = '';
    my $found;
    while (1) {
        last unless $remaining =~ s/(.*?)\$//;
        $ret .= $1;
        my $char = substr $remaining, 0, 1;
        if ( $char eq '$' ) {
            $ret .= $char;    # literal $
            substr $remaining, 0, 1, '';
            next;
        }
        elsif ( $char =~ /[\{\(]/ ) {
            ( $found, my $tail ) = extract_bracketed $remaining, '{}()', '';
            die "Syntax error in '$remaining'" if !defined $found;
            $found     = substr $found, 1, -1;
            $remaining = $tail;
        }
        else {
            $found = substr $remaining, 0, 1, '';
        }
        my $value = evaluate_macro( $found, $function_packages, $vars_search_list, $fsmap );
        if ( !defined $value ) {
            warn "Cannot evaluate '$found'\n";
            $value = '';
        }
        $ret .= $value;
    }
    return $ret . $remaining;
}

# Perhaps should also understand "..." and '...' ?
# like GNU make will need to understand \ to quote spaces, for deps
# also C:\xyz as a non-target (overlap with parse_makefile)
sub tokenize {
    my ($string) = @_;
    ## no critic (BuiltinFunctions::RequireBlockGrep)
    return [ grep length, split /\s+/, $string ];
    ## use critic
}

sub get_full_line {
    my ($fh) = @_;
    my $final = my $line = <$fh>;
    return if !defined $line;
    chomp($final);
    while ( $final =~ /\\$/ ) {
        chop $final;
        $final =~ s/\s*$//;
        $line = <$fh>;
        last if !defined $line;
        chomp $line;
        $line =~ s/^\s*/ /;
        $final .= $line;
    }
    return $final;
}

sub set_var {
    my ( $self, $name, $value ) = @_;
    $self->{Vars}{$name} = $value;
}

sub vars {
    my ($self) = @_;
    $self->{Vars};
}

sub function_packages {
    my ($self) = @_;
    $self->{FunctionPackages};
}

sub fsmap {
    my ($self) = @_;
    $self->{FSFunctionMap};
}

sub expand {
    my ( $self, $text ) = @_;
    return subsvars( $text, $self->function_packages, [ $self->vars, \%ENV ], $self->fsmap );
}

sub process_ast_bit {
    my ( $self, $type, @args ) = @_;
    return if $type eq 'comment';
    if ( $type eq 'include' ) {
        my $opt = $args[0];
        my ($tokens) = tokenize( $self->expand( $args[1] ) );
        foreach my $file (@$tokens) {
            eval {
                my $mf  = $self->fsmap->{fh_open}->( '<', $file );
                my $ast = parse_makefile($mf);
                close($mf);
                $self->process_ast_bit(@$_) for @$ast;
                1;
            } or warn $@ if $opt ne '-';
        }
    }
    elsif ( $type eq 'var' ) {
        $self->set_var( $args[0], defined $args[1] ? $args[1] : "" );
    }
    elsif ( $type eq 'vpath' ) {
        $self->{Vpath}{ $args[0] } = $args[1];
    }
    elsif ( $type eq 'rule' ) {
        my ( $targets, $kind, $prereqs, $cmnds ) = @args;
        ($prereqs) = tokenize( $self->expand($prereqs) );
        ($targets) = tokenize( $self->expand($targets) );
        unless ( @$targets == 1 and $targets->[0] =~ /^\.[A-Z]/ ) {
            $self->target($_) for @$prereqs;    # so "exist or can be made"
        }
        my $rule = Make::Rule->new( $kind, $prereqs, $cmnds );
        $self->target($_)->add_rule($rule) for @$targets;
    }
    return;
}

#
# read makefile (or fragment of one) either as a result
# of a command line, or an 'include' in another makefile.
#
sub parse_makefile {
    my ($fh) = @_;
    my @ast;
    local $_ = get_full_line($fh);
    while (1) {
        last unless ( defined $_ );
        s/^\s+//;
        next if !length;
        if (/^(-?)include\s+(.*)$/) {
            push @ast, [ 'include', $1, $2 ];
        }
        elsif (s/^#+\s*//) {
            push @ast, [ 'comment', $_ ];
        }
        elsif (/^\s*([\w._]+)\s*:?=\s*(.*)$/) {
            push @ast, [ 'var', $1, $2 ];
        }
        elsif (/^vpath\s+(\S+)\s+(.*)$/) {
            push @ast, [ 'vpath', $1, $2 ];
        }
        elsif (
            /^
                \s*
                ([^:\#]*?)
                \s*
                (::?)
                \s*
                ((?:[^;\#]*\#.*|.*?))
                (?:\s*;\s*(.*))?
            $/sx
            )
        {
            my ( $target, $kind, $prereqs, $maybe_cmd ) = ( $1, $2, $3, $4 );
            my @cmnds = defined $maybe_cmd ? ($maybe_cmd) : ();
            $prereqs =~ s/\s*#.*//;
            while ( defined( $_ = get_full_line($fh) ) ) {
                next if (/^\s*#/);
                next if (/^\s*$/);
                last unless (/^\t/);
                next if (/^\s*$/);
                s/^\s+//;
                push( @cmnds, $_ );
            }
            push @ast, [ 'rule', $target, $kind, $prereqs, \@cmnds ];
            redo;
        }
        else {
            warn "Ignore '$_'\n";
        }
    }
    continue {
        $_ = get_full_line($fh);
    }
    return \@ast;
}

sub pseudos {
    my $self = shift;
    foreach my $key (qw(SUFFIXES PHONY PRECIOUS PARALLEL)) {
        delete $self->{Depend}{ '.' . $key };
        my $t = delete $self->{Dot}{ '.' . $key };
        if ( defined $t ) {
            $self->{$key} = {};
            ## no critic (BuiltinFunctions::RequireBlockMap)
            foreach my $dep ( map @{ $_->prereqs }, @{ $t->rules } ) {
                ## use critic
                $self->{$key}{$dep} = 1;
            }
        }
    }
    return;
}

sub find_makefile {
    my ( $file, $extra_names, $fsmap ) = @_;
    return $file if defined $file;
    for ( qw(makefile Makefile), @{ $extra_names || [] } ) {
        return $_ if $fsmap->{file_readable}->($_);
    }
    return;
}

sub parse {
    my ( $self, $file ) = @_;
    $file = find_makefile $file, $self->{GNU} ? ['GNUmakefile'] : [], $self->fsmap;
    my $fh;
    if ( ref $file eq 'SCALAR' ) {
        open my $tfh, "+<", $file;
        $fh = $tfh;
    }
    else {
        $fh = $self->fsmap->{fh_open}->( '<', $file );
    }
    my $ast = parse_makefile($fh);
    $self->process_ast_bit(@$_) for @$ast;
    undef $fh;

    # Next bits should really be done 'lazy' on need.

    $self->pseudos;     # Pull out .SUFFIXES etc.
    $self->dotrules;    # Convert .c.o into %.o : %.c
    return;
}

sub PrintVars {
    my $self = shift;
    local $_;
    my $vars = $self->vars;
    foreach ( sort keys %$vars ) {
        print "$_ = ", $vars->{$_}, "\n";
    }
    print "\n";
    return;
}

sub parse_cmdline {
    my ($line) = @_;
    $line =~ s/^([\@\s-]*)//;
    my $prefix = $1;
    my %parsed = ( line => $line );
    $parsed{silent}   = 1 if $prefix =~ /\@/;
    $parsed{can_fail} = 1 if $prefix =~ /-/;
    return \%parsed;
}

## no critic (Subroutines::ProhibitBuiltinHomonyms)
sub exec {
    my ( $self, $line ) = @_;
    undef %date;
    my $parsed = parse_cmdline($line);
    print "$parsed->{line}\n" unless $parsed->{silent};
    my $code = system $parsed->{line};
    if ( $code && !$parsed->{can_fail} ) {
        $code >>= 8;
        die "Code $code from $parsed->{line}";
    }
    return;
}
## use critic

## no critic (Subroutines::RequireFinalReturn)
sub NextPass { shift->{Pass}++ }
sub pass     { shift->{Pass} }
## use critic

## no critic (RequireArgUnpacking)
sub parse_args {
    my ( @vars, @targets );
    foreach (@_) {
        if (/^(\w+)=(.*)$/) {
            push @vars, [ $1, $2 ];
        }
        else {
            push @targets, $_;
        }
    }
    return \@vars, \@targets;
}
## use critic

sub apply {
    my ( $self, $method, @args ) = @_;
    $self->NextPass;
    my ( $vars, $targets ) = parse_args(@args);
    $self->set_var(@$_) for @$vars;
    $targets = [ $self->{Vars}{'.DEFAULT_GOAL'} ] unless @$targets;
    ## no critic (BuiltinFunctions::RequireBlockGrep BuiltinFunctions::RequireBlockMap)
    my @bad_targets = grep !$self->{Depend}{$_}, @$targets;
    die "Cannot '$method' (@args) - no target @bad_targets" if @bad_targets;
    return map $self->target($_)->recurse($method), @$targets;
    ## use critic
}

# Spew a shell script to perfom the 'make' e.g. make -n
sub Script {
    my ( $self, @args ) = @_;
    my $com = ( $^O eq 'MSWin32' ) ? 'rem ' : '# ';
    my @results;
    for ( $self->apply( Make => @args ) ) {
        my ( $name, @cmd ) = @$_;
        push @results, $com . $name . "\n";
        ## no critic (BuiltinFunctions::RequireBlockMap)
        push @results, map parse_cmdline($_)->{line} . "\n", @cmd;
        ## use critic
    }
    return @results;
}

sub Print {
    my ( $self, @args ) = @_;
    return $self->apply( Print => @args );
}

sub Make {
    my ( $self, @args ) = @_;
    for ( $self->apply( Make => @args ) ) {
        my ( $name, @cmd ) = @$_;
        $self->exec($_) for @cmd;
    }
    return;
}

sub new {
    my ( $class, %args ) = @_;
    my $self = bless {
        Pattern          => {},                      # GNU style %.o : %.c
        Dot              => {},                      # Trad style .c.o
        Vpath            => {},                      # vpath %.c info
        Vars             => {},                      # Variables defined in makefile
        Depend           => {},                      # hash of targets
        Pass             => 0,                       # incremented each sweep
        Need             => {},
        Done             => {},
        FunctionPackages => [qw(Make::Functions)],
        FSFunctionMap    => \%fs_function_map,
        %args,
    }, $class;
    $self->set_var( 'CC',     $Config{cc} );
    $self->set_var( 'AR',     $Config{ar} );
    $self->set_var( 'CFLAGS', $Config{optimize} );
    load_modules( @{ $self->function_packages } );
    $DEFAULTS_AST ||= parse_makefile( \*DATA );
    $self->process_ast_bit(@$_) for @$DEFAULTS_AST;
    return $self;
}

=head1 NAME

Make - Pure-Perl implementation of a somewhat GNU-like make.

=head1 SYNOPSIS

    require Make;
    my $make = Make->new;
    $make->parse($file);
    $make->Make(@ARGV);

    # to see what it would have done
    print $make->Script(@ARGV);

    # to see an expanded version of the makefile
    $make->Print(@ARGV);

    my $targ = $make->target($name);
    my $rule = Make::Rule->new(':', \@prereqs, \@recipe);
    $targ->add_rule($rule);
    my @rules = @{ $targ->rules };

    my @prereqs  = @{ $rule->prereqs };
    my @commands = @{ $rule->recipe };

=head1 DESCRIPTION

In addition to traditional

	.c.o :
		$(CC) -c ...

GNU make's 'pattern' rules e.g.

	%.o : %.c
		$(CC) -c ...

Via pure-perl-make Make has built perl/Tk from the C<MakeMaker> generated
Makefiles...

=head1 METHODS

There are other methods (used by parse) which can be used to add and
manipulate targets and their prerequites.

=head2 new

Class method, takes pairs of arguments in name/value form. Arguments:

=head3 Vars

A hash-ref of values that sets variables, overridable by the makefile.

=head3 Jobs

Number of concurrent jobs to run while building. Not implemented.

=head3 GNU

If true, then F<GNUmakefile> is looked for first.

=head3 FunctionPackages

Array-ref of package names to search for GNU-make style
functions. Defaults to L<Make::Functions>.

=head3 FSFunctionMap

Hash-ref of file-system functions by which to access the
file-system. Created to help testing, but might be more widely useful.
Defaults to code accessing the actual local filesystem. The various
functions are expected to return real Perl filehandles. Relevant keys:
C<glob>, C<fh_open>, C<fh_write>, C<mtime>.

=head2 parse

Parses the given makefile. If none or C<undef>, these files will be tried,
in order: F<GNUmakefile> if L</GNU>, F<makefile>, F<Makefile>.

If a scalar-ref, will be makefile text.

=head2 Make

Given a target-name, builds the target(s) specified, or the first 'real'
target in the makefile.

=head2 Print

Print to current C<select>'ed stream a form of the makefile with all
variables expanded.

=head2 Script

Print to current C<select>'ed stream the equivalent bourne shell script
that a make would perform i.e. the output of C<make -n>.

=head2 set_var

Given a name and value, sets the variable to that.

May gain a "type" parameter to distinguish immediately-expanded from
recursively-expanded (the default).

=head2 expand

Uses L</subsvars> to return its only arg with any macros expanded.

=head2 target

Find or create L<Make::Target> for given target-name.

=head2 get_target

Find L<Make::Target> for given target-name, or undef.

=head2 patrule

Search registered pattern-rules for one matching given
target-name. Returns a L<Make::Rule> for that of the given kind, or false.

Uses GNU make's "exists or can be made" algorithm on each rule's proposed
requisite to see if that rule matches.

=head1 ATTRIBUTES

These are read-only.

=head2 vars

Returns a hash-ref of the current set of variables.

=head2 function_packages

Returns an array-ref of the packages to search for macro functions.

=head2 fsmap

Returns a hash-ref of the L</FSFunctionMap>.

=head1 FUNCTIONS

=head2 parse_makefile

Given a file-handle, returns array-ref of Abstract Syntax-Tree (AST)
fragments, representing the contents of that file. Each is an array-ref
whose first element is the node-type (C<comment>, C<include>, C<vpath>,
C<var>, C<rule>), followed by relevant data.

=head2 tokenize

Given a line, returns array-ref of the space-separated "tokens".

=head2 subsvars

    my $expanded = Make::subsvars(
        'hi $(shell echo there)',
        \@function_packages,
        [ \%vars ],
        $fsmap,
    );
    # "hi there"

Given a piece of text, will substitute any macros in it, either a
single-character macro, or surrounded by either C<{}> or C<()>. These
can be nested. Uses the array-ref as a list of hashes to search
for values.

If the macro is of form C<$(varname:a=b)>, then this will be a GNU
(and others) make-style "substitution reference". First "varname" will
be expanded. Then all occurrences of "a" at the end of words within
the expanded text will be replaced with "b". This is intended for file
suffixes.

For GNU-make style functions, see L<Make::Functions>.

=head1 DEBUGGING

To see debugging messages on C<STDERR>, set environment variable
C<MAKE_DEBUG> to a true value;

=head1 BUGS

More attention needs to be given to using the package to I<write> makefiles.

The rules for matching 'dot rules' e.g. .c.o   and/or pattern rules e.g. %.o : %.c
are suspect. For example give a choice of .xs.o vs .xs.c + .c.o behaviour
seems a little odd.

=head1 SEE ALSO

L<pure-perl-make>

L<https://pubs.opengroup.org/onlinepubs/9699919799/utilities/make.html> POSIX standard for make

L<https://www.gnu.org/software/make/manual/make.html> GNU make docs

=head1 AUTHOR

Nick Ing-Simmons

=head1 COPYRIGHT AND LICENSE

Copyright (c) 1996-1999 Nick Ing-Simmons.

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

1;
#
# Remainder of file is in makefile syntax and constitutes
# the built in rules
#
__DATA__

.SUFFIXES: .o .c .y .h .sh .cps

.c.o :
	$(CC) $(CFLAGS) $(CPPFLAGS) -c -o $@ $<

.c   :
	$(CC) $(CFLAGS) $(CPPFLAGS) -o $@ $< $(LDFLAGS) $(LDLIBS)

.y.o:
	$(YACC) $<
	$(CC) $(CFLAGS) $(CPPFLAGS) -c -o $@ y.tab.c
	$(RM) y.tab.c

.y.c:
	$(YACC) $<
	mv y.tab.c $@
