requires 'perl', '5.008001';

requires 'File::Temp';
requires 'File::Which';
requires 'IPC::Run3';

suggests 'Archive::Tar';
suggests 'Archive::Zip';

on develop => sub {
    requires 'File::pushd';
};
