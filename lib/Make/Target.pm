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

sub Base {
    my $name = shift->{NAME};
    $name =~ s/\.[^.]+$//;
    return $name;
}

sub Info {
    return shift->{MAKEFILE};
}

sub done {
    my $self = shift;
    my $pass = $self->Info->pass;
    return 1 if ( $self->{Pass} == $pass );
    $self->{Pass} = $pass;
    return 0;
}

sub recurse {
    my ( $self, $method, @args ) = @_;
    return if $self->done;
    my $info = $self->Info;
    my @results;
    foreach my $rule ( $self->colon, $self->dcolon ) {
        foreach my $dep ( @{ $rule->depend } ) {
            my $t = $info->Target($dep);
            if ( defined $t ) {
                push @results, $t->recurse( $method, @args );
            }
            elsif ( !$info->exists($dep) ) {
                my $dir = cwd();
                die "Cannot recurse $method - no target $dep in $dir";
            }
        }
        push @results, $rule->$method(@args);
    }
    return @results;
}

1;
