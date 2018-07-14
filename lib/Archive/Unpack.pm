package Archive::Unpack;
use strict;
use warnings;

our $VERSION = '0.001';

use File::Temp ();
use File::Which ();
use IPC::Run3 ();

sub _run3 {
    my ($cmd, $outfile) = @_;
    my $out;
    IPC::Run3::run3 $cmd, \undef, ($outfile ? $outfile : \$out), \my $err;
    return ($?, $out, $err);
}

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
        return 1 if $^O eq 'MSWin32' || $^O eq 'solaris' || $^O eq 'hpux';
        my ($exit, $out, $err) = _run3 [$Backend->{tar}, '--version'];
        $out =~ /GNU.*1\.13/i;
    };
    if ($Backend->{tar} and !$maybe_bad_tar->()) {
        *untar = *_untar;
    } elsif (
        $Backend->{tar} and
        $Backend->{gzip} = File::Which::which("gzip") and
        $Backend->{bzip2} = File::Which::which("bzip2")
    ) {
        *untar = *_untar_bad;
        $Backend->{xz} = File::Which::which("xz"); # optional xz
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
        for my $c (qw(tar gzip bzip2 xz unzip)) {
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

    my ($exit, $out, $err);
    {
        my $ar = $file =~ /\.xz$/ ? 'J' : $file =~ /\.bz2$/ ? 'j' : 'z';
        ($exit, $out, $err) = _run3 [$Backend->{tar}, "${ar}tf", $file];
        last if $exit != 0;
        my $root = $self->_find_tarroot(split /\r?\n/, $out);
        ($exit, $out, $err) = _run3 [$Backend->{tar}, "${ar}xf", $file];
        return $root if $exit == 0 and -d $root;
    }
    return if !$wantarray;
    return (undef, $err || $out);
}

sub _untar_bad {
    my ($self, $file) = @_;
    my $wantarray = wantarray;
    my ($exit, $out, $err);
    {
        my $ar = $file =~ /\.xz$/  ? $Backend->{xz}
               : $file =~ /\.bz2$/ ? $Backend->{bzip2}
               :                     $Backend->{gzip};
        die "There is no backend for xz" if !$ar;
        my $temp = File::Temp->new(SUFFIX => '.tar', EXLOCK => 0);
        ($exit, $out, $err) = _run3 [$ar, "-dc", $file], $temp->filename;
        last if $exit != 0;

        # XXX /usr/bin/tar: Cannot connect to C: resolve failed
        my @opt = $^O eq 'MSWin32' ? ('--force-local') : ();

        ($exit, $out, $err) = _run3 [$Backend->{tar}, @opt, "-tf", $temp->filename];
        last if $exit != 0 || !$out;
        my $root = $self->_find_tarroot(split /\r?\n/, $out);
        ($exit, $out, $err) = _run3 [$Backend->{tar}, @opt, "-xf", $temp->filename];
        return $root if $exit == 0 and -d $root;
    }
    return if !$wantarray;
    return (undef, $err || $out);
}

sub _untar_module {
    my ($self, $file) = @_;
    my $wantarray = wantarray;
    no warnings 'once';
    local $Archive::Tar::WARN = 0;
    my $t = Archive::Tar->new;
    {
        my $ok = $t->read($file);
        last if !$ok;
        my $root = $self->_find_tarroot($t->list_files);
        my @file = $t->extract;
        return $root if @file and -d $root;
    }
    return if !$wantarray;
    return (undef, $t->error);
}

sub _find_tarroot {
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

    my ($exit, $out, $err);
    {
        ($exit, $out, $err) = _run3 [$Backend->{unzip}, '-t', $file];
        last if $exit != 0;
        my $root = $self->_find_ziproot(split /\r?\n/, $out);
        ($exit, $out, $err) = _run3 [$Backend->{unzip}, '-q', $file];
        return $root if $exit == 0 and -d $root;
    }
    return if !$wantarray;
    return (undef, $err || $out);
}

sub _unzip_module {
    my ($self, $file) = @_;
    my $wantarray = wantarray;

    no warnings 'once';
    my $err = ''; local $Archive::Zip::ErrorHandler = sub { $err .= "@_" };
    my $zip = Archive::Zip->new;
    UNZIP: {
        my $status = $zip->read($file);
        last UNZIP if $status != Archive::Zip::AZ_OK();
        for my $member ($zip->members) {
            my $af = $member->fileName;
            next if $af =~ m!^(/|\.\./)!;
            my $status = $member->extractToFileNamed($af);
            last UNZIP if $status != Archive::Zip::AZ_OK();
        }
        my ($root) = $zip->membersMatching(qr{^[^/]+/$});
        last UNZIP if !$root;
        $root = $root->fileName;
        $root =~ s{/$}{};
        return $root if -d $root;
    }
    return if !$wantarray;
    return (undef, $err);
}

sub _find_ziproot {
    my ($self, undef, $root, @others) = @_;
    FILE: {
        chomp $root;
        if ($root !~ s{^\s+testing:\s+([^/]+)/.*?\s+OK$}{$1}) {
            $root = shift @others;
            redo FILE if $root;
        }
    }
    $root;
}

1;
__END__

=encoding utf-8

=head1 NAME

Archive::Unpack - unpack tarballs and zipballs

=head1 SYNOPSIS

  use Archive::Unpack;

  my $archive = Archive::Unpack->new;

  chdir "workspace";

  # unpack tarballs and zipballs in workspace/
  my $root1 = $archive->unpack("/path/to/ModuleA-0.1.tar.gz");
  my $root2 = $archive->unpack("/path/to/ModuleB-0.1.tar.bz2");
  my $root3 = $archive->unpack("/path/to/ModuleC-0.1.zip");

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
