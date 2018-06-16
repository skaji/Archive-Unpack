requires 'perl', '5.008001';

requires 'File::Which';
requires 'Command::Runner';

suggests 'Archive::Tar';
suggests 'Archive::Zip';

on develop => sub {
    requires 'File::pushd';
};
