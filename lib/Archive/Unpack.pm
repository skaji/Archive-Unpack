package Archive::Unpack;
use strict;
use warnings;

our $VERSION = '0.001';

use Command::Runner;
use File::Which ();

my $Init;
my $Backend = {};
our $_INIT_ALL; # for test

sub backend { $Backend }

sub new {
    my ($class, %argv) = @_;
    $class->_init if !$Init++;
    bless \%argv, $class;
}

sub unpack {
    my ($self, $file) = @_;
    my $method = $file =~ /\.zip$/ ? 'unzip' : 'untar';
    $self->$method($file);
}

sub _init {
    my $class = shift;

    no warnings 'once';

    # untar
    $Backend->{tar} = File::Which::which("tar");
    my $maybe_bad_tar = sub {
        return 1 if $^O eq 'MSWin32';
        return 1 if $^O eq 'solaris' || $^O eq 'hpux';
        my $cmd = Command::Runner->new(command => [$Backend->{tar}, '--version']);
        my $res = $cmd->run;
        $res->{stdout} =~ /GNU.*1\.13/i;
    };
    if ($Backend->{tar} and !$maybe_bad_tar->()) {
        *untar = *_untar;
    } elsif (
        $Backend->{tar} and
        $Backend->{gzip} = File::Which::which("gzip") and
        $Backend->{bzip2} = File::Which::which("bzip2")
    ) {
        *untar = *_untar_bad;
    } elsif (eval { require Archive::Tar }) {
        $Backend->{'Archive::Tar'} = 'Archive::Tar ' . Archive::Tar->VERSION;
        *untar = *_untar_module;
    } else {
        *untar = sub { die "There is no backend for untar" };
    }

    # unzip
    if ($Backend->{unzip} = File::Which::which("unzip")) {
        *unzip = *_unzip;
    } elsif (eval { require Archive::Zip }) {
        $Backend->{'Archive::Zip'} = 'Archive::Zip ' . Archive::Zip->VERSION;
        *unzip = *_unzip_module;
    } else {
        *unzip = sub { die "There is no backend for unzip" };
    }

    if ($_INIT_ALL) {
        for my $c (qw(tar gzip bzip2 unzip)) {
            $Backend->{$c} = File::Which::which($c);
        }
        for my $m (qw(Archive::Tar Archive::Zip)) {
            eval "require $m" or die $@;
            $Backend->{$m} = "$m ". $m->VERSION;
        }
    }
}

sub _untar {
    my ($self, $file) = @_;
    my $wantarray = wantarray;
    my $ar = $file =~ /bz2$/ ? 'j' : 'z';
    my $cmd = Command::Runner->new(command => [$Backend->{tar}, "${ar}tf", $file]);
    my $res = $cmd->run;
    if ($res->{result} != 0) {
        return if !$wantarray;
        return (undef, $res->{stderr});
    }
    my $root = $self->_find_root(split /\r?\n/, $res->{stdout});
    $cmd = Command::Runner->new(command => [$Backend->{tar}, "${ar}xf", $file]);
    $res = $cmd->run;
    if ($res->{result} == 0 and -d $root) {
        return $root;
    } else {
        return if !$wantarray;
        return (undef, $res->{stderr});
    }
}

sub _untar_bad {
    my ($self, $file) = @_;
    my $wantarray = wantarray;
    my $ar = $file =~ /bz2$/ ? $Backend->{bzip2} : $Backend->{gzip};
    my $cmd = Command::Runner->new(commandf => ['%q -dc %q | %q tf -', $ar, $file, $Backend->{tar}]);
    my $res = $cmd->run;
    if ($res->{result} != 0) {
        return if !$wantarray;
        return (undef, $res->{stderr});
    }
    my $root = $self->_find_root(split /\r?\n/, $res->{stdout});
    $cmd = Command::Runner->new(commandf => ['%q -dc %q | %q xf -', $ar, $file, $Backend->{tar}]);
    $res = $cmd->run;
    if ($res->{result} == 0 and -d $root) {
        return $root;
    } else {
        return if !$wantarray;
        return (undef, $res->{stderr});
    }
}

sub _untar_module {
    my ($self, $file) = @_;
    my $wantarray = wantarray;
    no warnings 'once';
    local $Archive::Tar::WARN = 0;
    my $t = Archive::Tar->new;
    my $ok = $t->read($file);
    if (!$ok) {
        return if !$wantarray;
        return (undef, $t->error);
    }
    my $root = $self->_find_root($t->list_files);
    my @file = $t->extract;
    if (@file and -d $root) {
        return $root;
    } else {
        return if !$wantarray;
        return (undef, $t->error);
    }
}

sub _find_root {
    my ($self, $root, @others) = @_;
    FILE: {
        chomp $root;
        $root =~ s!^\./!!;
        $root =~ s{^(.+?)/.*$}{$1};
        if (!length $root) { # archive had ./ as the first entry, so try again
            $root = shift @others;
            redo FILE if $root;
        }
    }
    $root;
}

sub _unzip {
    my ($self, $file) = @_;
    my $wantarray = wantarray;
    my $cmd = Command::Runner->new(command => [$Backend->{unzip}, '-t', $file]);
    my $res = $cmd->run;
    if ($res->{result} != 0) {
        return if !$wantarray;
        return (undef, $res->{stderr} || $res->{stdout});
    }
    my (undef, $root, @others) = split /\r?\n/, $res->{stdout};
    FILE: {
        chomp $root;
        if ($root !~ s{^\s+testing:\s+([^/]+)/.*?\s+OK$}{$1}) {
            $root = shift @others;
            redo FILE if $root;
        }
    }
    $cmd = Command::Runner->new(command => [$Backend->{unzip}, '-q', $file]);
    $res = $cmd->run;
    if ($res->{result} == 0 and -d $root) {
        return $root;
    } else {
        return if !$wantarray;
        return (undef, $res->{stderr} || $res->{stdout});
    }
}

sub _unzip_module {
    my ($self, $file) = @_;
    my $wantarray = wantarray;

    no warnings 'once';
    my $err = ''; local $Archive::Zip::ErrorHandler = sub { $err .= "@_" };
    my $zip = Archive::Zip->new;
    if ($zip->read($file) != Archive::Zip::AZ_OK()) {
        return if !$wantarray;
        return (undef, $err);
    }
    for my $member ($zip->members) {
        my $af = $member->fileName;
        next if $af =~ m!^(/|\.\./)!;
        if ($member->extractToFileNamed($af) != Archive::Zip::AZ_OK()) {
            return if !$wantarray;
            return (undef, $err);
        }
    }
    my ($root) = $zip->membersMatching(qr{^[^/]+/$});
    if ($root) {
        $root = $root->fileName;
        $root =~ s{/$}{};
        return $root if -d $root;
    }

    return if !$wantarray;
    return (undef, $err);
}

1;
__END__

=encoding utf-8

=head1 NAME

Archive::Unpack - unpack tarballs and zipballs

=head1 SYNOPSIS

  use Archive::Unpack;

  my $unpacker = Archive::Unpack->new;

  chdir "workspace";
  my $root1 = $unpacker->unpack("ModuleA-0.1.tar.gz");
  my $root2 = $unpacker->unpack("ModuleB-0.1.tar.bz2");
  my $root3 = $unpacker->unpack("ModuleC-0.1.zip");

=head1 DESCRIPTION

Archive::Unpack unpacks tarballs and zipballs.

=head1 AUTHOR

Shoichi Kaji <skaji@cpan.org>

=head1 COPYRIGHT AND LICENSE

Most of code are taken from L<App::cpanminus>, whose copyright and license are

  Copyright 2010- Tatsuhiko Miyagawa
  This software is licensed under the same terms as Perl.

Copyright 2018 Shoichi Kaji <skaji@cpan.org>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
