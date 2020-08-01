package Make::Rule;

use strict;
use warnings;
use Carp;
use Make::Rule::Vars;
## no critic (ValuesAndExpressions::ProhibitConstantPragma)
use constant DEBUG => $ENV{MAKE_DEBUG};
## use critic

our $VERSION = '1.2.0';

# Bottom level 'rule' package
# An instance exists for each ':' or '::' rule in the makefile.
# The commands and dependancies are kept here.

sub target {
    return shift->{TARGET};
}

sub depend {
    my $self = shift;
    if (@_) {
        my $name = $self->target->Name;
        my $dep  = shift;
        confess "dependents $dep are not an array reference" unless ( 'ARRAY' eq ref $dep );
        foreach my $file (@$dep) {
            unless ( exists $self->{DEPHASH}{$file} ) {
                $self->{DEPHASH}{$file} = 1;
                push( @{ $self->{DEPEND} }, $file );
            }
        }
    }
    return $self->{DEPEND};
}

sub command {
    my $self = shift;
    if (@_) {
        my $cmd = shift;
        confess "commands $cmd are not an array reference" unless ( 'ARRAY' eq ref $cmd );
        if (@$cmd) {
            if ( @{ $self->{COMMAND} } ) {
                warn "Command for " . $self->target->Name, " redefined",
                    "Was:", join( "\n", @{ $self->{COMMAND} } ), "\n",
                    "Now:", join( "\n", @$cmd ), "\n";
            }
            $self->{COMMAND} = $cmd;
        }
        else {
            if ( @{ $self->{COMMAND} } ) {
                DEBUG
                    and warn "Command for " . $self->target->Name, " retained\n",
                    "Was:", join( "\n", @{ $self->{COMMAND} } ), "\n";
            }
        }
    }
    return $self->{COMMAND};
}

#
# The key make test - is target out-of-date as far as this rule is concerned
# In scalar context - boolean value of 'do we need to apply the rule'
# In list context the things we are out-of-date with e.g. magic $? variable
#
sub out_of_date {
    my $self  = shift;
    my $info  = $self->target->Info;
    my @dep   = ();
    my $tdate = $self->target->date;
    my $count = 0;
    foreach my $dep ( @{ $self->depend } ) {
        my $date = $info->date($dep);
        $count++;
        if ( !defined($date) || !defined($tdate) || $date < $tdate ) {

            # warn $self->target->Name." ood wrt ".$dep."\n";
            return 1 unless wantarray;
            push( @dep, $dep );
        }
    }
    return @dep if wantarray;

    # Note special case of no dependencies means it is always  out-of-date!
    return !$count;
}

sub auto_vars {
    my ($self) = @_;
    my %var;
    tie %var, 'Make::Rule::Vars', $self;
    return \%var;
}

#
# Return commands to apply rule with variables expanded
# - May need vpath processing
#
sub exp_command {
    my $self      = shift;
    my $info      = $self->target->Info;
    my @subs_args = ( $info->function_packages, [ $self->auto_vars, $info->vars, \%ENV ] );
    ## no critic (BuiltinFunctions::RequireBlockMap)
    my @cmd = map Make::subsvars( $_, @subs_args ), @{ $self->command };
    ## use critic
    return (wantarray) ? @cmd : \@cmd;
}

#
# clone creates a new rule derived from an existing rule, but
# with a different target. Used when left hand side was a variable.
# perhaps should be used for dot/pattern rule processing too.
#
sub clone {
    my ( $self, $target ) = @_;
    my %hash = %$self;
    $hash{TARGET}  = $target;
    $hash{DEPEND}  = [ @{ $self->{DEPEND} } ];
    $hash{DEPHASH} = { %{ $self->{DEPHASH} } };
    return bless \%hash, ref $self;
}

sub new {
    my ( $class, $target, $kind, $depend, $command ) = @_;
    my $self = bless {
        TARGET  => $target,              # parent target (left hand side)
        KIND    => $kind,                # : or ::
        DEPEND  => [], DEPHASH => {},    # right hand args
        COMMAND => []                    # command(s)
    }, $class;
    $self->depend($depend)   if $depend;
    $self->command($command) if $command;
    return $self;
}

#
# This code has to go somewhere but no good home obvious yet.
#  - only applies to ':' rules, but needs top level database
#  - perhaps in ->commands of derived ':' class?
#
sub find_commands {
    my ($self) = @_;
    if ( !@{ $self->{COMMAND} } && @{ $self->{DEPEND} } ) {
        my $info = $self->target->Info;
        my @dep  = $self->depend;
        my @rule = $info->patrule( $self->target->Name );
        if (@rule) {
            $self->depend( $rule[0] );
            $self->command( $rule[1] );
        }
    }
    return;
}

#
# Normal 'make' method
#
sub Make {
    my $self = shift;
    return unless ( $self->out_of_date );
    return [ $self->target->Name, $self->exp_command ];
}

#
# Print rule out in makefile syntax
# - currently has variables expanded as debugging aid.
# - will eventually become make -p
# - may be useful for writing makefiles from MakeMaker too...
#
sub Print {
    my $self = shift;
    my $file;
    print $self->target->Name, ' ', $self->{KIND}, ' ';
    foreach my $file ( $self->depend ) {
        print " \\\n   $file";
    }
    print "\n";
    my @cmd = $self->exp_command;
    if (@cmd) {
        foreach my $file (@cmd) {
            print "\t", $file, "\n";
        }
    }
    else {
        print STDERR "No commands for ", $self->target->Name, "\n" unless ( $self->target->phony );
    }
    print "\n";
    return;
}

=head1 NAME

Make::Rule - a rule with prerequisites and recipe

=head1 SYNOPSIS

    my $rule = Make::Rule->new( $target, $kind[, $depend[, $command]] );
    my $clone = $rule->clone($target);
    my @name_commands = $rule->Make;
    my $target = $rule->target; # Make::Target obj
    my @deps = @{ $rule->depend };
    my @cmds = @{ $rule->command };
    my @expanded_cmds = @{ $rule->exp_command }; # vars expanded
    my @ood = $rule->out_of_date;
    my $vars = $rule->auto_vars; # tied hash-ref

=head1 DESCRIPTION

Represents a rule.

=cut

1;
