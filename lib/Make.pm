package Make;

use strict;
use warnings;

our $VERSION = '1.2.0';

use Carp;
use Config;
use Cwd;
use File::Spec;
use Make::Target ();

my %date;
my $generation = 0;    # lexical cross-package scope used!

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

#
# Construct a new 'target' (or find old one)
# - used by parser to add to data structures
#
sub Target {
    my ( $self, $target ) = @_;
    unless ( exists $self->{Depend}{$target} ) {
        my $t = Make::Target->new( $self, $target );
        $self->{Depend}{$target} = $t;
        if ( $target =~ /%/ ) {
            $self->{Pattern}{$target} = $t;
        }
        elsif ( $target =~ /^\./ ) {
            $self->{Dot}{$target} = $t;
        }
        else {
            push( @{ $self->{Targets} }, $t );
        }
    }
    return $self->{Depend}{$target};
}

#
# Utility routine for patching %.o type 'patterns'
#
sub patmatch {
    my $key = shift;
    local $_ = shift;
    my $pat = $key;
    $pat =~ s/\./\\./;
    $pat =~ s/%/(\[^\/\]*)/;
    if (/$pat$/) {
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
    return $_ if ( -r $_ );
    foreach my $key ( sort keys %{ $self->{vpath} } ) {
        my $Pat;
        if ( defined( $Pat = patmatch( $key, $_ ) ) ) {
            foreach my $dir ( split( /:/, $self->{vpath}{$key} ) ) {
                return "$dir/$_" if ( -r "$dir/$_" );
            }
        }
    }
    return;
}

#
# Convert traditional .c.o rules into GNU-like into %o : %c
#
sub dotrules {
    my ($self) = @_;
    foreach my $t ( sort keys %{ $self->{Dot} } ) {
        my $e = subsvars( $t, $self->vars, \%ENV );
        $self->{Dot}{$e} = delete $self->{Dot}{$t} unless ( $t eq $e );
    }
    my (@suffix) = $self->suffixes;
    foreach my $t (@suffix) {
        my $d;
        my $r = delete $self->{Dot}{$t};
        if ( defined $r ) {
            my @rule = ( $r->colon ) ? ( $r->colon->depend ) : ();
            if (@rule) {
                delete $self->{Dot}{ $t->Name };
                print STDERR $t->Name, " has dependants\n";
                push( @{ $self->{Targets} }, $r );
            }
            else {
                # print STDERR "Build \% : \%$t\n";
                $self->Target('%')->dcolon( [ '%' . $t ], scalar $r->colon->command );
            }
        }
        foreach my $d (@suffix) {
            $r = delete $self->{Dot}{ $t . $d };
            if ( defined $r ) {

                # print STDERR "Build \%$d : \%$t\n";
                $self->Target( '%' . $d )->dcolon( [ '%' . $t ], scalar $r->colon->command );
            }
        }
    }
    foreach my $t ( sort keys %{ $self->{Dot} } ) {
        push( @{ $self->{Targets} }, delete $self->{Dot}{$t} );
    }
    return;
}

#
# Return modified date of name if it exists
#
sub date {
    my ( $self, $name ) = @_;
    unless ( exists $date{$name} ) {
        $date{$name} = -M $name;
    }
    return $date{$name};
}

#
# Check to see if name is a target we can make or an existing
# file - used to see if pattern rules are valid
# - Needs extending to do vpath lookups
#
## no critic (Subroutines::ProhibitBuiltinHomonyms)
sub exists {
## use critic
    my ( $self, $name ) = @_;
    return 1 if ( exists $self->{Depend}{$name} );
    return 1 if defined $self->date($name);

    # print STDERR "$name '$path' does not exist\n";
    return 0;
}

#
# See if we can find a %.o : %.c rule for target
# .c.o rules are already converted to this form
#
sub patrule {
    my ( $self, $target ) = @_;

    # print STDERR "Trying pattern for $target\n";
    foreach my $key ( sort keys %{ $self->{Pattern} } ) {
        my $Pat;
        if ( defined( $Pat = patmatch( $key, $target ) ) ) {
            my $t = $self->{Pattern}{$key};
            foreach my $rule ( $t->dcolon ) {
                my @dep = $rule->exp_depend;
                if (@dep) {
                    my $dep = $dep[0];
                    $dep =~ s/%/$Pat/g;

                    # print STDERR "Try $target : $dep\n";
                    if ( $self->exists($dep) ) {
                        foreach (@dep) {
                            s/%/$Pat/g;
                        }
                        return ( \@dep, scalar $rule->command );
                    }
                }
            }
        }
    }
    return ();
}

#
# Old code to handle vpath stuff - not used yet
#
sub needs {
    my ( $self, $target ) = @_;
    unless ( $self->{Done}{$target} ) {
        if ( exists $self->{Depend}{$target} ) {
            my @depend = split( /\s+/, subsvars( $self->{Depend}{$target}, $self->vars, \%ENV ) );
            foreach (@depend) {
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

#
# Substitute $(xxxx) and $x style variable references
# - should handle ${xxx} as well
# - recurses till they all go rather than doing one level,
#   which may need fixing
#
## no critic (RequireArgUnpacking)
sub subsvars {
    local $_ = shift;
    my @vars_search_list = @_;
## use critic
    croak("Trying to subsitute undef value") unless ( defined $_ );
    ## no critic (Variables::ProhibitMatchVars)
    while ( /(?<!\$)\$\(([^()]+)\)/ || /(?<!\$)\$([<\@^?*])/ ) {
        my ( $key, $head, $tail ) = ( $1, $`, $' );
        ## use critic
        my $value;
        if ( $key =~ /^([\w._]+|\S)(?::(.*))?$/ ) {
            my ( $var, $op ) = ( $1, $2 );
            foreach my $hash (@vars_search_list) {
                $value = $hash->{$var};
                if ( defined $value ) {
                    last;
                }
            }
            unless ( defined $value ) {
                die "$var not defined in '$_'" unless ( length($var) > 1 );
                $value = '';
            }
            if ( defined $op ) {
                if ( $op =~ /^s(.).*\1.*\1/ ) {
                    local $_ = subsvars( $value, @vars_search_list );
                    $op =~ s/\\/\\\\/g;
                    next unless $op;

                    #I'm not sure what purpose this eval served, and it
                    #creates some warnings. Removing until I know a good
                    #reason for it's existence.
                    #eval { $op . 'g' };
                    $value = $_;
                }
                else {
                    die "$var:$op = '$value'\n";
                }
            }
        }
        elsif ( $key =~ /wildcard\s*(.*)$/ ) {
            $value = join( ' ', glob($1) );
        }
        elsif ( $key =~ /shell\s*(.*)$/ ) {
            $value = join( ' ', split( '\n', `$1` ) );
        }
        elsif ( $key =~ /addprefix\s*([^,]*),(.*)$/ ) {
            $value = join( ' ', map { $1 . $_ } split( '\s+', $2 ) );
        }
        elsif ( $key =~ /notdir\s*(.*)$/ ) {
            my @files = split( /\s+/, $1 );
            foreach (@files) {
                s#^.*/([^/]*)$#$1#;
            }
            $value = join( ' ', @files );
        }
        elsif ( $key =~ /dir\s*(.*)$/ ) {
            my @files = split( /\s+/, $1 );
            foreach (@files) {
                s#^(.*)/[^/]*$#$1#;
            }
            $value = join( ' ', @files );
        }
        elsif ( $key =~ /^subst\s+([^,]*),([^,]*),(.*)$/ ) {
            my ( $from, $to ) = ( $1, $2 );
            $value = $3;
            $from  = quotemeta $from;
            $value =~ s/$from/$to/g;
        }

        # $(mktmp) appears to be a dmake only macro
        # its not yet clear to me just how temporary this temporary
        # file is expected to be, but hopefully we can replace this
        # with Path::Tiny->tempfile or the use of File::Temp directly
        # this also only handles one use of the macro, where the content
        # and filename are provided together. they may be provided
        # separately, which I don't think we handle yet
        elsif ( $key =~ /^mktmp,(\S+)\s*(.*)$/ ) {
            my ( $file, $content ) = ( $1, $2 );
            open( my $tmp, ">", $file ) or die "Cannot open $file: $!";
            $content =~ s/\\n//g;
            print TMP $content;
            close(TMP);

            # will have to see if we really want to return the filename
            # here, or if returning the filehandle is the right thing to do
            $value = $file;
        }
        else {
            warn "Cannot evaluate '$key' in '$_'\n";
        }
        $_ = "$head$value$tail";
    }
    s/\$\$/\$/g;
    return $_;
}

#
# Split a string into tokens - like split(/\s+/,...) but handling
# $(keyword ...) with embedded \s
# Perhaps should also understand "..." and '...' ?
## no critic
sub tokenize {
    my ( $string, $offset, $close_stack ) = @_;
    $offset      ||= 0;
    $close_stack ||= [];
    my $length       = length $string;
    my @result       = ();
    my $start_offset = $offset;
    my $in_token     = 0;
    my $good_closer;

    while (1) {
        my $char      = substr $string, $offset, 1;
        my $is_closer = $char =~ /[\}\)]/;
        $good_closer = $is_closer && @$close_stack && $char eq $close_stack->[-1];
        if (    $is_closer
            and !( @$close_stack and $char eq $close_stack->[-1] )
            and ( grep $char eq $_, @$close_stack ) )
        {
            die "Unexpected '$char' in $string at $offset";
        }
        if ( $char =~ /\s/ or $good_closer or $offset == $length ) {
            push @result, substr $string, $start_offset, $offset - $start_offset
                if $in_token;
            $in_token = 0;
        }
        else {
            $start_offset = $offset if !$in_token;
            $in_token     = 1;
        }
        last if $offset >= $length;
        if ( $char eq '$' ) {
            my $char2 = substr( $string, ++$offset, 1 );
            if ( $char2 eq '$' ) {
                next;    # literal $
            }
            elsif ( $char2 =~ /([\{\(])/ ) {
                my $opener = $1;
                my $closer = $opener eq '(' ? ')' : '}';
                ( my $subtokens, $offset ) = tokenize( $string, $offset + 1, [ @$close_stack, $closer ], );
                $offset--;    # counter the ++ in continue
            }
            else {
                die "Syntax error: '\$$char2' in '$string' at $offset";
            }
        }
        elsif ($good_closer) {
            $offset++;
            last;
        }
    }
    continue {
        $offset++;
    }
    die "Expected '$close_stack->[-1]' in '$string' at end"
        if !$good_closer
        and @$close_stack
        and $offset == $length;
    return ( \@result, $offset );
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

sub process_ast_bit {
    my ( $self, $type, @args ) = @_;
    return if $type eq 'comment';
    if ( $type eq 'include' ) {
        my $opt = $args[0];
        my ($tokens) = tokenize( subsvars( $args[1], $self->vars, \%ENV ) );
        foreach my $file (@$tokens) {
            if ( open( my $mf, "<", $file ) ) {
                my $ast = parse_makefile($mf);
                close($mf);
                $self->process_ast_bit(@$_) for @$ast;
            }
            else {
                warn "Cannot open $file: $!" unless ( $opt eq '-' );
            }
        }
    }
    elsif ( $type eq 'var' ) {
        $self->set_var( $args[0], defined $args[1] ? $args[1] : "" );
    }
    elsif ( $type eq 'vpath' ) {
        $self->{Vpath}{ $args[0] } = $args[1];
    }
    elsif ( $type eq 'rule' ) {
        my ( $targets, $kind, $depends, $cmnds ) = @args;
        foreach (@$targets) {
            my $t     = $self->Target($_);
            my $index = 0;
            if ( $kind eq '::' || /%/ ) {
                $t->dcolon( $depends, $cmnds );
            }
            else {
                $t->colon( $depends, $cmnds );
            }
        }
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
    my $was_rule = 0;
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
        elsif (/^\s*([^:]*)(::?)\s*(.*)$/) {
            my ( $target, $kind, $depend ) = ( $1, $2, $3 );
            my @cmnds;
            if ( $depend =~ /^([^;]*);(.*)$/ ) {
                ( $depend, $cmnds[0] ) = ( $1, $2 );
            }
            while ( defined( $_ = get_full_line($fh) ) ) {
                next if (/^\s*#/);
                next if (/^\s*$/);
                last unless (/^\t/);
                next if (/^\s*$/);
                s/^\s+//;
                push( @cmnds, $_ );
            }
            $was_rule = 1;
            $depend =~ s/\s\s+/ /;
            $target =~ s/\s\s+/ /;
            ($depend) = tokenize($depend);
            ($target) = tokenize($target);
            push @ast, [ 'rule', $target, $kind, $depend, \@cmnds ];
        }
        else {
            warn "Ignore '$_'\n";
        }
    }
    continue {
        $_        = get_full_line($fh) if !$was_rule;
        $was_rule = 0;
    }
    return \@ast;
}

sub pseudos {
    my $self = shift;
    foreach my $key (qw(SUFFIXES PHONY PRECIOUS PARALLEL)) {
        my $t = delete $self->{Dot}{ '.' . $key };
        if ( defined $t ) {
            $self->{$key} = {};
            foreach my $dep ( $t->colon->exp_depend ) {
                $self->{$key}{$dep} = 1;
            }
        }
    }
    return;
}

sub ExpandTarget {
    my $self = shift;
    foreach my $t ( @{ $self->{'Targets'} } ) {
        $t->ExpandTarget;
    }
    foreach my $t ( @{ $self->{'Targets'} } ) {
        $t->ProcessColon;
    }
    return;
}

sub parse {
    my ( $self, $file ) = @_;
    if ( !defined $file ) {
        my @files = qw(makefile Makefile);
        unshift( @files, 'GNUmakefile' ) if ( $self->{GNU} );
        foreach my $name (@files) {
            if ( -r $name ) {
                $self->{Makefile} = $name;
                last;
            }
        }
    }
    open( my $mf, "<", $file ) or croak("Cannot open $file: $!");
    my $ast = parse_makefile($mf);
    $self->process_ast_bit(@$_) for @$ast;
    close($mf);

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

sub exec {
    my $self = shift;
    undef %date;
    $generation++;
    return system @_;
}

## no critic (Subroutines::RequireFinalReturn)
sub NextPass { shift->{Pass}++ }
sub pass     { shift->{Pass} }
## use critic

## no critic (RequireArgUnpacking)
sub apply {
    my $self   = shift;
    my $method = shift;
    $self->NextPass;
    my @targets = ();

    # print STDERR join(' ',Apply => $method,@_),"\n";
    foreach (@_) {
        if (/^(\w+)=(.*)$/) {

            # print STDERR "OVERRIDE: $1 = $2\n";
            $self->set_var( $1, $2 );
        }
        else {
            push( @targets, $_ );
        }
    }
    #
    # This expansion is dubious as it alters the database
    # as a function of current values of Override.
    #
    $self->ExpandTarget;    # Process $(VAR) :
    @targets = ( $self->{'Targets'}[0] )->Name unless (@targets);

    # print STDERR join(' ',Targets => $method,map($_->Name,@targets)),"\n";
    foreach (@targets) {
        my $t = $self->{Depend}{$_};
        unless ( defined $t ) {
            print STDERR join( ' ', $method, @_ ), "\n";
            die "Cannot `$method' - no target $_";
        }
        $t->$method();
    }
    return;
}
## use critic

## no critic (Subroutines::RequireFinalReturn RequireArgUnpacking)
sub Script {
    shift->apply( Script => @_ );
}

sub Print {
    shift->apply( Print => @_ );
}

sub Make {
    shift->apply( Make => @_ );
}
## use critic

sub new {
    my ( $class, %args ) = @_;
    my $self = bless {
        Pattern => {},    # GNU style %.o : %.c
        Dot     => {},    # Trad style .c.o
        Vpath   => {},    # vpath %.c info
        Vars    => {},    # Variables defined in makefile
        Depend  => {},    # hash of targets
        Targets => [],    # ordered version so we can find 1st one
        Pass    => 0,     # incremented each sweep
        Need    => {},
        Done    => {},
        %args,
    }, $class;
    $self->set_var( 'CC',     $Config{cc} );
    $self->set_var( 'AR',     $Config{ar} );
    $self->set_var( 'CFLAGS', $Config{optimize} );
    my $ast = parse_makefile( \*DATA );
    $self->process_ast_bit(@$_) for @$ast;
    $self->parse( $self->{Makefile} );
    return $self;
}

=head1 NAME

Make - Pure-Perl implementation of a somewhat GNU-like make.

=head1 SYNOPSIS

    require Make;
    my $make = Make->new(Makefile => $file);
    $make->Make(@ARGV);

    # to see what it would have done
    $make->Script(@ARGV);

    # to see an expanded version of the makefile
    $make->Print(@ARGV);

    my $targ = $make->Target($name);
    $targ->colon([dependency...],[command...]);
    $targ->dcolon([dependency...],[command...]);
    my @depends  = $targ->colon->depend;
    my @commands = $targ->colon->command;

=head1 DESCRIPTION

The syntax of makefile accepted is reasonably generic, but I have not re-read
any documentation yet, rather I have implemented my own mental model of how
make works (then fixed it...).

In addition to traditional

	.c.o :
		$(CC) -c ...

GNU make's 'pattern' rules e.g.

	%.o : %.c
		$(CC) -c ...

Likewise a subset of GNU makes $(function arg...) syntax is supported.

Via pure-perl-make Make has built perl/Tk from the C<MakeMaker> generated
Makefiles...

=head1 METHODS

There are other methods (used by parse) which can be used to add and
manipulate targets and their dependants. There is a hierarchy of classes
which is still evolving. These classes and their methods will be documented when
they are a little more stable.

=head2 new

Class method, takes pairs of arguments in name/value form. Arguments:

=head3 Vars

A hash-ref of values that sets variables, overridable by the makefile.

=head3 Jobs

Number of concurrent jobs to run while building. Not implemented.

=head3 GNU

If true, then F<GNUmakefile> is looked for first.

=head3 Makefile

The file to parse. If not given, these files will be tried, in order:
F<GNUmakefile> if L</GNU>, F<makefile>, F<Makefile>.

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

=head1 ATTRIBUTES

These are read-only.

=head2 vars

Returns a hash-ref of the current set of variables.

=head1 FUNCTIONS

=head2 parse_makefile

Given a file-handle, returns array-ref of Abstract Syntax-Tree (AST)
fragments, representing the contents of that file. Each is an array-ref
whose first element is the node-type (C<comment>, C<include>, C<vpath>,
C<var>, C<rule>), followed by relevant data.

=head2 tokenize

Given a line, returns array-ref of the space-separated "tokens". GNU
make-style function calls will be a single token.

=head2 subsvars

Given a piece of text, will substitute any macros in it. Uses the
remaining args as a list of hashes to search for values.

Also understands these GNU-make style functions:

=head3 wildcard

Returns all its args expanded using C<glob>.

=head3 shell

Runs the command, returns the output with all newlines replaced by spaces.

=head3 addprefix

Prefixes second and succeeding args with first arg.

=head3 notdir

Returns everything after last C</>.

=head3 dir

Returns everything up to last C</>.

=head3 subst

In the third arg, replace every instance of first arg with second. E.g.:

    $(subst .o,.c,a.o b.o c.o)
    # becomes a.c b.c c.c

=head3 mktmp,(\S+)\s*(.*)$/ ) {

Like the dmake macro, but with mandatory file argument specified after
an immediate comma (C<,>). The text after further whitespace is inserted
in that file, whose name is returned. E.g.:

    $(mktmp,file.txt $(shell echo hi))
    # becomes file.txt, and that file contains "hi"

=head1 BUGS

More attention needs to be given to using the package to I<write> makefiles.

The rules for matching 'dot rules' e.g. .c.o   and/or pattern rules e.g. %.o : %.c
are suspect. For example give a choice of .xs.o vs .xs.c + .c.o behaviour
seems a little odd.

Variables are probably substituted in different 'phases' of the process
than in make(1) (or even GNU make), so 'clever' uses will probably not
work.

UNIXisms abound.

=head1 SEE ALSO

L<pure-perl-make>

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
