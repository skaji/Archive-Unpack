[![Build Status](https://travis-ci.com/skaji/Archive-Unpack.svg?branch=master)](https://travis-ci.com/skaji/Archive-Unpack)
[![AppVeyor Status](https://ci.appveyor.com/api/projects/status/github/skaji/Archive-Unpack?branch=master&svg=true)](https://ci.appveyor.com/project/skaji/Archive-Unpack)

# NAME

Archive::Unpack - unpack tarballs and zipballs

# SYNOPSIS

    use Archive::Unpack;

    my $unpacker = Archive::Unpack->new;

    chdir "workspace";
    my $root1 = $unpacker->unpack("ModuleA-0.1.tar.gz");
    my $root2 = $unpacker->unpack("ModuleB-0.1.tar.bz2");
    my $root3 = $unpacker->unpack("ModuleC-0.1.zip");

# DESCRIPTION

Archive::Unpack unpacks tarballs and zipballs.

# AUTHOR

Shoichi Kaji <skaji@cpan.org>

# COPYRIGHT AND LICENSE

Most of code are taken from [App::cpanminus](https://metacpan.org/pod/App::cpanminus), whose copyright and license are

    Copyright 2010- Tatsuhiko Miyagawa
    This software is licensed under the same terms as Perl.

Copyright 2018 Shoichi Kaji <skaji@cpan.org>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.
