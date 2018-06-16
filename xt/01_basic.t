use strict;
use warnings;
use Test::More;

use Archive::Unpack;
use File::Basename 'basename';
use File::Copy 'copy';
use File::Spec::Functions 'catfile';
use File::Temp 'tempdir';
use File::pushd qw(tempd pushd);


my $store = tempdir CLEANUP => 1;
{
    my $guard = pushd $store;
    !system "wget", "-q", "https://cpan.metacpan.org/authors/id/C/CJ/CJOHNSTON/Win32-SystemInfo-0.11.zip" or die;
    !system "wget", "-q", "https://cpan.metacpan.org/authors/id/J/JJ/JJONES/Finance-OFX-Parse-Simple-0.07.zip" or die;

    !system "wget", "-q", "https://cpan.metacpan.org/authors/id/S/SK/SKAJI/CPAN-Flatten-0.01.tar.gz" or die;
    !system "wget", "-q", "https://ftp.gnu.org/gnu/m4/m4-1.4.3.tar.bz2" or die;
}

$Archive::Unpack::_INIT_ALL = 1;
my $unpacker = Archive::Unpack->new;
note explain $unpacker->backend;

my $test = sub {
    my $method = shift;
    subtest $method => sub {
        my $guard = tempd;
        if ($method !~ /unzip/) {
            ok !$unpacker->$method("__bad__.tar.gz");

            my $root1 = $unpacker->$method(catfile($store, "CPAN-Flatten-0.01.tar.gz"));
            is $root1, "CPAN-Flatten-0.01";
            my $root2 = $unpacker->$method(catfile($store, "m4-1.4.3.tar.bz2"));
            is $root2, "m4-1.4.3";
        }

        if ($method !~ /untar/) {
            ok !$unpacker->$method("__bad__.zip");

            my $root1 = $unpacker->$method(catfile($store, "Win32-SystemInfo-0.11.zip"));
            is $root1, "Win32-SystemInfo-0.11";
            my $root2 = $unpacker->$method(catfile($store, "Finance-OFX-Parse-Simple-0.07.zip"));
            is $root2, "Finance--OFX--Parse--Simple-master";
        }
    };
};

$test->($_) for qw(unpack unzip _unzip _unzip_module untar _untar _untar_bad _untar_module);

opendir my $dh, $store or die;
my @entory = grep { !/^\.\.?$/ } readdir $dh;
close $dh;
is @entory, 4;

done_testing;
