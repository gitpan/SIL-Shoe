# sh2xml_l.pl
# This is about as good as I can do without any more information. Any suggestions
# for where to go from here. Someone could take the output from this automated
# solution and use XSLT to re-organise according to a different DTD.

$VERSION = '1.0.2'; #   MJPH     8-JUN-2004     Add charset support
# $VERSION = '1.0.1'; #   MJPH     5-MAR-2003     Add system codepage support
# $VERSION = '1.0';   #   MJPH     9-MAY-2003     Add Unicode support for Toolbox

use SIL::Shoe::Settings;
use SIL::Shoe::Data;
use Encode::Registry;
use Getopt::Std;

getopts("c:e:s:");

%charsets = (
    0 => 1252,      # ansi - Western European
    1 => 0,         # default
    2 => 0,         # symbol
    3 => 0,         # invalid
    77 => 10000,    # mac
    128 => 932,     # Shift JIS
    129 => 949,     # Hangul
    130 => 1361,    # Johab
    134 => 936,     # GB2312 Simplified Chinese
    136 => 950,     # Big5 Traditional Chinese
    161 => 1253,    # Greek
    162 => 1254,    # Turkish
    163 => 1258,    # Vietnamese
    177 => 1255,    # Hebrew
    178 => 1256,    # Arabic
    179 => 'arabictrad',
    180 => 'arabicuser',
    181 => 'hebrewuser',
    186 => 1257,    # Baltic
    204 => 1251,    # Russian (Cyrillic)
    222 => 874,     # Thai
    238 => 1250,    # Eastern European
    254 => 437,     # PC 437
    255 => 'oem'
    );

unless (defined $ARGV[0])
{
    die <<'EOT';
    sh2sh -s settings_dir [-c codepage] [-e encs] infile [outfile]

Converts Shoebox data to Shoebox converting to Unicode as it goes.

    -c codepage     Set system codepage for this process
    -e enc,enc      Add Encoding:: subsets in Perl 5.8.1
    -s dir          Directory to find .typ files in [.]
    
If outfile is missing, it is created as the input file with extension replaced
by .db1. This allows a user to drop a data file on a shortcut.
EOT
}

unless (defined $ARGV[1])
{
    $ARGV[1] = $ARGV[0];
    $ARGV[1] =~ s/(\.[^.]*)?$/.db1/o;
}

if ($] > 5.007 && $opt_e)
{
    foreach (split(/\s*[,;]\s*/, $opt_e))
    {
        require "Encode/$opt_e.pm";
        &{"Encode::$opt_e::import"};
    }
}

$opt_s = "." unless defined $opt_s;
$settings = SIL::Shoe::Settings->new($opt_s) || die "Unable to read settings directory at $opt_s";

$s = SIL::Shoe::Data->new($ARGV[0], undef, nostripnl => 1)
        || die "Can't open $ARGV[0]";
open(OUTFILE, ">$ARGV[1]") || die "Can't create $ARGV[1]";
binmode(OUTFILE, ":utf8");
select OUTFILE;

$typef = $settings->type($s->{' Type'}) || die "Can't find .typ file for type: $s->{' Type'}";
$typef->read;
$s->{' key'} = $typef->{'mkrRecord'}[0] || $typef->{'mkrRecord'};        # bug in .typ file results in mkrRecord going in twice
$lngdef = $settings->lang($typef->{'lngDefault'});
$lngdef->add_specials if ($lngdef);
if ($opt_c)
{ $deflng = $opt_c; }
elsif ($lngdef->{'codepage'})
{ $deflng = $lngdef->{'codepage'}; }
elsif ($^O eq 'MSWin32')
{
    require Win32::TieRegistry;
    Win32::TieRegistry->import(Delimiter => '/');

    $deflng = $Registry->{"LMachine/SYSTEM/ControlSet/CurrentControlSet/Control/Nls/CodePage//ACP"};
}

unless ($deflang)
{ $deflang = cp1252; }

$defenc = Encode::Registry::find_encoding($deflang) || Encode::Registry::find_encoding('iso-8859-1')
    || die "Can't make an encoding converter for $deflang";


while ($s->readrecord(\@fields))
{
    $indent = 0;
    @stack = ('shoebox');
    for ($i = 0; $i <= $#fields; $i++)
    {
        $f = $fields[$i];
        $marker = $f;
        next if ($s->{$marker} eq "");
        $marker =~ s/\s+.*$//oi;    # strip to the name back to its sfm

        unless ($lang = $settings->lang($typef->{'mkr'}{$marker}{'lng'}))
        { $enc = $defenc; }
        elsif (defined $lang->{'encoding'})
        { $enc = $lang->{'encoding'}; }
        elsif (defined $lang->{'UnicodeLang'})
        { undef $enc; }
        else
        {
            my ($cp);
            $lang->add_specials;
            $cp = $lang->{'codepage'} || $charsets{hex($lang->{'charset'})};
            $enc = Encode::Registry::find_encoding($cp);
            if (!$enc && $cp)
            {
                print STDERR "Unable to find encoding $cp, using default\n";
                $enc = $defenc;
            }
            $lang->{'encoding'} = $enc;
        }
        $s->{$f} = $enc->decode($s->{$f}) if ($enc);
        print "\\$marker $s->{$f}\n";
    }
    print "\n";
}
