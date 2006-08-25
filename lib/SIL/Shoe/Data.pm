package SIL::Shoe::Data;

=head1 NAME

SIL::Shoe::Data - Class for handling Shoebox databases

=head1 SYNOPSIS

 require SIL::Shoe::Data;
 $s = SIL::Shoe::Data->new("infile.db", $key);
 $s->index;
 $s->findrecord("Mine");
 $s->readrecord(\@fieldkeys);
 $s->{'newfield'} = "Hi there mum!";
 push(@fieldkeys, "newfield");
 $s->printrecord(\*FILEHANDLE, @fieldkeys)

=head1 DESCRIPTION

This class provides support for Standard Format databases as generated by
Shoebox. The class supports indexing, incrementing, etc. and as such holds
static information regarding a database.

The following methods are available:

=cut

$VERSION = "1.10";      # MJPH  14-AUG-2006     Add field methods
# $VERSION = "1.09";      # MJPH  30-JUN-2006     Add printheader
# $VERSION = "1.08";      # MJPH  19-MAY-2006     Fix complex indexing for many keys in a record
# $VERSION = "1.07";      # MJPH  21-FEB-2005     Add \_DateStampHasFourDigitYear field (' DateStamp' = 4)
# $VERSION = "1.06";      # MJPH  20-JAN-2005     Fix multiline key fields
# $VERSION = "1.05";      # MJPH  10-JUN-2004     Add md5 and line counts on indexing
# $VERSION = "1.04";      # MJPH   3-APR-2003     Add auto key searching, md5, locational reading
# $VERSION = "1.0003";    # MJPH   9-DEC-1998     Add noblank creation option.
# $VERSION = "1.0000";
# $VERSION = "1.0001";    # MJPH  29-JUN-1998     Debugged nostripnl, added VERSION, map comment
# $VERSION = "1.0002";    # MJPH  28-JUL-1998     Get index and findrecord working

use strict;
use Carp();
use IO::File;
use Digest::MD5;

=head2 SIL::Shoe::Data->new("filename", "key", 'attrname' => 'value', ...)

Creates a new Shoebox object corresponding to the SF database in "filename".
The keyfield marker is given at this point also. If key is blank, then it will
be guessed by looking for the first marker in the file (excluding \_sh).
Extra attributes are also supported including:

=over 4

=item nostripnl

If set, instructs that multi-line fields not be joined into a single line by a
space.

=item nostripws

If set, disables the default stripping of whitespace from the start and end
of a field's data.

=item allfields

Make sure that all fields are output by printrecord, even those not in the
given list.

=item noblank

Indicates that records printed via printrecord should not have a following
blank line.

=item unicode

Assume the file is UTF8 unicode data otherwise process as bytes

=item nointernal

Do not keep track of fields and their positions within the record

=back

=cut

sub new
{
    my $class = shift;
    my $file = shift;
    my $key = shift;
    my ($self, $fh);

    my (%attrs) = @_;
    foreach (keys %attrs) { $self->{" $_"} = $attrs{$_}; }

    if (ref $file)
    { $fh = $file; }
    elsif ($self->{' unicode'})
    { $fh = IO::File->new($file, "<:utf8") || return Carp::croak("Unable to open Shoebox file $file"); }
    else
    { $fh = IO::File->new($file, "<:bytes") || return Carp::croak("Unable to open Shoebox file $file"); }


# notice we can use fields starting with space for internals
# since SF markers can't start with space.

    $self->{' key'} = $key;
    $self->{' INFILE'} = $fh;
    $self->{' thisloc'} = 0;            # where we are following the last ReadRecord
    $self->{' loc'} = 0;                # the location of the last findrecord


    while ($_ = $fh->getline)
    {
        if (m/^\\_sh\s+(\S+)\s+(\S+)\s+(.*?)\s*$/oi)
        {
            $self->{' Version'} = $1;
            $self->{' CSum'} = $2;        # always 400 in SH4  
            $self->{' Type'} = $3;
            last if $key;
        }
        elsif (m/^\\_DateStampHasFourDigitYear/o)
        {
            $self->{' DateStamp'} = 4;
        }
        elsif (m/^\\(\S+)/oi)
        { 
            next if ($1 eq '_sh');
            $self->{' key'} = $1 unless $key;
            last; 
        }
    }
    $fh->seek(0, 0);
    
    bless $self, $class;
}


=head2 $s->index("otherkey")

"otherkey" is optional and allows indexing on a key other than the key field.

Indexes the database according to the key field. Since Shoebox seems happy to
hold its index in memory, so shall we. This index supports multiple records
identically keyed.

The internal structure of the index is a hash of index entries each of which
is an array of locations in the file. Thus:

    $s->{' index'}{$entry}[$num]

returns a C<seek> location into the file. Note also that the index can be kept
and saved and a new index created as needed.

This direct access is useful, for example in finding all the values of a given
sfm:

    $s->index("auth");
    @auths = keys %{$s->{' index'}};

otherkey may take multiple values, in which case the index is indexed on the
values of each field in the list passed, joined by a null (\000)

    $s->index("title", "auth");
    $myind = $s->{' index'}{"mybook\000me"}[0];

for records with multiple occurrences of an indexed field, then multiple index
entries will me made. Thus

    \entry 001
    \title mybook
    \title mybook: mysubtitle
    \auth  me
    \auth  myself
    
would result in 4 index entries for this one record:

    "mybook\000me", "mybook\000myself", 
    "mybook: mysubtitle\000me", "mybook: mysubtitle\000myself"

Indexing also allows for some options, these are passed as a hash reference as
the first parameter, as in:

    $s->index({'-lines' => 1}, "title", "auth");
    
=over 4

=item -lines

Keeps the line number of the key field of each record in the index. The values
are stored in the corresponding hash:

    $s->{' lineindex'}

=item -md5

Stores an md5 hash of each record according to the index entries in

    $s->{' md5index'}
    
=back

=cut

sub index
{
    my ($self, $opts, @keys) = @_;
    my ($file, $loc, $keyloc, $index, @val, %keys, $k);
    my ($val, $v, $lcount, $md5, $lloc, $lindex, $mindex);
    
    if (defined $opts && ref($opts) ne 'HASH')
    {
        unshift (@keys, $opts);
        $opts = {};
    }
    $keys[0] = $self->{' key'} unless ($keys[0]);
    %keys = map{$_, $k++} @keys;
    $file = $self->{' INFILE'};
    $file->seek(0, 0);
    $md5 = Digest::MD5->new() if ($opts->{'-md5'});
    while ($_ = $file->getline)
    {
        $lcount++;
        if (m/^\\$self->{' key'}\s+/o)
        {
            if (defined @val)
            {
                my ($md5loc) = $md5->digest if ($opts->{'-md5'});
                foreach $v (@val)
                { 
                    my ($vk) = join("\000", @{$v});
                    push (@{$index->{$vk}}, $keyloc); 
                    push (@{$lindex->{$vk}}, $lloc) if ($opts->{'-lines'});
                    push (@{$mindex->{$vk}}, $md5loc) if ($opts->{'-md5'});
                }
                undef @val;
            }
            $md5 = Digest::MD5->new() if ($opts->{'-md5'});
            $keyloc = $loc;
            $lloc = $lcount;
        }
        if (m/^\\(\S+)\s+(.*?)\s*$/o)
        {
            $k = $1;
            $val = $2;
            if (defined $keys{$k})
            {
                my (@copy);
                if (defined $val[0][$keys{$k}])     # side effect, defines @val
                {
                    foreach $v (grep {$_->[$keys{$k}] eq $val[0][$keys{$k}]} @val)
                    { push(@copy, [@$v]); }
                    foreach $v (@copy)
                    { $v->[$keys{$k}] = $val; }
                    push (@val, @copy);
                }
                else
                {
                    foreach $v (@val)
                    { $v->[$keys{$k}] = $val; }
                }
            }
        }
        $loc = $file->tell;
        chomp;
        $md5->add($_) if ($opts->{'-md5'});
    }

    if (defined @val)
    {
        my ($md5loc) = $md5->digest if ($opts->{'-md5'});
        foreach $v (@val)
        { 
            my ($vk) = join("\000", @{$v});
            push (@{$index->{$vk}}, $keyloc); 
            push (@{$lindex->{$vk}}, $lloc) if ($opts->{'-lines'});
            push (@{$mindex->{$vk}}, $md5loc) if ($opts->{'-md5'});
        }
    }
    $self->{' index'} = $index;
    $self->{' lineindex'} = $lindex if ($opts->{'-lines'});
    $self->{' md5index'} = $mindex if ($opts->{'-md5'});
    $file->seek(0, 0);
    $self;
}


=head2 $s->findrecord("value");

Searches through the database for a key with the given value. Identical
matching only is supported. If the database has been indexed, then the index
is used in preference, which may, of course, be indexed on a different field.

For multiple records with the same index entries, multiple calls to findrecord
with the same value will refer to each record in turn.

Calling findrecord clears the readrecord marker which allows sequential
reading of records.

Returns undef if no record found and at the end of a list of records. Thus:

 while ($s->findrecord("FirstOnly")) { ... }

Will process all the records indexed by "FirstOnly".

findrecord may also be passed a list of values in which case they are joined
appropriately for searching a corresponding index with that value.

=cut

sub findrecord
{
    my ($self, @val) = @_;
    my ($index, @locs, $loc, $file, $key);
    my ($i, $val, $oldloc);
    
    $val = join("\000", @val);
    $oldloc = $self->{' thisloc'};
    $self->{' thisloc'} = -1;
    if ($index = $self->{' index'})
    {
        $self->{' find'} = $val;
        return undef unless defined $index->{$val};
        @locs = @{$index->{$val}};
        for ($i = 0; $i <= $#locs; $i++)
        {
            if ($self->{' loc'} == $locs[$i])
            {
                if ($i == $#locs)
                {
                    $self->{' thisloc'} = $oldloc;
                    $self->{' loc'} = -1;
                    return undef;
                }
                $self->{' loc'} = $locs[$i + 1];
                last;
            }
        }
        $self->{' loc'} = $locs[0] unless ($i <= $#locs);
        seek($self->{' INFILE'}, $self->{' loc'}, 0);
        return $self;
    } else {
        $key = $self->{' key'};
        $file = $self->{' INFILE'};
        $file->seek($self->{' loc'}, 0);
        $file->getline if ($self->{' find'} eq $val);
        $self->{' find'} = $val;
        $loc = $file->tell;
        while ($_ = $file->getline)
        {
            if (m/^\\$key\s+$val\s*$/o)
            {
                $self->{' loc'} = $loc;
                $file->seek($loc, 0);
                return $self;
            }
            $loc = $file->tell;
        }
        return undef;
    }
}


=head2 $s->readrecord(\@fieldlist [, $loc])

Reads a record from the current location as located by the last findrecord or
readrecord whichever is later. Notice that if the last findrecord failed then
the readrecord will start from the beginning of the file.

\@fieldlist is optional.

Multiple fields with the same name are *not* stored as an array, as might be
expected, but as fields with spaces in as in f, f 0, f 1, etc. The precise
names are returned in \@fieldlist. The advantage of this method is that users
just wanting the first occurrence don't have to decide whether something is
coming as an array or as a string. The other alternative would have been to
make every field an array resulting in major hassle for people.

A way of turning the multiple fields into an array is to use a C<map>
function of the form:

    @array = map { m/^$fieldname(?:\s+\d+)?$/o ? $s->{$_} : () } @fieldlist;

which returns an array of fields called $fieldname from $s.

$loc specifies a location in the file to read from. Usually it is undefined,
but if set allows for control over which record is read.

Returns undef if no record read (probably due to end of file).

=cut

sub readrecord
{
    my ($self, $flist, $loc) = @_;
    my ($file) = $self->{' INFILE'};
    my ($key) = $self->{' key'};
    my ($stripnl) = not $self->{' nostripnl'};
    $loc ||= $self->{' thisloc'};
    my ($foundkey) = 0;
    $loc = $self->{' loc'} if ($loc == -1);         # done a findrecord

    my ($current_key, $old_key, $data);

# first wipe out any fields stored in $self
    my (@f) = keys %$self;
    foreach (@f) { delete $self->{$_} unless (m/^\s/oi); }
    @$flist = () if (defined $flist);
    unless ($self->{' nointernal'})
    {
        $self->{' field_list'} = [];
        $self->{' field_lkup'} = {};
    }

    $file->seek($loc, 0);
    while($_ = $file->getline)
    {
        chomp;
        if (m/^\\$key\s*(.*?)\s*$/)
        {
            $self->{$key} = $1;
            push(@{$flist}, $key) if (defined $flist);
            unless ($self->{' nointernal'})
            {
                push (@{$self->{' field_list'}}, $key);
                $self->{' field_lkup'}{$key} = 0;
            }
            $foundkey = 1;
            last;
        }
        $loc = $file->tell;
    }
    return undef unless $foundkey;          # didn't find a key so return nothing

# read fields until find next key found
    $current_key = $key;    # in nomans land, between key and first field
    $loc = $file->tell;     # get current location so can return here if
                            # find a new key.
    while($_ = $file->getline)
    {
        chomp;
        if (m/^\\(\S*)\s*(.*?)\s*$/oi)   # is this a field marker of some kind?
        {
            $old_key = $current_key;
            $current_key = $1;
            $data = $2;
            if (defined $old_key && !defined $self->{' nostripws'})
            {
                $self->{$old_key} =~ s/\s*$//o;
                $self->{$old_key} =~ s/^\s*//o;
            }
            if ($current_key =~ m/^\\*$/)    # deleted records in old
                                # SHv1.2 are ignored.  Handles backup files
            {
                undef $current_key;
                next;
            }
            if ($current_key =~ m/^$key$/)
            {
                $file->seek($loc, 0);   # go to start of line
                last;                   # and exit
            }
            # iterate to find a new unique field of the same name, for multiple
            # fields of the same name in a record.  The resultant subsequent
            # field names are of the form "field n" where n is a number.
            while (defined $self->{$current_key})
            {
                my ($suff, $pref);
                if ($current_key =~ m/ /o)    # already got a long field name
                {
                    $suff = $';
                    $pref = $`;               #'
                    $suff++;                  # incremement the final no.
                }
                else                          # set up the first value
                {
                    $suff = 0;
                    $pref = $current_key;
                }
                $current_key = $pref . " " . $suff;     # make a new field
            }                                           # name
            $self->{$current_key} = $data;              # store the value
            push(@$flist, $current_key) if (defined $flist);
            unless ($self->{' nointernal'})
            {
                push (@{$self->{' field_list'}}, $current_key);
                $self->{' field_lkup'}{$current_key} = $foundkey++;
            }
                                                        # add the field name to the list
        }
        elsif (defined $current_key)           # a continuation line?
        {
            s/\s*$//o;                         # clear line final spaces
            s/^\s*//o if ($stripnl);           # perhaps strip initial ws
            $self->{$current_key} .= ($stripnl ? " " : "\n") . $_;
        }
    }
    continue
    {
        $loc = $file->tell;        # keep track of a possible new record
    }
    $self->{$current_key} =~ s/\s*$//  if (defined $current_key); # clear up at eof
    $self->{' thisloc'} = $loc;
    $self;
}


=head2 $s->proc_record($sub [,$loc])

Iterates over each line of a record calling $sub for each line, which has
been chomped. Uses the same approach as readrecord in choosing where to read.

=cut

sub proc_record
{
    my ($self, $sub, $loc) = @_;
    my ($file) = $self->{' INFILE'};
    my ($key) = $self->{' key'};
    $loc ||= $self->{' thisloc'};
    $loc = $self->{' loc'} if ($loc == -1);
    
    $file->seek($loc, 0);
    while($_ = $file->getline)
    {
        chomp;
        if (m/^\\$key([ \t]+|$)/)
        {
            &{$sub}($_);
            while ($_ = $file->getline)
            {
                chomp;
                last if (/^\\$key([ \t]+|$)/);
                &{$sub}($_);
                $loc = $file->tell;
            }
            last;
        }
        $loc = $file->tell;
    }
    $self->{' thisloc'} = $loc;
    return $self;
}


=head2 $s->allof($key)

Returns all occurrences of a given key, in field order

=cut

sub allof
{
    my ($self, $key) = @_;
    my ($k) = qr/^$key(?:\s|$)/;

    return map {$self->{$_}} sort grep {/$k/} keys %{$self};
}


=head2 $s->insert_field($offset, $field)

Inserts a field into the field list at the given offset. Returns the new name
of the field (to account for multiple identical fields).

=cut

sub insert_field
{
    my ($self, $ind, $field) = @_;
    my ($hash) = $self->{' field_lkup'};
    my ($h);
    
    while (defined $hash->{$field}) { $field =~ s/(\s\d*)?$/" " . ($1 + 1)/oe; }
    splice(@{$self->{' field_list'}}, $ind, 0, $field);
    foreach $h (keys %$hash)
    { $hash->{$h}++ if ($hash->{$h} >= $ind); }
    $hash->{$field} = $ind;
    return $field;
}


=head2 $s->delete_field($field)

Deletes a particular field from the field list (note not all occurrences, just
the specific field)

=cut

sub delete_field
{
    my ($self, $field) = @_;
    my ($hash) = $self->{' field_lkup'};
    my ($ind) = defined $hash->{$field} ? $hash->{$field} : return;
    my ($h);

    splice(@{$self->{' field_list'}}, $ind, 1);
    foreach $h (keys %$hash)
    { $hash->{$h}-- if ($hash->{$h} > $ind); }
    delete $hash->{$ind};
}


=head2 $s->rename_field($old, $new)

Renames all occurrences of old fields to new ones changing the database as well

=cut

sub rename_field
{
    my ($self, $old, $new) = @_;
    my ($k);

    foreach $k (grep {m/^$old(?:\s|$)/} @{$self->{' field_list'}})
    {
        my ($t) = "$k";
        my ($newf) = $new;
        while (defined $self->{' field_lkup'}{$newf}) { $newf =~ s/(\s\d*)?$/" ". ($1 + 1)/oe; }
        $self->{$newf} = delete $self->{$t};
        $self->{' field_list'}[$self->{' field_lkup'}{$t}] = $newf;
        $self->{' field_lkup'}{$newf} = delete $self->{' field_lkup'}{$t};
    }
}


=head2 $s->offsetof_field($field)

Returns the field index of a particular field

=cut

sub offsetof_field
{
    my ($self, $field) = @_;
    return $self->{' field_lkup'}{$field};
}


=head2 $s->printheader(\*FILE)

Prints out the header information

=cut

sub printheader
{
    my ($sh, $file) = @_;

    printf $file "\\_sh %s  %d  %s\n", $sh->{' Version'}, $sh->{' CSum'}, $sh->{' Type'};
    print $file "\\_DateStampHasFourDigitYear\n" if ($sh->{' DateStamp'} == 4);
    print $file "\n";
}

=head2 $s->printrecord(\*FILE, @fieldlist)

Prints out an SH record with fields in the given order. If $s->{' allfields'} is
set, then also add onto the end of the list, all unmentioned fields.

=cut

sub printrecord
    {
    my ($self, $file, @fields) = @_;
    my ($f);

    if ($self->{' allfields'})
        {
        foreach $f (keys %$self )   # for each field possible
            {                       # add to the list if not alread there
            push (@fields, $f) unless (grep($_ eq $f, @fields));
            }
        }
    foreach $f (@fields)              # iterate over the marker list
        {
        if ($f =~ m/ /o)              # need to trim fieldname kludging
            { print $file "\\$` "; }
        else
            { print $file "\\" ."$f "; }
        print $file "$self->{$f}\n";
        }
    print $file "\n" unless $self->{' noblank'};  # print a blank line at the end of a record
    }


=head2 $s->rewind([$pos])

Rewinds the current pointer to the start (or $pos if given)

=cut

sub rewind
{ $_[0]->{' thisloc'} = $_[0]->{' loc'} = $_[1]; }


=head2 $s->DESTROY()

The destructor for an SF database. Closes the file before disappearing.

=cut

sub DESTROY
{
    my ($self) = @_;

    $self->{' INFILE'}->close;
    undef;
}

1;
__END__
# now the test program
package main;

require SIL::Shoe::Data;

$s = SIL::Shoe::Data->new($ARGV[0], $ARGV[1]);
while ($s->readrecord(\@keys)) { $s->printrecord(\*STDOUT, @keys); }


