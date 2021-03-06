use strict;
use warnings;

use ExtUtils::MakeMaker;

my %WriteMakefileArgs = (
    "ABSTRACT"           => "module for processing makefiles",
    "AUTHOR"             => "Nick Ing-Simmons",
    "CONFIGURE_REQUIRES" => {
        "ExtUtils::MakeMaker" => 0
    },
    "VERSION_FROM" => "lib/Make.pm",
    "NAME"         => "Make",
    "EXE_FILES"    => [ glob 'scripts/*' ],
    "LICENSE"      => "perl",
    "META_MERGE"   => {
        dynamic_config => 0,
        'meta-spec'    => { version   => 2 },
        no_index       => { directory => ['t'] },
        prereqs        => {
            develop => {
                requires => {
                    "Test::Version"       => "1.003001",
                    "Test::Pod"           => "1.00",
                    "Test::Code::TidyAll" => "0.41",
                    "Test::Perl::Critic"  => "1.02",
                    "Perl::Tidy"          => "20200822",    # new formatting
                },
            },
            test => {
                requires => {
                    'Test::More' => '0.82',                 # explain
                },
                recommends => {
                    'App::Prove' => '3.00',                 # prove -j4
                },
            },
        },
        resources => {
            bugtracker => { web => 'https://github.com/klp2/Make/issues' },
            homepage   => 'https://metacpan.org/pod/Make',
            repository => {
                type => 'git',
                url  => 'https://github.com/klp2/Make.git',
                web  => 'https://github.com/klp2/Make',
            },
            x_IRC => 'irc://irc.perl.org/#perl'
        },
    },
    "MIN_PERL_VERSION" => "5.006",
    "PREREQ_PM"        => {
        "Carp"             => 0,
        "Config"           => 0,
        "Cwd"              => 0,
        "File::Spec"       => 0,
        "strict"           => 0,
        "warnings"         => 0,
        "Text::Balanced"   => '2.03',
        "Text::ParseWords" => '3.24',
        "Graph"            => '0.9712',    # TC with multiedged
    },
    "TEST_REQUIRES" => {
        "Test::More"     => "1.00",
        'Test::Snapshot' => '0.06',
    },
);

my %FallbackPrereqs = (
    "Carp"                => 0,
    "Config"              => 0,
    "Cwd"                 => 0,
    "File::Spec"          => 0,
    "ExtUtils::MakeMaker" => 0,
    "File::Spec"          => 0,
    "Test::More"          => "1.00",
    "Text::Balanced"      => '2.03',
    "Text::ParseWords"    => '3.30',
    "strict"              => 0,
    "warnings"            => 0,
);

unless ( eval { ExtUtils::MakeMaker->VERSION(6.63_03) } ) {
    delete $WriteMakefileArgs{TEST_REQUIRES};
    delete $WriteMakefileArgs{BUILD_REQUIRES};
    $WriteMakefileArgs{PREREQ_PM} = \%FallbackPrereqs;
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
    unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);
