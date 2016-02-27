#!perl
use Make;
use Cwd;
use Test;    
BEGIN { plan tests => 2 };
my $m = Make->new(Makefile => "Makefile");
ok(ref($m),'Make',"Make Object");
eval { $m->Make('all') };
ok($@,'',"Make all");

