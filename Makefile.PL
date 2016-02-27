use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME'     => 'Make',
    'EXE_FILES' => ['pmake'],
    'clean' => {FILES => "*% *.bak Make/*%"},
    'linkext' => { LINKTYPE => ''},
    'dist'     => { COMPRESS => 'gzip -f', SUFFIX => 'gz' },
    'VERSION_FROM'  => 'Make.pm'
);


