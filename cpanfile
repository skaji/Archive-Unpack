requires 'perl', '5.008001';

requires 'File::Temp', '0.22';
requires 'File::Which';
requires 'IPC::Run3';

suggests 'Archive::Tar';
suggests 'Archive::Zip';

on develop => sub {
    requires 'File::pushd';
};
