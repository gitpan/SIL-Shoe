#!/usr/bin/perl

use File::Compare;
use Test::Simple tests => 2;

run_perl('scripts/sh2xml', '-f', '-s', 't/Thai', 't/Thai/text.db', 't/text.xml');
ok(!compare('t/text.xml', 't/text_base.xml'), 'sh2xml Thai');
run_perl('scripts/sh2sh', '-s', 't/Thai', 't/Thai/dict.db', 't/dict.xml');
ok(!compare('t/dict.xml', 't/dict_base.xml'), 'sh2sh Thai');

sub run_perl
{
    my ($prog, @args) = @_;
    
#    local(@ARGV) = @args;
    system('perl', $prog, @args);
}

    