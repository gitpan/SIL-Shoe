@rem = '--*-Perl-*--
@echo off
if "%OS%" == "Windows_NT" goto WinNT
perl -x -S "%0" %1 %2 %3 %4 %5 %6 %7 %8 %9
goto endofperl
:WinNT
perl -x -S %0 %*
if NOT "%COMSPEC%" == "%SystemRoot%\system32\cmd.exe" goto endofperl
if %errorlevel% == 9009 echo You do not have Perl in your PATH.
if errorlevel 1 goto script_failed_so_exit_with_non_zero_val 2>nul
goto endofperl
@rem ';
#!perl

use SIL::Shoe::Diffn;
use Getopt::Long;

%opts = ();

@options = ('command|c=s', 'ed|e', 'show-overlap|E', 'show-all|A', 'overlap-only|x', 'X', 
    'easy-only|3', 'merge|m', 'label|L=s@', 'i', 'text|a', 'initial-tab|T',
    'diff-program=s', 'version|v', 'help');

GetOptions(\%opts, @options);

unless (@ARGV)
{
    die <<'EOT';
    shdiff3 [-c diff3_cmd] [diff3 options] file1 base file2
Tests to see whether the files are shoebox files, if so, does a 3-way merge of
them, otherwise passes control to diff3.
EOT
}

$first = shift;
$base = shift;
$count = 0;

open (IN, "< $base") || die "Can't open $base";
$fline = <IN>;
close(IN);

if ($fline =~ m/^\\_sh\s+(\S+)\s+(\S+)\s+(.*?)\s*$/oi)
{
    $fh = \*STDOUT;
    bless $fh, 'IO::File';

    SIL::Shoe::Diffn::shmerge({'-outfh' => $fh, '-ccountref' => \$count}, $base, $first, @ARGV);
    # print SIL::Shoe::Diffn::shmerge({'-debug' => $opt_d}, $base, $first, @ARGV);
    exit ($count != 0);
}
else
{
    foreach $o (@options)
    {
        $o =~ s/\|.*$//o;
        next if ($o eq 'command');
        $cmd .= " --$o $opts{$o}" if (defined $opts{$o});
    }
    $res = system(join(' ',quotemeta($opts{'command'}), $cmd, map {quotemeta($_)} ($first, $base, shift)));
    exit($res >> 8);
}

__END__
:endofperl
