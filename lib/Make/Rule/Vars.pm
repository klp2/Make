package Make::Rule::Vars;

use strict;
use warnings;
use Carp;

our $VERSION = '1.2.0';

# Package to handle automatic variables pertaining to rules e.g. $@ $* $^ $?
# by using tie to this package 'subsvars' can work with array of
# hash references to possible sources of variable definitions.

sub TIEHASH {
    my ( $class, $rule ) = @_;
    return bless \$rule, $class;
}

sub FETCH {
    my ( $self, $v ) = @_;
    my $rule = $$self;

    # print STDERR "FETCH $_ for ",$rule->Name,"\n";
    return $rule->Name if $v eq '@';
    return $rule->Base if $v eq '*';
    return join ' ', @{ $rule->depend } if $v eq '^';
    return join ' ', $rule->out_of_date if $v eq '?';
    return ( @{ $rule->depend } )[0] if $v eq '<';
    return;
}

1;
