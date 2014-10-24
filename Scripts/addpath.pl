use Win32::TieRegistry(Delimiter => '/');
use Getopt::Std;

use bytes;

getopts('r');

$path = join(' ', @ARGV);

unless ($path)
{
    die <<'EOT';
    addpath [-r] path
    
Adds the path to the system path or removes it (-r)

  -r        removes path from system path
EOT
}

my ($regKey) = "HKEY_LOCAL_MACHINE/SYSTEM/CurrentControlSet/Control/Session Manager/Environment//Path";

if (Win32::IsWinNT())
{
    if ($opt_r)
    { removepathnt($path); }
    else
    { addpathnt($path); }
}

sub addpathnt
{
    my ($path) = @_;
    my ($currPath) = $Registry->{$regKey};
    
    if ($currPath !~ m/(^|;)\Q$path\E(;|$)/oi)
    { 
        $currPath .= ";$path";
        $Registry->{$regKey} = $currPath; 
    }
    elsif (!defined $currPath)
    { $Registry->{$regKey} = $path; }
}


sub removepathnt
{
    my ($path) = @_;
    my ($currPath) = $Registry->{$regKey};
    
    if ($currPath =~ s/;\Q$path//oi || $currPath =~ s/\Q$path;//oi)
    { $Registry->{$regKey} = $currPath; }
}
