requires 'perl', '5.008001';

requires 'Cache::FastMmap';
requires 'File::Temp';
requires 'POSIX::AtFork';
requires 'JSON';

on 'test' => sub {
    requires 'Test::More', '0.98';
};

