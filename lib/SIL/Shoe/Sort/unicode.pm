package SIL::Shoe::Sort::unicode;

use Unicode::Collate;
use base 'SIL::Shoe::Sort::default';

sub new
{
    my ($class, $name) = @_;
    my ($self);
    my ($dump, $level) = split(/\|/, $name);
    my ($srt) = Unicode::Collate->new(
        'level' => $level || 4
    ) || die "Can't create Unicode collator";

    $self = {
        'coll' => $srt,
        'level' => $level || 4,       # default
    };

    return bless $self, $class;
}

sub cmp
{
    my ($self, $a, $b, $level) = @_;

    return 1 unless $b;
    return -1 unless $a;
    if (defined $level && $level != $self->{'level'})
    {
        $self->{'coll'}->change(level => $level);
        $self->{'level'} = $level;
    }
    return $self->{'coll'}->cmp($a, $b);
}

sub firstchar
{
    my ($self, $str, $level, $ignore) = @_;

    return undef unless ($str);
    return ($self->{'coll'}->tokenize($str, $level, $ignore))[0];
}

package Unicode::Collate;

sub tokenize
{
    my ($self, $str, $level, $ignore) = @_;
    my ($r, @res);
    my ($rEnt) = $self->splitEnt($str);
    $level ||= $self->{'level'};        # pick up default if not specified

    foreach $r (@{$rEnt})
    {
        my ($var, @wt) = (unpack('cn4', ($self->getWt($r))[0]));   # only interested in first key since primary one
        my ($test, $i);
        my ($s) = pack('U*', split(/;/, $r));

        for ($i = 0; $i < $level - 1; $i++)
        { $test |= ($wt[$i] == 0); }

        next if ($ignore && $test && !$wt[$level-1]);
        if ($test)
        { $res[-1] .= $s; }
        else
        { push (@res, $s); }
    }
    @res;
}



1;
        
