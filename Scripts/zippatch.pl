use SIL::FS;
use Getopt::Std;
use IO::File;
use File::Spec;

getopts('m:o:r');

unless (defined $ARGV[1])
{
    die <<'EOT';
zippatch [-m manifest] [-o outroot] [-r] original patch

Patches an original directory tree or .zip file as directory with
the normal difference patch file. Either patches in place or to outroot
which may be a directory or .zip file representing a directory.

 -m manifest    Manifest file to use for file names and types
 -o outroot     directory/.zip to create output files in.
 -r             reverse patch (tries to auto-sense this).
EOT
}

if ($ARGV[0] =~ m/\.zip$/oi)
{ $infs = SIL::FS::Zip->new($ARGV[0], -manifest => $opt_m ? $fs2->{'manifest'} : undef); }
else
{ 
    $infs = SIL::FS::File->new($ARGV[0], -manifest => $opt_m ? $fs2->{'manifest'} : undef); 
    $infs->remove_list(File::Spec->rel2abs($ARGV[0])) if ($ARGV[0] =~ m/\.zip$/oi);
}

if ($opt_o =~ m/\.zip$/oi)
{ 
    if ($opt_o eq $ARGV[0])
    { $outfs = $infs; }
    else
    { $outfs = SIL::FS::Zip->new(); }
}
elsif ($opt_o)
{ $outfs = SIL::FS::File->new($opt_o); }
else
{ $outfs = $infs; }

%files = map {$_ => 1} @{$infs->{'filelist'}};

$pfs = IO::File->new("< $ARGV[1]") || die "Can't open patch file $ARGV[1]";

$hunk = 0;
$swapped = 0;
while (<$pfs>)
{
    chomp;
    if (m/^DELETE\-\-\-: (.*?)\s*$/o)
    {
        $deleted{$1}++;
        delete $files{$1};
    }
    elsif (m/^\-\-\- (.+?)\s*$/o)
    {
        $oldfile = $currfile;
        $currfile = $1;
        if ($oldfile && !$deleted{$oldfile})
        {
            end_patch();
            $outfs->put_lines($oldfile, @outlines);
            $files{$oldfile} = 2;
            @outlines = ();
        }
        unless ($deleted{$currfile})
        { 
            @inlines = $infs->get_lines($currfile);
            $ipos = 1;
        }
    }
    elsif (m/^(\s*)((\d+)(?:,(\d+))?([acd])(\d+)(?:,(\d+))?)\s*$/o)
    {
        ($space, $range, $i_start, $i_end, $cmd, $o_start, $o_end) =
        ($1,     $2,     $3,     $4 || $3, $5,   $6,       $7 || $6);
        if ($cmd eq 'a' || $cmd eq 'c')
        { $a_len = ($o_end - $o_start + 1); }
        else
        { undef $a_len; }
        if ($cmd eq 'd' || $cmd eq 'c')
        { $d_len = ($i_end - $i_start + 1); }
        else
        { undef $d_len; }
    }
    elsif ($_ eq "---")
    {
        if ($cmd eq 'c' && $d_len != 0)
        {
            print STDERR 'Short hunk ignored.';
            $cmd = '';
        }
    }
    elsif (s/^$space< // && $cmd =~ m/[cd]/o)
    {
        push (@d_lines, $_);
        if ($d_len-- <= 0)
        { 
            print STDERR 'Short hunk ignored.';
            $cmd = '';
        }
        if ($cmd eq 'd' && $d_len == 0)
        { 
            do_patch($i_start, $i_end, $cmd, $o_start, $o_end) unless ($deleted{$currfile});
            $cmd = '';
        }
    }
    elsif (s/^$space> // && $cmd =~ m/[ac]/o)
    {
        push (@a_lines, $_);
        if ($a_len-- <= 0)
        {
            print STDERR 'Short hunk ignored.';
            $cmd = '';
        }
        elsif ($a_len == 0)
        { 
            do_patch($i_start, $i_end, $cmd, $o_start, $o_end) unless ($deleted{$currfile}); 
            $cmd = '';
        }
    }
}

if ($currfile && !$deleted{$currfile})
{
    end_patch();
    $outfs->put_lines($currfile, @outlines);
    $files{$currfile} = 2;
}

if ($outfs ne $infs)
{
    foreach $f (grep {$files{$_} == 1} sort keys %files)
    { $outfs->put_lines($f, $infs->get_lines($f)); }
}

if ($opt_o =~ m/\.zip$/oi)
{ $outfs->writeTo($opt_o); }

sub do_patch
{
    my ($i_start, $i_end, $cmd, $o_start, $o_end) = @_;
    
    if ($swapped)
    { 
        ($i_start, $i_end, $o_start, $o_end) = ($o_start, $o_end, $i_start, $i_end);
        @temp = @d_lines;
        @d_lines = @a_lines;
        @a_lines = @temp;
        if ($cmd eq 'd')
        { $cmd eq 'a'; }
        elsif ($cmd eq 'a')
        { $cmd eq 'd'; }
    }
    $pos = find_context($i_start, $ipos, @d_lines);
    if ($pos < 0 && $hunk == 0)
    {
        $pos = find_context($o_start, $ipos, @a_lines);
        if ($pos >= 0)
        { 
            $swapped = !$swapped;
            do_patch(@_);
        }
    }
    if ($pos < 0)
    {
        print STDERR "Can't find context to apply hunk";
    }
    else
    {
        if ($pos > $ipos)
        { push (@outlines, @inlines[$ipos-1 .. $pos-2]); }
        if (@d_lines)
        { $ipos = $pos + @d_lines; }
        else
        {
            push (@outlines, @inlines[$pos - 1]) if ($pos > 0);
            $ipos = $pos + 1;
        }
        push (@outlines, @a_lines);
    }
    $hunk++ if ($cmd =~ m/[cd]/o);
    @d_lines = ();
    @a_lines = ();
}

sub find_context
{
    my ($start, $currpos, @lines) = @_;
    my ($i, $l, $found, $offset);
    my ($res) = $start;
    
    return $res unless @lines;
    
    for ( ; $res <= @inlines; $res += $offset)
    {
        $found = -1;
        for ($i = 0; $i < @lines; $i++)
        {
            if ($inlines[$res + $i - 1] ne $lines[$i])
            { 
                $found = $i;
                last;
            }
        }
        return ($res) if ($found == -1);
        
        for ($i = $found; $i < @lines; $i++)
        {
            if ($inlines[$res - 1] eq $lines[$i])
            { last; }
        }
        if ($offset == 0 && $res - $i >= $currpos)
        { $offset = -$i; }
        else
        { $offset = $i; }
    }
    return -1;
}

sub end_patch
{
    push (@outlines, @inlines[$ipos .. scalar @inlines - 1]);
}
