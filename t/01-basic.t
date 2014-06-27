use strict;
use warnings FATAL => 'all';

use Test::More;
use if $ENV{AUTHOR_TESTING}, 'Test::Warnings';
use Test::DZil;
use Path::Tiny;
use File::pushd 'pushd';
use Test::Deep;
use Test::Deep::YAML 0.002;

my $tzil = Builder->from_config(
    { dist_root => 't/does-not-exist' },
    {
        add_files => {
            path(qw(source dist.ini)) => simple_ini(
                [ GatherDir => ],
                [ MetaYAML => ],
                [ 'Test::CheckBreaks' => { conflicts_module => 'Moose::Conflicts' } ],
            ),
            path(qw(source lib Foo.pm)) => "package Foo;\n1;\n",
        },
    },
);

$tzil->chrome->logger->set_debug(1);
$tzil->build;

my $build_dir = path($tzil->tempdir)->child('build');
my $file = path($build_dir, 't', 'zzz-check-breaks.t');
ok(-e $file, 'test created');

my $content = $file->slurp;
unlike($content, qr/[^\S\n]\n/m, 'no trailing whitespace in generated test');

# it's important we require using an eval'd string rather than via a bareword,
# so prereq scanners don't grab this module (::Conflicts modules are not
# usually indexed)
like($content, qr/eval 'require $_; $_->check_conflicts'/m, "test checks $_")
    for 'Moose::Conflicts';

# note - YAML.pm wants characters, not octets
my $yaml = $tzil->slurp_file('build/META.yml');
cmp_deeply(
    $yaml,
    yaml(
        code(sub {
            my $val = shift;
            return 1 if not exists $val->{x_breaks};
            return (0, 'x_breaks field exists')
        })
    ),
    'metadata does not get an autovivified x_breaks field',
);

subtest 'run the generated test' => sub
{
    my $wd = pushd $build_dir;
    do $file;
    warn $@ if $@;
};

diag 'saw log messages: ', explain $tzil->log_messages if not Test::Builder->new->is_passing;

done_testing;
