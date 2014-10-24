#!perl
use SIL::Shoe::Settings;
use SIL::Shoe::Type;
use IO::File;
use Getopt::Std;

getopts('h:l:s:t:');

$VERSION = '0.13';  # MJPH      20-JAN-2004     add support for \(), in symbol fonts via unicode
#$VERSION = '0.12';  # MJPH      13-JAN-2001     remove \\ from source text too.
#$VERSION = '0.11';  #   MJPH    01-JAN-2001     Sort out multi-column block output,
#                                                remove -x, add -t


unless (defined $ARGV[1] && defined $opt_s)
{
    die <<'EOT';
    SHINTR [-h space] [-l space] -s dir [-t type] <infile> <outfile>
Processes an interlinearised database ready for output as RTF.

  -h space      Inter column spacing (in pt) [6]
  -l space      Inter line spacing between blocks (in pt) [8]
  -s dir        Shoebox settings dir
  -t type       Override database type for file
EOT
}

$rtf_mark = "\\_RTF";
$int_mark = "\\_INT";
$hs = 6;
$hs = $opt_h if (defined $opt_h);
$di = 8;
$di = $opt_l if (defined $opt_l);

$settings = SIL::Shoe::Settings->new("$opt_s");
open(INFILE, "<$ARGV[0]") || die "Can't read $ARGV[0]";
open(OUTFILE, ">$ARGV[1]") || die "Can't write $ARGV[1]";
unless ($opt_t)
{
    $line = <INFILE>;
    $line =~ m/^\\_sh\s+(\S+)\s+(\S+)\s+(.*?)\s+$/oi || die "$ARGV[0] is not a Shoebox file";
    print OUTFILE $line;
    $opt_t = $3;
}
$type = $settings->type($opt_t) || die "Can't find .typ file for $opt_t";
$i = 0;
foreach $x (@{$type->{'intprc'}})
{
    foreach $mk ($x->{'mkrFrom'}, $x->{'mkrTo'})
    {
        unless (defined $markers{$mk})
        {
            $markers{$mk} = $i;
            $markers[$i++] = $mk;
        }
    }
    $parent[$markers{$x->{'mkrTo'}}] = $markers{$x->{'mkrFrom'}};
    push(@{$children[$markers{$x->{'mkrFrom'}}]}, $markers{$x->{'mkrTo'}});
}
$lastrow = $i - 1;

while(<INFILE>)
{
    chomp;

    if (m/^\\(\S+)\s/oi)
    {
        $mk = $1;
        $rest = $';
#        print STDERR "$_\n" if (m/^\\ref\s+.*?(\d+)$/o);
#        $temp = $1;
        $ind = $markers{$mk};
        if (defined $ind)
        {
            unless (defined $parent[$ind])
            {
                if ($instack)
                {
                    process_stack($root, \@rows, $lastrow, $contstack);
                    $contstack = 1;
                }
                $root = $ind;
                $instack = 1;
                @rows = ();
                $rows[$ind] = build_pos($rest, $ind);
#                print STDERR "$indnum, $innum\n";
            } else
            {
                $rows[$ind] = build_pos($rest, $ind);
                $p = $parent[$ind];
                make_tree($rows[$ind], $rows[$p], $ind, $p) if (defined $p);
            }
        } elsif ($instack)
        {
            process_stack($root, \@rows, $lastrow, $contstack);
            $contstack = 0;
            $instack = 0;
            print OUTFILE "\\$mk $rest\n";
        } else
        { print OUTFILE "\\$mk $rest\n"; }
    } elsif (m/^\s*$/oi)
    { print OUTFILE "\n"; }
    else
    {
        if ($instack)
        {
            process_stack($root, \@rows, $lastrow, $contstack);
            $contstack = 0;
            $instack = 0;
        }
        print OUTFILE "$_\n";
    }
}


sub build_pos
{
    my ($str, $ind) = @_;
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
            line => $ind,
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


sub process_stack
{
    my ($ind, $rows, $lastrow, $contstack) = @_;
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

    print OUTFILE "$int_mark\n" unless ($contstack);
    for ($p = $rows->[$ind]; defined $p; $p = $p->{'next'})
    { stack_rtf($p, $p, $ind, $lastrow); }
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


sub stack_rtf
{
    my ($first, $last, $ind, $lastrow) = @_;
    my ($c, @strs, @lists, $i, $final, $j);

    unless (defined $parent[$ind])
    {
        print OUTFILE "$rtf_mark {\\field\\flddirty{\\*\\fldinst EQ \\\\s\\\\di$di(\\\\a\\\\al\\\\hs$hs(\n"; #
        $final = "))}{\\fldrslt }}";
    }

    for ($c = $first; defined $c && $c ne $last->{'next'}; $c = $c->{'next'})
    {
        if ($c eq $first || $c->{'children'})
        {
            push (@strs, '');
            push (@lists, $c);
        }
        $strs[-1] .= "$c->{'text'} ";
    }

    foreach (@strs) { s/\s$//o; }     # */ }

    if ($#strs > 0)
    {
        print OUTFILE "$rtf_mark \\\\a\\\\al\\\\hs$hs\\\\co" . ($#strs + 1) . "(\n";
        $final = ")$final";
    }
    
    for ($i = 0; $i <= $#strs; $i++)
    {
#        $strs[$i] =~ s/([\\,()])//og;     # buggy Word, should insert \\$1
        print OUTFILE "\\$markers[$ind] " . process_intstr($strs[$i], $markers[$ind]) . "\n";
        print OUTFILE "$rtf_mark ,\n" if ($i < $#strs);
    }

    for ($i = $ind + 1; $i <= $lastrow; $i++)
    {
        unless ($parent[$i] == $ind)
        {
            print OUTFILE "$rtf_mark $final\n" if ($final);
            return $i;
        }

        foreach $j (@lists)
        {
            print OUTFILE "$rtf_mark ,\n";
            if ($#{$j->{'children'}[$i]} >= 0)
            { stack_rtf($j->{'children'}[$i][0], $j->{'children'}[$i][-1], $i, $lastrow); }
            else
            { print OUTFILE "\\$markers[$i] \\~\n"; }
        }
    }
        
    print OUTFILE "$rtf_mark $final\n" if ($final);
    return $i;
}


sub process_intstr
{
    my ($str, $mkr) = @_;
    my ($lang);
    my (%symmap) = (
        '\\' => -4004,
        ',' => -4052,
        '(' => -4056,
        ')' => -4055);
    
    if ($str =~ m/[\\,()]/o)
    {
        my ($mk) = $type->{'mkr'}{$mkr};
        if ($mk and $lang = $settings->lang($mk->{'lng'}) and $lang->{'charset'} == 2)        # symbol font hack we can do
        { $str =~ s/([\\,()])/"\020\\u$symmap{$1} "/oge; }
        else
        { $str =~ s/[\\,()]//og; }
    }

    return $str;
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
