package Make::Target;

use strict;
use warnings;

our $VERSION = '1.2.0';

use Carp;
use Cwd;
use Make::Rule;

#
# Intermediate 'target' package
# There is an instance of this for each 'target' that apears on
# the left hand side of a rule i.e. for each thing that can be made.
#
sub new {
    my ( $class, $info, $target ) = @_;
    return bless {
        NAME     => $target,    # name of thing
        MAKEFILE => $info,      # Makefile context
        Pass     => 0           # Used to determine if 'done' this sweep
    }, $class;
}

sub date {
    my $self = shift;
    my $info = $self->Info;
    return $info->date( $self->Name );
}

sub phony {
    my $self = shift;
    return $self->Info->phony( $self->Name );
}

## no critic (RequireArgUnpacking)
sub colon {
    my $self = shift;
    if (@_) {
        if ( exists $self->{COLON} ) {
            my $dep = $self->{COLON};
            if ( @_ == 1 ) {

                # merging an existing rule
                my $other = shift;
                $dep->depend( scalar $other->depend );
                $dep->command( $other->command );
            }
            else {
                $dep->depend(shift);
                $dep->command(shift);
            }
        }
        else {
            $self->{COLON} = ( @_ == 1 ) ? shift->clone($self) : Make::Rule->new( $self, ':', @_ );
        }
    }
    return exists $self->{COLON} ? $self->{COLON} : ();
}

sub dcolon {
    my $self = shift;
    if (@_) {
        my $rule = ( @_ == 1 ) ? shift->clone($self) : Make::Rule->new( $self, '::', @_ );
        $self->{DCOLON} = [] unless ( exists $self->{DCOLON} );
        push( @{ $self->{DCOLON} }, $rule );
    }
    return ( exists $self->{DCOLON} ) ? @{ $self->{DCOLON} } : ();
}

sub Name {
    return shift->{NAME};
}

sub Info {
    return shift->{MAKEFILE};
}

sub ProcessColon {
    my ($self) = @_;
    my $c = $self->colon;
    $c->find_commands if $c;
    return;
}

sub ExpandTarget {
    my ($self) = @_;
    my $target = $self->Name;
    my $info   = $self->Info;
    my $colon  = delete $self->{COLON};
    my $dcolon = delete $self->{DCOLON};
    foreach my $expand ( split( /\s+/, Make::subsvars( $target, $info->function_packages, $info->vars, \%ENV ) ) ) {
        next unless defined($expand);
        my $t = $info->Target($expand);
        if ( defined $colon ) {
            $t->colon($colon);
        }
        foreach my $d ( @{$dcolon} ) {
            $t->dcolon($d);
        }
    }
    return;
}

sub done {
    my $self = shift;
    my $info = $self->Info;
    my $pass = $info->pass;
    return 1 if ( $self->{Pass} == $pass );
    $self->{Pass} = $pass;
    return 0;
}

sub recurse {
    my ( $self, $method, @args ) = @_;
    my $info = $self->Info;
    my $i    = 0;
    foreach my $rule ( $self->colon, $self->dcolon ) {
        my $j = 0;
        foreach my $dep ( $rule->exp_depend ) {
            my $t = $info->{Depend}{$dep};
            if ( defined $t ) {
                $t->$method(@args);
            }
            else {
                unless ( $info->exists($dep) ) {
                    my $dir = cwd();
                    die "Cannot recurse $method - no target $dep in $dir";
                }
            }
        }
    }
    return;
}

sub Script {
    my $self = shift;
    my $info = $self->Info;
    my $rule = $self->colon;
    return if ( $self->done );
    $self->recurse('Script');
    foreach my $rule ( $self->colon, $self->dcolon ) {
        $rule->Script;
    }
    return;
}

sub Make {
    my $self = shift;
    my $info = $self->Info;
    my $rule = $self->colon;
    return if ( $self->done );
    $self->recurse('Make');
    foreach my $rule ( $self->colon, $self->dcolon ) {
        $rule->Make;
    }
    return;
}

sub Print {
    my $self = shift;
    my $info = $self->Info;
    return if ( $self->done );
    my $rule = $self->colon;
    foreach my $rule ( $self->colon, $self->dcolon ) {
        $rule->Print;
    }
    $self->recurse('Print');
    return;
}

1;
