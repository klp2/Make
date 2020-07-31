## no critic
package Make::Rule;

our $VERSION = '1.2.0';

use strict;
use warnings;
use Carp;
use Make::Rule::Vars;

# Bottom level 'rule' package
# An instance exists for each ':' or '::' rule in the makefile.
# The commands and dependancies are kept here.

sub target {
    return shift->{TARGET};
}

sub Name {
    return shift->target->Name;
}

sub Base {
    my $name = shift->target->Name;
    $name =~ s/\.[^.]+$//;
    return $name;
}

sub Info {
    return shift->target->Info;
}

sub depend {
    my $self = shift;
    if (@_) {
        my $name = $self->Name;
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
                warn "Command for " . $self->Name, " redefined";
                print STDERR "Was:", join( "\n", @{ $self->{COMMAND} } ), "\n";
                print STDERR "Now:", join( "\n", @$cmd ), "\n";
            }
            $self->{COMMAND} = $cmd;
        }
        else {
            if ( @{ $self->{COMMAND} } ) {

                # warn "Command for ".$self->Name," retained";
                # print STDERR "Was:",join("\n",@{$self->{COMMAND}}),"\n";
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
    my $info  = $self->Info;
    my @dep   = ();
    my $tdate = $self->target->date;
    my $count = 0;
    foreach my $dep ( @{ $self->depend } ) {

        # This is a dumb fix around regex issues with using Strawberry perl.
        # This may not fix for all versions of Strawberry perl or all versions
        # of windows, but is a hacky work-around until a real fix can be implemented
        if ( $^O eq 'MSWin32' ) {
            if ( $dep =~ m/libConfig.pm/ ) {
                $dep =~ s#libConfig.pm#lib\\Config.pm#;
            }
            if ( $dep =~ m/COREconfig.h/ ) {
                $dep =~ s#COREconfig.h#CORE\\config.h#;
            }
        }
        my $date = $info->date($dep);
        $count++;
        if ( !defined($date) || !defined($tdate) || $date < $tdate ) {

            # warn $self->Name." ood wrt ".$dep."\n";
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
    my $info      = $self->Info;
    my @subs_args = ( $info->function_packages, [ $self->auto_vars, $info->vars, \%ENV ] );
    my @cmd       = map Make::subsvars( $_, @subs_args ), @{ $self->command };
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
    my $obj = bless \%hash, ref $self;
    return $obj;
}

sub new {
    my $class  = shift;
    my $target = shift;
    my $kind   = shift;
    my $self   = bless {
        TARGET  => $target,              # parent target (left hand side)
        KIND    => $kind,                # : or ::
        DEPEND  => [], DEPHASH => {},    # right hand args
        COMMAND => []                    # command(s)
    }, $class;
    $self->depend(shift)  if (@_);
    $self->command(shift) if (@_);
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
        my $info = $self->Info;
        my @dep  = $self->depend;
        my @rule = $info->patrule( $self->Name );
        if (@rule) {
            $self->depend( $rule[0] );
            $self->command( $rule[1] );
        }
    }
}

#
# Normal 'make' method
#
sub Make {
    my $self = shift;
    return unless ( $self->out_of_date );
    return [ $self->Name, $self->exp_command ];
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
    print $self->Name, ' ', $self->{KIND}, ' ';
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
        print STDERR "No commands for ", $self->Name, "\n" unless ( $self->target->phony );
    }
    print "\n";
}

1;
