# sh2xml_l.pl
# This is about as good as I can do without any more information. Any suggestions
# for where to go from here. Someone could take the output from this automated
# solution and use XSLT to re-organise according to a different DTD.

$VERSION = '1.0.3'; #   MJPH     8-JUN-2004     Add charset support
# $VERSION = '1.0.2'; #   MJPH    15-MAR-2003     Convert font names via system codepage
# $VERSION = '1.0.1'; #   MJPH     5-MAR-2003     Add system codepage support
# $VERSION = '1.0';   #   MJPH     9-MAY-2003     Add Unicode support for Toolbox

use SIL::Shoe::Settings;
use SIL::Shoe::Data;
use Encode::Registry;
use Getopt::Std;

getopts("a:c:d:e:fis:x:");

unless (defined $ARGV[0])
{
    die <<'EOT';
    sh2xml [-s settings_dir] [-a attrib] [-c codepage] [-d file]
            [-x stylesheet] [-e encs] infile [outfile]

Converts Shoebox data to XML based on marker hierarchy and interlinear text.

    -a attrib       Default attribute name [value]
    -c codepage     Set system codepage for this process
    -d file         output file for DTD
    -e enc,enc      Add Encoding:: subsets in Perl 5.8.1
    -f              Add formatting information <shoebox-format>
    -i              Include DTD in data file (overriden by -d)
    -s dir          Directory to find .typ files in [.]
    -x stylesheet   XSL stylesheet filename to reference in the XML file
    
If outfile is missing, it is created as the input file with extension replaced
by .xml. This allows a user to drop a data file on a shortcut.
EOT
}

%esc = (                    # as per XML spec.
    '<' => '&lt;',
    '>' => '&gt;',
    '&' => '&amp;',
    "'" => '&apos;',
    '"' => '&quot;'
    );
    
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

unless (defined $ARGV[1])
{
    $ARGV[1] = $ARGV[0];
    $ARGV[1] =~ s/(\.[^.]*)?$/.xml/o;
}

if ($] > 5.007 && $opt_e)
{
    foreach (split(/\s*[,;]\s*/, $opt_e))
    {
        require "Encode/$opt_e.pm";
        &{"Encode::$opt_e::import"};
    }
}

$opt_a = "value" unless defined $opt_a;
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

print '<?xml version="1.0" encoding="UTF-8"' . ($opt_i ? ' standalone="yes"' : '') . ' ?>' . "\n";
print '<?xml-stylesheet type="text/xsl" href="' . $opt_x . "\"?>\n" if ($opt_x);

$typen = $s->{' Type'};
$typen =~ s/\s+/_/oig;
if ($opt_d)
{ print "<!DOCTYPE $typen SYSTEM \"$opt_d\">\n"; }

$dtd = make_dtd($typef, $typen);

print "<shoebox type=\"$s->{' Type'}\">\n\n";

if ($opt_f)
{
    print "<shoebox-format>\n";
    foreach $m (sort keys %{$typef->{'mkr'}})
    {
        my ($fntmkr, $italic, $bold, $color);
        $mkr = $typef->{'mkr'}{$m};
        print "  <marker name=\"$dtd->{$m}{'element'}\"";
        print " style=\"" . (defined $mkr->{'CharStyle'} ? 'char' : 'par') . "\"";
        print ">\n";
        print "    <language>$mkr->{'lng'}</language>\n";
        if (defined $mkr->{'fnt'})
        { $fntmkr = $mkr->{'fnt'}; }
        else
        { $fntmkr = $settings->lang($mkr->{'lng'}); }
        
        $italic = defined $fntmkr->{'Italic'} ? 'italic' : undef;
        $bold = defined $fntmkr->{'Bold'} ? 'bold' : undef;
        $color = $fntmkr->{'rgbColor'} eq '0,0,0' ? undef : $fntmkr->{'rgbColor'};
        $bold .= ' ' if ($bold && $italic);
        
        print "    <font size=\"$fntmkr->{'Size'}\"";
        print " style=\"$bold$italic\"" if ($bold || $italic);
        print " color=\"$color\"" if ($color);
        print ">" . protect($defenc->decode($fntmkr->{'Name'})) . "</font>\n";

        if (defined $dtd->{$m}{'interlinid'})
        { print "    <interlinear level=\"" . ($dtd->{$m}{'interlinid'} + 1) . "\"/>\n"; }
        if ($dtd->{$m}{'element'} ne $m)
        { print "    <original-marker>" . protect($m) . "</original-marker>\n"; }
        print "  </marker>\n";
    }
    print "</shoebox-format>\n\n";
}

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

        if (defined $dtd->{$marker}{'interlinid'})
        {
            if (!defined $interlin_level)
            {
                print " " x $indent;
                print "<interlinear-block>\n";
                $indent += 2;
            }
            elsif ($dtd->{$marker}{'interlinid'} == 0)
            { 
                output_block($indent, $rows, $dtd);
                $rows = [];
            }
            $interlin_level = $dtd->{$marker}{'interlinid'};
            $rows->[$interlin_level] = build_pos($s->{$f});
            next;
        }
        elsif (defined $interlin_level)
        {
            output_block($indent, $rows, $dtd);
            $rows = [];
            $indent -= 2;
            print " " x $indent;
            print "</interlinear-block>\n";
            undef $interlin_level;
        }
                
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
        $s->{$f} =~ s/([<>&'"])/$esc{$1}/og;    # tidy up data]

        if (defined $dtd->{$marker}{'parent'})
        {
        outdent:
            while ($h = shift (@stack))
            {
                $p = $dtd->{$marker}{'parent'};
                if ($h eq $p)
                {
                    unshift (@stack, $h);
                    last;
                } else
                {
                    @temp = ($p);
                    while (defined $dtd->{$p}{'parent'})
                    {
                        $p = $dtd->{$p}{'parent'};
                        if ($h eq $p)
                        {
                            unshift (@stack, $h);
                            foreach $t (@temp)
                            {
                                print " " x $indent;
                                print "<$dtd->{$t}{'element'}>\n";
                                $indent += 2;
                                unshift (@stack, $t);
                            }
                            last outdent;
                        }
                        else
                        { unshift (@temp, $p); }
                    }
                }
                $indent -= 2;
                print " " x $indent;
                print "</$dtd->{$h}{'element'}>\n";
            }
            if ($#stack < 0)
            { die "Incorrect SF hierarchy at sfm $f in record $s->{$s->{' key'}}"; }
        }

        if (defined $dtd->{$marker}{'child'})
        {
            unshift (@stack, $dtd->{$marker}{'element'});
            print " " x $indent;
            print "<$dtd->{$marker}{'element'} $opt_a=\"$s->{$f}\">\n";
            $indent += 2;
        } else
        {
            print " " x $indent;
            print "<$dtd->{$marker}{'element'}>$s->{$f}</$dtd->{$marker}{'element'}>\n";
        }
    }
    if (defined $interlin_level)
    {
        output_block($indent, $rows, $dtd);
        $rows = [];
        $indent -= 2;
        print " " x $indent;
        print "</interlinear-block>\n";
        undef $interlin_level;
    }
    
    while ($#stack >= 1)
    {
        my ($h) = shift(@stack);
        $indent -= 2;
        print " " x $indent;
        print "</$dtd->{$h}{'element'}>\n";
    }
    print "\n";
}

print OUTFILE "</shoebox>\n";
close OUTFILE;

sub make_dtd
{
    my ($tf, $typen) = @_;
    my ($k, $tree, $mk, $lcount, $nk);

    $tree = {};
    $lcount = 0;
    foreach $k (@{$tf->{'intprc'}})
    {
        foreach $mk ($k->{'mkrFrom'}, $k->{'mkrTo'})
        {
            unless (defined $tree->{$mk}{'interlinid'})
            {
                $tree->{$mk}{'interlinid'} = $lcount;
                $tree->{'interlinear block'}{'markers'}[$lcount++] = $mk;
            }
        }
#        $tree->{$k->{'mkrTo'}}{'interlin_parent'} = $tree->{$k->{'mkrFrom'}}{'interlinid'};
        $tree->{$k->{'mkrTo'}}{'parent'} = $k->{'mkrFrom'};
        push(@{$tree->{$k->{'mkrFrom'}}{'interlin_child'}}, $tree->{$k->{'mkrTo'}}{'interlinid'});
    }
    
    foreach $k (keys %{$tf->{'mkr'}})
    {
        $nk = transform($k);
        $tree->{$k}{'element'} = $nk;
        $parent = $tf->{'mkr'}{$k}{'mkrOverThis'};
        if (defined $tree->{$k}{'interlinid'})
        {
            if (defined $tree->{$k}{'parent'})
            { $parent = $tree->{$k}{'parent'}; }
            else
            { 
                push (@{$tree->{'interlinear block'}{'child'}}, $nk);
                $nk = 'interlinear block';
                $tree->{$nk}{'element'} = 'interlinear-block';
                $tree->{$k}{'parent'} = $nk;
                $k = 'interlinear block';
            }
        }
        $parent ||= 'shoebox';
        $tree->{$k}{'parent'} = $parent unless defined $tree->{$k}{'parent'};
        push (@{$tree->{$parent}{'child'}}, $nk);        
    }

    if (defined $opt_d)
    {
        open(DTD, ">$opt_d") || die "Can't create $opt_d";
        select DTD;
        print '<?xml version="1.0" encoding="UTF-8" ?>' . "\n";
    }

    return $tree unless (defined $opt_d || defined $opt_i);

    print "<!DOCTYPE shoebox [\n";
    if ($opt_f)
    {
        print "<!ELEMENT shoebox (shoebox-format, ($tree->{'shoebox'}{'child'}[0])*)>\n";
        print <<'EOT';
<!ELEMENT shoebox-format (marker)*>
<!ELEMENT marker (language, font, interlinear?, original-marker?)>
<!ATTLIST marker 
    name CDATA #REQUIRED
    style (char | par) #REQUIRED>

<!ELEMENT language (#PCDATA)>

<!ELEMENT font (#PCDATA)>
<!ATTLIST font 
        size CDATA #REQUIRED
        style CDATA #IMPLIED
        color CDATA #IMPLIED>
        
<!ELEMENT interlinear EMPTY>
<!ATTLIST interlinear level CDATA #IMPLIED>

<!ELEMENT original-marker (#PCDATA)>

EOT
    }
    else
    { print "<!ELEMENT shoebox ($tree->{'shoebox'}{'child'}[0])*>\n"; }

    print "<!ATTLIST shoebox type CDATA #IMPLIED>\n\n";

    foreach $nk (sort keys %{$tree})
    { 
        next if ($nk eq 'shoebox');
        if (defined $tree->{$nk}{'child'})
        {
            print "<!ELEMENT $tree->{$nk}{'element'} (" . join("|", map {$tree->{$_}{'element'}} sort @{$tree->{$nk}{'child'}}) . ")*>\n";
            print "<!ATTLIST $tree->{$nk}{'element'} $opt_a CDATA #IMPLIED>\n\n";
        }
        else
        { print "<!ELEMENT $tree->{$nk}{'element'} (#PCDATA)>\n"; }
    }

    print "]>\n\n";

    if (defined $opt_d)
    {
        select OUTFILE;
        close(DTD);
    }
    $tree;
}


sub transform
{
    my ($str) = (@_);
    $str =~ s/^(\d)/_.$1/o;
    $str;
}

sub protect
{
    my ($str) = @_;
    
    $str =~  s/([<>&'"])/$esc{$1}/og;    # tidy up data]
    $str;
}

sub build_pos
{
    my ($str) = @_;
    my ($match, $num, $pos, $substr, $first, $new, $last);

    $pos = 0;
    $num = 0;
#    $str =~ s/^\s?//og;
    while ($str =~ m/^(\S+)\s*/oi)
    {
        $substr = $1;
        $match = $&;
        $str = $';
        $new = SIL::Shoe::Interlin::Node->new(
            text => $substr,
            num => $num,
            pos => $pos,
            end => $pos + length($substr));
        if ($last)
        {
            $last->{'next'} = $new;
            $last = $new;
        }
        else
        {
            $first = $new;
            $last = $new;
        }
        $pos += length($match);
        $num++;
    }
    return $first;
}

sub make_tree
{
    my ($row, $prow, $ind, $pind) = @_;
    my ($child, $parent, $oldp, $plast);

    for ($child = $row; defined $child; $child = $child->{'next'})
    {
# find actual parent of this child
        for ($parent = $prow; defined $parent; $parent = $parent->{'next'})
        {
            if ($child->{'pos'} == $parent->{'pos'})
            {
                $plast = $parent;
                last;
            }
            elsif ($child->{'pos'} < $parent->{'pos'})
            { last; }
            $plast = $parent;
        }
        
        $child->{'parent'} = $plast;
        push(@{$plast->{'children'}[$ind]}, $child);

        $oldp = $plast;
        for ($parent = $plast->{'next'}; defined $parent; $parent = $parent->{'next'})
        {
            last unless ($child->{'end'} >= $parent->{'pos'});
            $oldp = $parent;
        }

        mark_links($plast, $oldp, $pind) if ($oldp ne $plast);
    }
}


sub mark_links
{
    my ($first, $last, $ind) = @_;
    my ($pfirst, $plast, $pind);

    $pind = $parent[$ind];
    if (defined $pind)
    {
        $pfirst = $first->{'parent'};
        $plast = $last->{'parent'};
        mark_links($pfirst, $plast, $pind) if ($pfirst ne $plast);
    }

    for ($pfirst = $first; $pfirst ne $last; $pfirst = $pfirst->{'next'})
    { $pfirst->{'linked'} = 1; }
}


sub output_block
{
    my ($indent, $rows, $dtd) = @_;
    my ($i);
    
    for ($i = 0; $i < scalar @{$rows}; $i++)
    {
        $mk = $dtd->{'interlinear block'}{'markers'}[$i];
        if (defined $dtd->{$mk}{'parent'} && defined $dtd->{$dtd->{$mk}{'parent'}}{'interlinid'})
        {
            my ($pid) = $dtd->{$dtd->{$mk}{'parent'}}{'interlinid'};
            make_tree($rows->[$i], $rows->[$pid], $i, $pid);
        }
    }
    process_stack(0, $rows, $indent);
    
}

sub process_stack
{
    my ($ind, $rows, $indent) = @_;
    my ($p, $c, $op);

    for ($p = $rows->[$ind]; defined $p; $p = $p->{'next'})
    {
        $op->{'linked'} = 1 if (defined $op && !$p->{'children'});
        $op = $p;
    }

    for ($c = $rows->[$ind]; defined $c; $c = $c->{'next'})
    {
        for ($p = $c; defined $p && $p->{'linked'}; $p = $p->{'next'})
        { }

        if ($p ne $c)
        {
            $c->{'chained'} = $p;
            mark_children($c, $p, $ind);
            $c = $p;
        }
    }

    for ($c = $rows->[$ind]; defined $c; $c = $c->{'next'})
    {
        next unless ($c->{'chained'});
        remove_links($c, $c->{'chained'}, $ind);
    }

    for ($p = $rows->[$ind]; defined $p; $p = $p->{'next'})
    { stack_xml($p, $ind, $dtd, $indent); }
}


sub mark_children
{
    my ($first, $last, $ind) = @_;
    my ($cind, $cfirst, $clast, $c, $p);

    foreach $cind (@{$children[$ind]})
    {
        $cfirst = $first->{'children'}[$cind][0];
        for ($p = $first; defined $p && $p ne $last->{'next'}; $p = $p->{'next'})
        {
            foreach $c (@{$p->{'children'}[$cind]})
            {
                if ($cfirst->{'pos'} <= $c->{'pos'})
                {
                    $clast = $c;
                }
                else
                {
                    $clast = $cfirst;
                    $cfirst = $c;
                }
            }
        }

        if ($cfirst)
        {
            $clast ||= $cfirst;
            $cfirst->{'chained'} = $clast;
            for ($c = $cfirst; $c ne $clast; $c = $c->{'next'})
            {
                $c->{'linked'} = 1;
            }
            $first->{'fchild'}[$cind] = $cfirst;
            mark_children($cfirst, $clast, $cind);
        }
    }
}


sub remove_links
{
    my ($first, $last, $ind) = @_;
    my ($cind, $c);

    foreach $cind (@{$children[$ind]})
    {
        $c = $first->{'fchild'}[$cind];
        next unless $c;
        remove_links($c, $c->{'chained'}, $cind);
        $first->{'children'}[$cind] = [$c];
        $c->{'parent'} = $first;
    }

    for ($c = $first->{'next'}; defined $c && $c ne $last->{'next'}; $c = $c->{'next'})
    {
        $first->{'text'} .= " $c->{'text'}";
    }
    $first->{'next'} = $c;
    $first->{'linked'} = 0;
}


sub stack_xml
{
    my ($first, $ind, $dtd, $indent) = @_;
    my ($mk, $enc, $str, $lang, $c, $child);
    
    $mk = $dtd->{'interlinear block'}{'markers'}[$ind];
    
    unless ($lang = $settings->lang($typef->{'mkr'}{$mk}{'lng'}))
    { $enc = $defenc; }
    elsif (defined $lang->{'encoding'})
    { $enc = $lang->{'encoding'}; }
    else
    {
        $lang->add_specials;
        $enc = Encode::Registry::find_encoding($lang->{'codepage'}) || $defenc;
        $lang->{'encoding'} = $enc;
    }

    if ($first)
    {
        $str = $enc->decode($first->{'text'});
        $str =~ s/([<>&'"])/$esc{$1}/og;    # tidy up data]
    }
    else
    { $str = ''; }

    print " " x $indent;
    if (defined $dtd->{$mk}{'interlin_child'})
    {
        if ($first)
        { print "<$dtd->{$mk}{'element'} value=\"$str\">\n"; }
        else
        { print "<$dtd->{$mk}{'element'}>\n"; }
        
        foreach $c (@{$dtd->{$mk}{'interlin_child'}})
        {
            if ($first && @{$first->{'children'}[$c]})
            {
                foreach $child (@{$first->{'children'}[$c]})
                { stack_xml($child, $c, $dtd, $indent + 2); }
            }
            else
            { stack_xml(undef, $c, $dtd, $indent + 2); }
        }
        print " " x $indent;
        print "</$dtd->{$mk}{'element'}>\n";
    }
    elsif ($first)
    { print "<$dtd->{$mk}{'element'}>$str</$dtd->{$mk}{'element'}>\n"; }
    else
    { print "<$dtd->{$mk}{'element'}/>\n"; }
}


package SIL::Shoe::Interlin::Node;

sub new
{
    my ($class, %attrs) = @_;
    my ($self) = {%attrs};

    bless $self, ref $class || $class;
}

sub le
{
    my ($test, $against) = @_;
    my ($p);

    for ($p = $test; defined $p; $p = $p->{'next'})
    {
        return 1 if ($p eq $against);
    }
    return 0;
}
