use SIL::Shoe::Diffn;
use Getopt::Std;

getopts('d');

unless (@ARGV)
{
    die <<'EOT';
    shdiffn [-d] base file1 file2 ...
Does an n-way merge of shoebox files with optional debug information
EOT
}

$fh = \*STDOUT;
bless $fh, 'IO::File';

# SIL::Shoe::Diffn::shmerge({'-outfh' => $fh}, @ARGV);
print SIL::Shoe::Diffn::shmerge({'-debug' => $opt_d}, @ARGV);
