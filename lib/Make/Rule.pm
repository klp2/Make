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

sub depend {
    return shift->{DEPEND};
}

sub command {
    return shift->{COMMAND};
}

#
# The key make test - is target out-of-date as far as this rule is concerned
# In scalar context - boolean value of 'do we need to apply the rule'
# In list context the things we are out-of-date with e.g. magic $? variable
#
sub out_of_date {
    my ( $self, $target ) = @_;
    my $info  = $target->Info;
    my @dep   = ();
    my $tdate = $target->date;
    my $count = 0;
    foreach my $dep ( @{ $self->depend } ) {
        my $date = $info->date($dep);
        $count++;
        if ( !defined($date) || !defined($tdate) || $date < $tdate ) {

            # warn $target->Name." ood wrt ".$dep."\n";
            return 1 unless wantarray;
            push( @dep, $dep );
        }
    }
    return @dep if wantarray;

    # Note special case of no dependencies means it is always  out-of-date!
    return !$count;
}

sub auto_vars {
    my ( $self, $target ) = @_;
    my %var;
    tie %var, 'Make::Rule::Vars', $self, $target;
    return \%var;
}

#
# Return commands to apply rule with variables expanded
# - May need vpath processing
#
sub exp_command {
    my ( $self, $target ) = @_;
    my $info      = $target->Info;
    my @subs_args = ( $info->function_packages, [ $self->auto_vars($target), $info->vars, \%ENV ] );
    ## no critic (BuiltinFunctions::RequireBlockMap)
    my @cmd = map Make::subsvars( $_, @subs_args ), @{ $self->command };
    ## use critic
    return (wantarray) ? @cmd : \@cmd;
}

sub new {
    my ( $class, $kind, $depend, $command ) = @_;
    confess "dependents $depend are not an array reference"
        if 'ARRAY' ne ref $depend;
    confess "commands $command are not an array reference"
        if 'ARRAY' ne ref $command;
    return bless {
        KIND    => $kind,       # : or ::
        DEPEND  => $depend,     # right hand args
        COMMAND => $command,    # commands
    }, $class;
}

sub kind {
    return shift->{KIND};
}

#
# This code has to go somewhere but no good home obvious yet.
#  - only applies to ':' rules, but needs top level database
#  - perhaps in ->commands of derived ':' class?
#
sub find_commands {
    my ( $self, $target ) = @_;
    if ( !@{ $self->{COMMAND} } && @{ $self->{DEPEND} } ) {
        my $info = $target->Info;
        my @dep  = $self->depend;
        my @rule = $info->patrule( $target->Name );
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
    my ( $self, $target ) = @_;
    return unless ( $self->out_of_date($target) );
    return [ $target->Name, $self->exp_command($target) ];
}

#
# Print rule out in makefile syntax
# - currently has variables expanded as debugging aid.
# - will eventually become make -p
# - may be useful for writing makefiles from MakeMaker too...
#
sub Print {
    my ( $self, $target ) = @_;
    my $file;
    print $target->Name, ' ', $self->{KIND}, ' ';
    foreach my $file ( $self->depend ) {
        print " \\\n   $file";
    }
    print "\n";
    my @cmd = $self->exp_command($target);
    if (@cmd) {
        foreach my $file (@cmd) {
            print "\t", $file, "\n";
        }
    }
    else {
        print STDERR "No commands for ", $target->Name, "\n" unless ( $self->target->phony );
    }
    print "\n";
    return;
}

=head1 NAME

Make::Rule - a rule with prerequisites and recipe

=head1 SYNOPSIS

    my $rule = Make::Rule->new( $kind, \@depend, \@command );
    my @name_commands = $rule->Make($target);
    my @deps = @{ $rule->depend };
    my @cmds = @{ $rule->command };
    my @expanded_cmds = @{ $rule->exp_command($target) }; # vars expanded
    my @ood = $rule->out_of_date($target);
    my $vars = $rule->auto_vars($target); # tied hash-ref

=head1 DESCRIPTION

Represents a rule.

=cut

1;
