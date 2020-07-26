package Make::Functions;

use strict;
use warnings;

our $VERSION = '1.2.0';

my @temp_handles;    # so they don't get destroyed before end of program

sub wildcard {
    my ( $first_comma, $text_input ) = @_;
    return glob $text_input;
}

sub shell {
    my ( $first_comma, $text_input ) = @_;
    my $value = `$text_input`;
    chomp $value;
    return split "\n", $value;
}

sub addprefix {
    my ( $first_comma, $text_input ) = @_;
    $text_input =~ /([^,]*),(.*)/;
    ## no critic (BuiltinFunctions::RequireBlockMap)
    return map $1 . $_, split /\s+/, $2;
    ## use critic
}

sub notdir {
    my ( $first_comma, $text_input ) = @_;
    my @files = split( /\s+/, $text_input );
    s#^.*/## for @files;
    return @files;
}

sub dir {
    my ( $first_comma, $text_input ) = @_;
    my @files = split( /\s+/, $text_input );
    foreach (@files) {
        $_ = './' unless s#^(.*)/[^/]*$#$1#;
    }
    return @files;
}

sub subst {
    my ( $first_comma, $text_input ) = @_;
    my ( $from, $to, $value ) = split /,/, $text_input, 3;
    $from = quotemeta $from;
    $value =~ s/$from/$to/g;
    return $value;
}

sub patsubst {
    my ( $first_comma, $text_input ) = @_;
    my ( $from, $to, $value ) = split /,/, $text_input, 3;
    $from = quotemeta $from;
    $value =~ s/$from(?=(?:\s|\z))/$to/g;
    return $value;
}

sub mktmp {
    my ( $file, $content, $fh ) = @_;
    if ( defined $file ) {
        open( my $tmp, ">", $file ) or die "Cannot open $file: $!";
        $fh = $tmp;
    }
    else {
        $fh = File::Temp->new;    # default UNLINK = 1
        push @temp_handles, $fh;
        $file = $fh->filename;
    }
    print $fh $content;
    return $file;
}

=head1 NAME

Make::Functions - Functions in Makefile macros

=head1 SYNOPSIS

    require Make::Functions;
    my ($dir) = Make::Functions::dir("x/y");
    # $dir now "x"

=head1 DESCRIPTION

Package that contains the various functions used by L<Make>.

=head1 FUNCTIONS

Implements GNU-make style functions. The call interface for all these
Perl functions is:

    my @return_list = func($first_comma, $text_args);

The C<$first_comma> will be undefined unless there was a comma and word
straight after the function name.

=head2 wildcard

Returns all its args expanded using C<glob>.

=head2 shell

Runs the command, returns the output with all newlines replaced by spaces.

=head2 addprefix

Prefixes each word in the second arg with first arg:

    $(addprefix x/,1 2)
    # becomes x/1 x/2

=head2 notdir

Returns everything after last C</>.

=head2 dir

Returns everything up to last C</>. If no C</>, returns C<./>.

=head2 subst

In the third arg, replace every instance of first arg with second. E.g.:

    $(subst .o,.c,a.o b.o c.o)
    # becomes a.c b.c c.c

=head2 patsubst

Like L</subst>, but only operates when the pattern is at the end of
a word.

=head2 mktmp

Like the dmake macro. The C<$first_comma> is the optional file argument
specified after an immediate comma (C<,>).

The text after further whitespace is inserted in that file, whose name
is returned. E.g.:

    $(mktmp,file.txt $(shell echo hi))
    # becomes file.txt, and that file contains "hi"

    $(mktmp $(shell echo hi))
    # becomes a temporary filename, and that file contains "hi"

=head1 COPYRIGHT AND LICENSE

Copyright (c) 1996-1999 Nick Ing-Simmons.

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

1;
