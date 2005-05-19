package SIL::Shoe::Lang;

=head1 NAME

SIL::Shoe::Lang - Shoebox language file interface

=head1 SYNOPSIS

  $s = SIL::Shoe::Lang->new("filename.lng");
  $s->read;
  $s->{'srt'}{"order"}{'primary'};

=head1 DESCRIPTION

This class provides an interface to the Shoebox language file. It restructures
the file for easier access and provides various support functions for sorting,
etc.

In addition to those in SIL::Shoe::Control, the following methods are
available:

=cut

use SIL::Shoe::Control;

@ISA = qw(SIL::Shoe::Control);

use strict;

my (%groups) = (
            "LanguageEncoding"  => ["0", ""],
            "srtset"            => ["0", ""],
            "srt"               => ["h", "srt"],
            "varset"            => ["0", ""],
            "var"               => ["h", "var"],
            "fnt"               => ["0", ""],
               );

sub group
{
    my ($self, $name) = @_;
    return $groups{$name};
}

sub multiline
{
    my ($self, $name, $ingroup) = @_;
    return 0 if ($name eq "desc");
    return 1;
}

sub make_srt_order
{
    my ($self, $ref) = @_;
    my (@res, %multi);
    my ($i, $sec, $base_sec, $max_sec, $c, $l, $co, $temp);

    $i = 1;
    foreach $c (split(' ', $ref->{'SecPreceding'}))
    {
        if (length($c) > 1)
        {
            $res[ord(substr($c, 0, 1))] = "\xff\xff";
            $multi{$c} = pack("cc", 0, $i++);
        } else
        { $res[ord($c)] = pack("cc", 0, $i++); }
    }
    $base_sec = $i + 1;
    $max_sec = $base_sec;
    $i = 0;
    foreach $l (split('\n', $ref->{'primary'}))
    {
        $sec = $base_sec;
        $i++;
        foreach $c (split(' ', $l))
        {
            if (length($c) > 1)
            {
                $co = ord(substr($c, 0, 1));
                if ($res[$co] ne "" && $res[$co] ne "\xff\xff")
                { $temp = $res[$co]; $res[$co] = "\xff\xff"; $multi{chr($co)} = $temp; }
                elsif ($res[$co] eq "")
                { $res[$co] = "\xff\xff"; }
                $multi{$c} = pack("cc", $i, $sec++);
            } else
            { $res[ord($c)] = pack("cc", $i, $sec++); }
        }
        $max_sec = $sec if $sec > $max_sec;
    }
    
    $i = $max_sec + 1;
    foreach $c (split(' ', $ref->{'SecFollowing'}))
    {
        if (length($c) > 1)
        {
            $co = ord(substr($c, 0, 1));
            if ($res[$co] ne "" && $res[$co] ne "\xff\xff")
            { $temp = $res[$co]; $res[$co] = "\xff\xff"; $multi{chr($co)} = $temp; }
            elsif ($res[$co] eq "")
            { $res[$co] = "\xff\xff"; }
            $multi{$c} = pack("cc", 0, $i++);
        } else
        { $res[ord($c)] = pack("cc", 0, $i++); }
    }
    (\@res, \%multi);
}

=head2 $s->build_sorts

Builds tables to help with sort ordering, for each sort order in the language file.

=cut

sub build_sorts
{
    my ($self) = @_;
    my ($k, $ref);

    foreach $k (keys %{$self->{'srt'}})
    {
        $ref = $self->{'srt'}{$k};
        ($ref->{' single'}, $ref->{' multi'}) = $self->make_srt_order($ref);
    }
    $self;
}


=head2 $s->sort_key($name, $str)

Calculates a sort key which can be string compared for a given string and sort
order name

=cut

sub sort_key
{
    my ($self, $name, $str) = @_;
    my ($resp, $ress, $i, $j, $c, $prim, $sec, $single, $multi, $val);

    $single = $self->{'srt'}{$name}{' single'};
    if (!defined $single)
    {
        $self->build_sorts;
        $single = $self->{'srt'}{$name}{' single'};
    }
    $multi = $self->{'srt'}{$name}{' multi'};
    for ($i = 0; $i < length($str); $i++)
    {
        $c = ord(substr($str, $i, 1));
        if ($single->[$c] eq "\xff\xff")
        {
            undef $val;
            for ($j = 1; $j < length($str) - $i; $j++)
            {
                last unless defined $multi->{substr($str, $i, $j)};
                $val = $multi->{substr($str, $i, $j)};
            }
            $i += ($j == 1) ? 0 : $j - 2;
        } else
        { $val = $single->[$c]; }
        ($prim, $sec) = unpack("cc", $val);
        $resp .= chr($prim) if ($prim != 0);
        $ress .= chr($sec) if ($sec != 0);
    }
    return $resp . "\000" . $ress;
}

sub add_specials
{
    my ($self) = @_;
    
    
    while ($self->{'desc'} =~ m/\\(\S+)\s*=\s*
        (?:\"((?:\\.|[^"])*)\"
            |
           \'((?:\\.|[^'])*)\'
            |
           (\S+))/ogx)
        {
            $self->{$1} = $2 || $3 || $4;
        }
    $self;
}

1;

