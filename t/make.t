#!perl
use Make;
#use Cwd;
use Test::More tests => 2;
my $m = Make->new(Makefile => "Makefile");
#ok(ref($m),'Make',"Make Object");
is ref($m), 'Make';
eval { $m->Make('all') };
is $@,'',;
