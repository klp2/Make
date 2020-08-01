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
    my ( $class, $name, $info ) = @_;
    return bless {
        NAME      => $name,    # name of thing
        MAKEFILE  => $info,    # Makefile context
        RULES     => [],
        RULE_TYPE => undef,    # undef, :, ::
        Pass      => 0,        # Used to determine if 'done' this sweep
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

sub rules {
    return shift->{RULES};
}

sub add_rule {
    my ( $self, $rule ) = @_;
    my $new_kind = $rule->kind;
    my $kind     = $self->{RULE_TYPE} ||= $new_kind;
    die "Target '$self->{NAME}' had '$kind' but tried to add '$new_kind'"
        if $kind ne $new_kind;
    return push @{ shift->{RULES} }, $rule;
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
    foreach my $rule ( @{ $self->rules } ) {
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
