#!/usr/bin/perl
#
# flipflip's AlpineQuest (https://www.alpinequest.net/) Landmark Files to GPX Converter (apq2gpx)
#
# Copyright (c) 2017 Philippe Kehl <flipflip at oinkzwurgl dot org>

# apq2gpx is free software: you can redistribute it and/or modify it under the terms of the GNU
# General Public License as published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# apq2gpx is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
# the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General
# Public License for more details.
#
# You should have received a copy of the GNU General Public License along with apq2gpx. If not, see
# <http://www.gnu.org/licenses/>.
#
# See the __DATA__ section at the end of the file for usage instructions.
#
# References:
# - https://www.alpinequest.net/en/help/v2/landmarks
# - https://www.alpinequest.net/forum/viewtopic.php?f=3&t=3319
#

use strict;
use warnings;
use utf8;


####################################################################################################
# base class

package Base
{
    use Data::Dumper;

    sub new
    {
        my $class = shift;
        my %args = @_;
        my $self = { verbosity => 0, colours => undef };
        @{$self}{keys %args} = values %args;

        # enable colours if we're printing to an interactive terminal
        if (!defined $self->{colours})
        {
            $self->{colours} = -t STDERR ? 1 : 0;
        }

        # try loading colour support on Windoze
        if ($self->{colours} && ($^O =~ m{Win32}i) && !defined $Win32::Console::ANSI::VERSION)
        {
            eval "local \$^W = 0; require Win32::Console::ANSI;";
            if ($@)
            {
                $self->{colours} = 0;
            }
        }

        if ($self->{colours})
        {
            $self->{colours} = { W => "\e[33m", E => "\e[31m", P => "", D => "\e[36m", T => "\e[36m", c => "\e[35m", o => "\e[m", };
        }
        else
        {
            $self->{colours} = { W => '', E => '', P => '', D => '', T => '', c => '', o => '' };
        }

        bless($self, $class);
        return $self;
    }

    # debug printing methods
    sub ERROR
    {
        my $self = shift;
        return $self->{verbosity} >= -2 ? $self->_PRINT('E', @_) : 1;
    }
    sub WARNING
    {
        my $self = shift;
        return $self->{verbosity} >= -1 ? $self->_PRINT('W', @_) : 1;
    }
    sub PRINT
    {
        my $self = shift;
        return $self->{verbosity} >= 0 ? $self->_PRINT('P', @_) : 1;
    }
    sub DEBUG
    {
        my $self = shift;
        return $self->{verbosity} >= 1 ? $self->_PRINT('D', @_) : 1;
    }
    sub TRACE
    {
        my $self = shift;
        return $self->{verbosity} >= 2 ? $self->_PRINT('T', @_) : 1;
    }
    sub _PRINT
    {
        my $self = shift;
        my $type = shift;
        my @args = map
        {
            my $str = $_;
            if (!defined $str) { $str = '<undef>'; }
            elsif (ref($str))
            {
                local $Data::Dumper::Terse = 1;
                local $Data::Dumper::Sortkeys = 1;
                # local $Data::Dumper::Useqq = 1;
                $str = Data::Dumper::Dumper($_);
                $str =~ s{\r?\n$}{}s;
            }
            #$str =~ s/([^[:print:]\r\n])/"\\x" . sprintf('%02x', ord($1)) . "x"/ge;
            $str
        } @_;
        my $fmt = shift(@args);


        my $prefix = '?';
        my $suffix = '';
        if    ($type eq 'E') { $prefix = $self->{colours}->{E} . 'ERROR: ';   $suffix = $self->{colours}->{o}; }
        elsif ($type eq 'W') { $prefix = $self->{colours}->{W} . 'WARNING: '; $suffix = $self->{colours}->{o}; }
        elsif ($type eq 'P') { $prefix = '';                                  $suffix = ''; }
        elsif ($type eq 'D') { $prefix = $self->{colours}->{D} . 'D ' . $self->{colours}->{c} . $self->_trace() . $self->{colours}->{D} . ': '; $suffix = $self->{colours}->{o}}
        elsif ($type eq 'T') { $prefix = $self->{colours}->{T} . 'T ' . $self->{colours}->{c} . $self->_trace(1) . $self->{colours}->{T} . ': '; $suffix = $self->{colours}->{o}}

        if ($#args > -1)
        {
            printf(STDERR "$prefix$fmt$suffix\n", @args);
        }
        else
        {
            print(STDERR "$prefix$fmt$suffix\n");
        }
        return 1;
    }

    sub TRACE_HEXDUMP
    {
        my ($self, $data) = @_;
        if ($self->{verbosity} >= 2)
        {
            my $datasize = length($data);
            for (my $offs = 0; $offs < $datasize; $offs += 16)
            {
                my $s = substr($data, $offs, 16);
                my @b = unpack('C*', $s);
                my $str = sprintf('0x%04x (%04d)', $offs, $offs);
                for (my $i = 0; $i < 16; $i++)
                {
                    $str .= ' ' if (($i % 4) == 0);
                    $str .= $i <= $#b ? sprintf(' %02x', $b[$i]) : '   ';
                }
                $str .= '  ';
                for (my $i = 0; $i < 16; $i++)
                {
                    my $c = ' ';
                    if ($i <= $#b)
                    {
                        $c = chr($b[$i]);
                        $c = '.' if ($c !~ m{[[:print:]]});
                    }
                    $str .= '|' if (($i % 4) == 0);
                    $str .= $c;
                }
                $str .= '|';
                $self->TRACE($str);
            }
        }
        return 1;
    }

    sub _trace
    {
        my ($self, $level) = @_;
        my @c1 = caller(2);
        my @c2 = caller(3);
        return $level ? "$c2[3]() @ $c1[1]:$c1[2]" : "$c2[3]()";
    }
};


####################################################################################################
# AlpineQuest Landmark File

package ApqFile
{
    use base 'Base';

    use MIME::Base64;

    sub new
    {
        my $class = shift;
        my $self = $class->SUPER::new(@_);

        # new(path => ...)
        if ($self->{path})
        {
            $self->TRACE('new(path => %s)', $self->{path});
            if ($self->{path} =~ m{\.(wpt|set|rte|are|trk|ldk)$}i)
            {
                $self->{type} = lc($1);
                my $rawdata = $self->_loadraw($self->{path});
                return undef unless (defined $rawdata);
                $self->{rawdata} = $rawdata;
                $self->{rawts} = (stat($self->{path}))[9];
            }
            else
            {
                $self->ERROR("Unknown file type: %s!", $self->{path});
                return undef;
            }

        }
        # new(rawdata => ..., type => ..., rawts => ..., rawname => ...)
        elsif ($self->{rawdata} && $self->{type} && $self->{rawts} && $self->{rawname})
        {
            if ($self->{type} !~ m{^(wpt|set|rte|are|trk|ldk)$})
            {
                $self->ERROR("Unknown file type: %s!", $self->{type});
                return undef;
            }
            $self->{path} = $self->{rawname};
        }
        else
        {
            $self->ERROR("Illegal parameters!");
            return undef;
        }

        $self->{rawsize} = length($self->{rawdata});
        $self->{rawoffs} = 0;
        $self->TRACE_HEXDUMP($self->{rawdata});

        my $res = 0;
        $self->{data} = {};
        if    ($self->{type} eq 'wpt') { $res = $self->_parseWpt(); }
        elsif ($self->{type} eq 'set') { $res = $self->_parseSet(); }
        elsif ($self->{type} eq 'rte') { $res = $self->_parseRte(); }
        elsif ($self->{type} eq 'are') { $res = $self->_parseAre(); }
        elsif ($self->{type} eq 'trk') { $res = $self->_parseTrk(); }
        elsif ($self->{type} eq 'ldk') { $res = $self->_parseLdk(); }

        if ($self->_tell() != $self->_size())
        {
            $self->DEBUG('Unused data, done at 0x%04x/0x%04x.', $self->_tell(), $self->_size());
        }

        if (!$res)
        {
            $self->ERROR("Failed parsing data!");
            return undef;
        }

        return $self;
    }

    sub type
    {
        my ($self) = @_;
        return $self->{type}
    }

    sub data
    {
        my ($self) = @_;
        my $data = {};
        $data->{ts} = $self->{rawts};
        $data->{type} = $self->{type};
        $data->{path} = $self->{path};
        $data->{file} = $self->{path};
        $data->{file} =~ s{.*/}{};
        if ($self->{type} eq 'wpt')
        {
            $data->{meta} = $self->{meta};
            $data->{location} = $self->{location};
        }
        elsif ($self->{type} eq 'set')
        {
            $data->{meta} = $self->{meta};
            $data->{waypoints} = $self->{waypoints};
        }
        elsif ($self->{type} eq 'rte')
        {
            $data->{meta} = $self->{meta};
            $data->{waypoints} = $self->{waypoints};
        }
        elsif ($self->{type} eq 'are')
        {
            $data->{meta} = $self->{meta};
            $data->{locations} = $self->{locations};
        }
        elsif ($self->{type} eq 'trk')
        {
            $data->{meta} = $self->{meta};
            $data->{waypoints} = $self->{waypoints};
            $data->{segments} = $self->{segments};
        }
        elsif ($self->{type} eq 'ldk')
        {
            $data->{root} = $self->{root};
        }

        return $data;
    }

    # waypoint
    sub _parseWpt
    {
        my ($self) = @_;
        # version 2
        # - int        file version
        # - int        header size (size of data to before {Waypoint})
        # - {Waypoint}
        #   - {Metadata} (version 2)
        #   - {Location}

        # header
        my ($fileVersion, $headerSize) = $self->_checkHeader(2);
        return 0 unless (defined $headerSize);

        # skip header (it may or may not be present)
        $self->_seek( $self->_tell() + $headerSize );

        # meta data
        $self->{meta} = $self->_getMetadata(2);

        # location
        $self->{location} = $self->_getLocation();

        return $self->{meta} && $self->{location} ? 1 : 0;
    }

    sub _parseSet
    {
        my ($self) = @_;

        # version 2
        # - int         file version
        # - int         header size (size of data to before {Metadata})
        # - int         number of waypoints
        # - coordinate  longitude of first waypoint
        # - coordinate  latitude of first waypoint
        # - {Metadata}  (version 2)
        # - {Waypoints}

        # header
        my ($fileVersion, $headerSize) = $self->_checkHeader(2);
        return 0 unless (defined $headerSize);

        # skip header (it may or may not be present)
        $self->_seek( $self->_tell() + $headerSize );

        my $metadataVersion = 2;

        # metadata
        $self->{meta} = $self->_getMetadata($metadataVersion);

        # waypoints
        $self->{waypoints} = $self->_getWaypoints($metadataVersion);

        return $self->{meta} && $self->{waypoints} ? 1 : 0;
    }

    sub _parseRte
    {
        my ($self) = @_;

        # version 2
        # - int         file version
        # - int         header size (size of data to before {Metadata})
        # - int         number of waypoints
        # - coordinate  longitude of first waypoint
        # - coordinate  latitude of first waypoint
        # - timestamp   time of first waypoint
        # - double      total route length (in m)
        # - double      total route length due to elevation changes (in m)
        # - double      total route elevation gain (in m), FIXME: always NaN it seems
        # - long        total route time (in s)
        # - {Metadata}  (version 2)
        # - {Waypoints}

        # header
        my ($fileVersion, $headerSize) = $self->_checkHeader(2);
        return 0 unless (defined $headerSize);

        # skip header (it may or may not be present)
        $self->_seek( $self->_tell() + $headerSize );

        my $metadataVersion = 2;

        # metadata
        $self->{meta} = $self->_getMetadata($metadataVersion);

        # waypoints
        $self->{waypoints} = $self->_getWaypoints($metadataVersion);

        return $self->{meta} && $self->{waypoints} ? 1 : 0;
    }

    sub _parseAre
    {
        my ($self) = @_;

        # version 2
        # - int         file version
        # - int         header size (size of data to before {Metadata})
        # - int         number of locations
        # - coordinate  longitude of first location
        # - coordinate  latitude of first location
        # - double      total area length (in m)
        # - double      total area area (in m2)
        # - {Metadata}  (version 2)
        # - {Locations}

        # header
        my ($fileVersion, $headerSize) = $self->_checkHeader(2);
        return 0 unless (defined $headerSize);

        # skip header (it may or may not be present)
        $self->_seek( $self->_tell() + $headerSize );

        my $metadataVersion = 2;

        # metadata
        $self->{meta} = $self->_getMetadata($metadataVersion);

        # locations
        $self->{locations} = $self->_getLocations();

        return $self->{meta} && $self->{locations} ? 1 : 0;
    }

    sub _parseTrk
    {
        my ($self) = @_;

        # version 3 (version 2 is the same but uses a different {Metadata} and {Segments} struct
        # - int         file version
        # - int         header size (size of data to before {Metadata}
        # - int         number of locations
        # - int         number of segments
        # - int         number of waypoints
        # - coordinate  longitude of first location
        # - coordinate  latitude of first location
        # - timestamp   time of first location
        # - double      total track length (in m)
        # - double      total track length due to elevation changes (in m)
        # - double      total track elevation gain (in m)
        # - long        total track time (in s)
        # - {Metadata}  (version 2)
        # - {Waypoints}
        # - {Segments}  (version 2)

        # version 2 is the same but version 1 {Metadata} and {Segment} structs

        # header
        my ($fileVersion, $headerSize) = $self->_checkHeader(2, 3);
        return 0 unless (defined $headerSize);

        # skip header (it may or may not be present)
        $self->_seek( $self->_tell() + $headerSize );

        my $metadataVersion = $fileVersion == 3 ? 2 : 1;
        my $segmentVersion  = $fileVersion == 3 ? 2 : 1;
        $self->DEBUG('fileVersion=%s metadataVersion=%s segmentVersion=%s',
                     $fileVersion, $metadataVersion, $segmentVersion);
        # metadata
        $self->{meta} = $self->_getMetadata($metadataVersion);

        # waypoints
        $self->{waypoints} = $self->_getWaypoints($metadataVersion);

        # segments
        $self->{segments} = $self->_getSegments($segmentVersion);

        return $self->{meta} && $self->{waypoints} && $self->{segments} ? 1 : 0;
    }

    sub _parseLdk
    {
        my ($self) = @_;

        # - int       application specific magic number
        # - int       archive version
        # - pointer   {Node} position of the root node (always with list entries)
        # - double    reserved
        # - double    reserved
        # - double    reserved
        # - double    reserved

        # header
        my $hdr = $self->_getvalmulti(magic => 'int', archVersion => 'int', rootOffset => 'pointer',
            res1 => 'long', res2 => 'long', res3 => 'long', res4 => 'long');
        return 0 unless (defined $hdr->{res4});
        my $expectedMagic = 0x4c444b3a;
        if ($hdr->{magic} != $expectedMagic)
        {
            $self->WARNING('Unknown magic 0x%08x (expected 0x%08x).', $hdr->{magic}, $expectedMagic);
            return 0;
        }
        my $expectedArchVersion = 1;
        if ($hdr->{archVersion} != $expectedArchVersion)
        {
            $self->WARNING('Unknown archive version %d (expected %d.', $hdr->{archVersion}, $expectedArchVersion);
            return 0;
        }

        # root node
        $self->{root} = $self->_getNode($hdr->{rootOffset});
        $self->_debugDumpNode($self->{root}); # debug dump

        return defined $self->{root} ? 1 : 0;
    }

    sub _debugDumpNode
    {
        my ($self, $node) = @_;
        $self->DEBUG('%s: %s', $self->{path}, $node->{path});
        foreach my $file (sort { $a->{order} <=> $b->{order} } @{$node->{files}})
        {
            $self->DEBUG('%s: %s (%d bytes)', $self->{path}, "$node->{path}$file->{name}", $file->{size});
        }
        foreach (sort { $a->{order} <=> $b->{order} } @{$node->{nodes}})
        {
            $self->_debugDumpNode($_);
        }
        return 1;
    }

    sub _getNode
    {
        my ($self, $offset, $path, $uid) = @_;

        $self->DEBUG('***** node at 0x%04x *****', $offset);
        $self->_seek($offset);

        # {Node}
        # - int magic number of the node (0x00015555)
        # - int flags
        # - pointer {Metadata} position of node metadata
        # - double reserved
        # - {NodeEntries} entries of the nod
        my $hdr = $self->_getvalmulti(magic => 'int', flags => 'int', metaOffset => 'pointer',
            res1 => 'long');
        return undef unless (defined $hdr->{res1});
        my $expectedMagic = 0x00015555;
        if ($hdr->{magic} != $expectedMagic)
        {
            $self->WARNING('Unknown magic 0x%08x (expected 0x%08x).', $hdr->{magic}, $expectedMagic);
            return undef;
        }
        my $entriesOffset = $self->_tell();
        $self->DEBUG('metaOffset=0x%04x entriesOffset=0x%04x', $hdr->{metaOffset}, $entriesOffset);

        # FIXME: it's 0x20 later it seems
        my $offs = $self->_tell();
        $self->_seek($hdr->{metaOffset} + 0x20);
        my $meta = $self->_getMetadata(2); # version 2 metadata
        $self->_seek($offs);

        # root node?
        if (!$path && !$uid)
        {
            $path = '/';
        }
        # add node name or UID to path
        else
        {
            if ($meta->{name})
            {
                $path .= $meta->{name} . '/';
            }
            else
            {
                $path .= sprint('UID%08X', $uid);
            }
            $self->DEBUG('node path=%s', $path);
        }

        # {NodeEntries}
        # - int     magic number of the entries (0x00025555 or 0x00045555)
        # - {NodeEntriesAsList} or {NodeEntriesAsTable}, depending on magic
        my $nodeEntriesMagic = $self->_getval('int');
        $self->DEBUG('path=%s nodeEntriesMagic=0x%08x', $path, $nodeEntriesMagic);

        my $node = { path => $path, nodes => [], files => [], meta => $meta };

        my $nChild = 0;
        my $nEmpty = 0;
        my $nData = 0;

        # {NodeEntriesAsList}
        # - int total number of entries
        # - int number of child node entrie
        # - int number of data entries
        # - pointer {NodeEntriesAsList} position of additional entries (0 for no additional entries)
        # - {NodeEntry}* child entries (n = number of child node entries)
        # - {NodeEntry}* empty space (n = total number of entries - number of child node entries - number of data entries)
        # - {NodeEntry}* data entries (n = number of data entries)
        if ($nodeEntriesMagic == 0x00025555)
        {
            my $list = $self->_getvalmulti(nTotal => 'int', nChild => 'int', nData => 'int', addOffset => 'pointer');
            $nChild = $list->{nChild};
            $nData  = $list->{nData};
            $nEmpty = $list->{nTotal} - $nChild - $nData;
        }
        # {NodeEntriesAsTable}
        # - int number of child node entries
        # - int number of data entries
        # - {NodeEntry}* child entries (n = number of child node entries)
        # - {NodeEntry}* data entries (n = number of data entries
        elsif ($nodeEntriesMagic == 0x00045555)
        {
            my $list = $self->_getvalmulti(nChild => 'int', nData => 'int');
            $nChild = $list->{nChild};
            $nData  = $list->{nData};
            $nEmpty = 0;
        }
        # illegal magic
        else
        {
            $self->WARNING('Illegal node entries magic 0x%08x.', $nodeEntriesMagic);
            return undef;
        }

        # {NodeEntry}
        # - pointer    {Node}/{Data} position of the child node or data
        # - int        uid of the child node or data

        # child entries (nodes, directories)
        $self->DEBUG('nChild=%d', $nChild);
        my @childEntries = ();
        for (my $ix = 0; $ix < $nChild; $ix++)
        {
            my $child = $self->_getvalmulti(offset => 'pointer', uid => 'int');
            $child->{_ix} = $ix;
            push(@childEntries, $child);
        }

        # empty entries
        $self->DEBUG('nEmpty=%d', $nEmpty);
        $self->_seek( $self->_tell() + ($nEmpty * (8 + 4)) );
        #for (my $ix = 0; $ix < $nEmpty; $ix++)
        #{
        #    my $empty = $self->_getvalmulti(offset => 'pointer', uid => 'int');
        #    $self->TRACE('empty[%03d]: offset=0x%04x uid=%i', $ix, $empty->{offset}, $empty->{uid});
        #}

        # data entries (files)
        $self->DEBUG('nData=%d', $nData);
        my @dataEntries = ();
        for (my $ix = 0; $ix < $nData; $ix++)
        {
            my $data = $self->_getvalmulti(offset => 'pointer', uid => 'int');
            $data->{_ix} = $ix;
            push(@dataEntries, $data);
        }

        # debug
        foreach (@childEntries)
        {
            $self->TRACE('childEntry[%03d]: offset=0x%04x uid=0x%08x', $_->{_ix}, $_->{offset}, $_->{uid});
        }
        foreach (@dataEntries)
        {
            $self->TRACE('dataEntry[%03d]: offset=0x%04x uid=0x%08x', $_->{_ix}, $_->{offset}, $_->{uid});
        }

        # get child nodes
        foreach my $entry (@childEntries)
        {
            my $child = $self->_getNode($entry->{offset}, $path, $entry->{uid});
            return undef unless ($child);
            $child->{order} = $entry->{_ix};
            push(@{$node->{nodes}}, $child);
        }

        # get all files for this node
        foreach my $entry (@dataEntries)
        {
            my $data = $self->_getNodeData($entry);
            return undef unless (defined $data);
            # the first byte seems to be the file type
            my $fileType = substr($data, 0, 1);
            my $fileData = substr($data, 1);
            my $fileData64 = MIME::Base64::encode_base64($fileData, '');
            my $dataSize = length($fileData);
            my $type = unpack('C', $fileType);
            my %typeMap = ( 0x65 => 'wpt', 0x66 => 'set', 0x67 => 'rte', 0x68 => 'trk', 0x69 => 'are' );
            my $typeStr = $typeMap{$type} ? $typeMap{$type} : 'bin';
            my $base1 = substr($self->{path}, 0, -4); # strip '.ldk'
            my $base2 = $path; $base2 =~ s{/}{_}g;
            my $fileName = sprintf('%s%sUID%08X.%s', $base1, $base2, $entry->{uid}, $typeStr);
            push(@{$node->{files}}, { name => $fileName, data => $fileData64, type => $typeStr, size => $dataSize, order => $entry->{_ix} });
        }

        foreach (@{$node->{nodes}})
        {
            $self->DEBUG('child %s', $_->{path});
        }
        foreach (@{$node->{files}})
        {
            $self->DEBUG('file %s (%d bytes)', $node->{path} . $_->{name}, $_->{size});
        }

        return $node;
    }

    sub _getNodeData
    {
        my ($self, $def) = @_;
        my $data = '';
        $self->TRACE('offset=0x%04x uid=0x%08x', $def->{offset}, $def->{uid});

        # {Data}
        # - int      magic number of the data block 0x00105555
        # - int      flags
        # - long     total size of data in bytes
        # - long     size of the main data block in bytes
        # - pointer  {DataAdditionalBlock} position of the next additional data block
        # - *        byte data

        # header
        $self->_seek($def->{offset});
        my $hdr = $self->_getvalmulti(magic => 'int', flags => 'int',
            totalSize => 'long', size => 'long', addOffset => 'pointer');
        return undef unless (defined $hdr->{addOffset});

        my $expectedMagic = 0x00105555;
        if ($hdr->{magic} != $expectedMagic)
        {
            $self->WARNING('Illegal data magic 0x%08x (expected 0x%08x).',
                           $hdr->{magic}, $expectedMagic);
            return undef;
        }

        # data
        $data .= $self->_getval('raw', $hdr->{size});

        # additional data?
        if ($hdr->{addOffset})
        {
            my $addData = $self->_getNodeAdditionalData($hdr->{addOffset});
            return undef unless (defined $addData);
            $data .= $addData;
        }

        return $data;
    }

    sub _getNodeAdditionalData
    {
        my ($self, $offset) = @_;
        my $data = '';

        # {DataAdditionalBlock}
        # - int      magic number of the additional data block 0x00205555
        # - long     size of the additional data block in bytes
        # - pointer  {DataAdditionalBlock} position of the next additional data block
        # - *        byte data

        # header
        my $hdr = $self->_getvalmulti(magic => 'int', size => 'long', addOffset => 'pointer');
        return undef unless (defined $hdr->{addOffset});

        my $expectedMagic = 0x00205555;
        if ($hdr->{magic} != $expectedMagic)
        {
            $self->WARNING('Illegal additional data magic 0x%08x (expected 0x%08x).',
                           $hdr->{magic}, $expectedMagic);
            return undef;
        }

        # additional data
        my $addData = $self->_getval('raw', $hdr->{size});
        return undef unless (defined $addData);
        $data .= $addData;

        # more?
        if ($hdr->{addOffset})
        {
            my $moreData = $self->_getNodeAdditionalData($hdr->{addOffset});
            return undef unless (defined $moreData);
            $data .= $moreData;
        }

        return $data;
    }

    sub _loadraw
    {
        my ($self, $path) = @_;

        if (!defined $path || ! -r $path)
        {
            $self->WARNING("Cannot read '%s'!", $path);
            return undef;
        }
        my $fh;
        unless (open($fh, '<:raw', $path))
        {
            $self->WARNING("Failed reading '%s': %s", $path, $!);
            return 0;
        }
        my $size = -s $path;
        my $raw;
        read($fh, $raw, $size);
        close($fh);
        my $rawsize = length($raw);

        $self->TRACE("Read '%s': %d/%d bytes.", $path, $rawsize, $size);
        if ($rawsize != $size)
        {
            $self->WARNING("Failed reading '%s': filesize %d != raw size %d!",
                           $path, $rawsize);
            return undef;
        }

        return $raw;
    }

    sub _tell
    {
        my ($self) = @_;
        return $self->{rawoffs};
    }
    sub _seek
    {
        my ($self, $offs) = @_;
        $self->TRACE('seek 0x%04x %+i = 0x%04x', $self->{rawoffs}, $offs - $self->{rawoffs}, $offs);
        return $self->{rawoffs} = $offs;
    }
    sub _size
    {
        my ($self) = @_;
        return $self->{rawsize};
    }

    sub _getval
    {
        my ($self, $type, $arg) = @_;
        # FIXME: more error handling
        if ($self->{rawoffs} >= $self->{rawsize})
        {
            $self->DEBUG("No more '%s' data at offset 0x%04x/0x%04x!", $type, $self->{rawoffs}, $self->{rawsize});
            return undef;
        }
        my $value = undef;
        my $raw = '';
        if ($type eq 'int') # 4 bytes, big endian, signed
        {
            $raw = substr($self->{rawdata}, $self->{rawoffs}, 4);
            $value = unpack('l>', $raw);
            $self->{rawoffs} += 4;
        }
        elsif ($type eq 'bool') # 1 byte, boolean
        {
            $raw = substr($self->{rawdata}, $self->{rawoffs}, 1);
            $value = unpack('c', $raw);
            $self->{rawoffs} += 1;
        }
        elsif ($type eq 'long') # 8 bytes, big-endian, signed
        {
            $raw = substr($self->{rawdata}, $self->{rawoffs}, 8);
            $value = unpack('q>', $raw);
            $self->{rawoffs} += 8;
        }
        elsif ($type eq 'pointer') # 8 bytes, big-endian, unsigned (?)
        {
            $raw = substr($self->{rawdata}, $self->{rawoffs}, 8);
            $value = unpack('Q>', $raw);
            $self->{rawoffs} += 8;
        }
        elsif ($type eq 'double') # 8 bytes, IEEE754
        {
            $raw = substr($self->{rawdata}, $self->{rawoffs}, 8);
            $value = unpack('d>', $raw);
            $self->{rawoffs} += 8;
        }
        elsif ($type eq 'int+raw') # size int + raw data
        {
            my $size = $self->_getval('int');
            $raw = substr($self->{rawdata}, $self->{rawoffs}, $size);
            $value = $raw;
            $self->{rawoffs} += $size;
        }
        elsif ($type eq 'raw') # raw binary data
        {
            my $size = $arg;
            $raw = substr($self->{rawdata}, $self->{rawoffs}, $size);
            $value = $raw;
            $self->{rawoffs} += $size;
        }
        elsif ($type eq 'string') # string
        {
            my $size = $arg;
            $raw = substr($self->{rawdata}, $self->{rawoffs}, $size);
            $value = $raw;
            $self->{rawoffs} += $size;
        }
        elsif ($type eq 'coordinate') # int, scale 1e-7
        {
            $value = $self->_getval('int');
            $value *= 1e-7;
        }
        elsif ($type eq 'height') # int, scale 1e-7
        {
            $value = $self->_getval('int');
            if ($value == -999999999)
            {
                $value = undef;
            }
            else
            {
                $value *= 1e-3;
            }
        }
        elsif ($type eq 'timestamp') # long, scale 1e-3
        {
            $value = $self->_getval('long');
            if ($value == 0)
            {
                $value = undef;
            }
            else
            {
                $value *= 1e-3;
            }
        }
        elsif ($type eq 'accuracy') # int, scale 1e-7
        {
            $value = $self->_getval('int');
            if ($value == 0)
            {
                $value = undef;
            }
        }
        elsif ($type eq 'pressure') # int, scale 1e-3
        {
            $value = $self->_getval('int');
            if ($value == 999999999)
            {
                $value = undef;
            }
            else
            {
                $value *= 1e-3;
            }
        }
        else
        {
            $self->WARNING("Illegal type '%s'!", $type);
            return undef;
        }

        my $size = length($raw);
        my $oldRawoffs = $self->{rawoffs} - $size;
        if ($oldRawoffs < $self->{rawsize})
        {
            $self->TRACE('%-10s at 0x%04x (%04d) [%02d] %s = %s', $type, $oldRawoffs, $oldRawoffs, $size,
                         join(' ', map { sprintf('%02x', $_) } unpack('C*', substr($self->{rawdata}, $oldRawoffs, $size))),
                         $type =~ m{raw} ? '<...>' : $value);
        }

        return $value;
    }

    sub _getvalmulti
    {
        my ($self, @pairs) = @_;
        my $data = { _order => [] };
        while ($#pairs > 0)
        {
            my $key = shift(@pairs);
            my $type = shift(@pairs);
            $data->{$key} = $self->_getval($type);
            push(@{$data->{_order}}, $key);
        }
        $self->DEBUG(join(' ', map { "$_=" . ($data->{$_} // '<undef>') } @{$data->{_order}}));
        return $data;
    }

    sub _checkHeader
    {
        my ($self, @expectedFileVersions) = @_;
        my $fileVersion = $self->_getval('int');
        my $headerSize  = $self->_getval('int');
        $self->DEBUG('fileVersion=%s headerSize=%s', $fileVersion, $headerSize);
        my %okayFileVersions = map { $_, 1 } @expectedFileVersions;
        if (!defined $fileVersion || !$okayFileVersions{$fileVersion})
        {
            $self->WARNING('Unknown file version %s (expected %s).', $fileVersion, join(' or ', @expectedFileVersions));
            return (undef, undef);
        }
        return ($fileVersion, $headerSize);
    }

    sub _getMetadata
    {
        my ($self, $metadataVersion) = @_;

        # This is what the specs say:
        #
        # - {Metadata}
        #   - {MetadataContent}        main metadata content
        #   - int                      number of extended metadata contents (-1 for none) -- seems to be -1 always
        #   - {MetadataContentExt}*    extended metadata contents
        # - {MetadataContent}
        #   - int                      size of entries
        #   - {MetadataContentEntry}
        # - {MetadataContentExt}
        #   - string                   name of extention
        #   - {MetadataContent}
        # - {MetadataContentEntry}
        #   - string                   entry name
        #   - int                      type of entry
        #                              -1 = bool (1 byte), -2 = long (8 bytes), -3 = double (8 bytes),
        #                              -4 = raw (int with size of data + data), >= 0 = string
        #   - *                        data (size depends on the type of entry)
        # - int         unknown (not documented in spec), always 0xffffffff (-1) it seems
        #
        # This is what I think it is (which may or may not be the same as above...):
        #
        # - {MetadataContent}
        #   - int   number of {MetadataContentEntry} structs
        #   - {MetadataContentEntry}
        #     - int     length of name string
        #     - string  name string
        #     - int     type of entry (see above)
        #     - *       data
        # - {MetadataContentExt}
        #   - int    number of {MetadataContentExt} -- always -1 it seems
        #   - {MetadataContentExt}
        #     - string             name of extension, FIXME: nul terminated?
        #     - {MetadataContent}  same as above?!

        my $nMetaEntries = $self->_getval('int');
        $self->DEBUG('nMetaEntries=%d metadataVersion=%s', $nMetaEntries, $metadataVersion);

        my $meta = { _order => [], _types => [] };
        for (my $ix = 0; $ix < $nMetaEntries; $ix++)
        {
            my $nameLen = $self->_getval('int');
            my $name    = $self->_getval('string', $nameLen);
            my $dataLen = $self->_getval('int') // return undef;;
            my $data = undef;
            my $type = undef;
            if    ($dataLen == -1) { $type = 'bool';    $data = $self->_getval($type); }
            elsif ($dataLen == -2) { $type = 'long';    $data = $self->_getval($type); }
            elsif ($dataLen == -3) { $type = 'double';  $data = $self->_getval($type); }
            elsif ($dataLen == -4) { $type = 'int+raw'; $data = $self->_getval($type); }
            elsif ($dataLen >=  0) { $type = 'string';  $data = $self->_getval($type, $dataLen); }
            else
            {
                $self->WARNING('Illegal meta data entry type %d.', $dataLen);
                return undef;
            }
            $meta->{$name} = $data;
            push(@{$meta->{_order}}, $name);
            push(@{$meta->{_types}}, $type);
        }

        if ($metadataVersion == 2)
        {
            my $nMetaExt = $self->_getval('int');
            $self->DEBUG('nMetaExt=%d', $nMetaExt);
            if ($nMetaExt > 0) # typically -1 in most files, typically 0 in LDK files
            {
                $self->WARNING("Extended metadata entries not implemented (nMetaExt=%d).", $nMetaExt);
                return undef;
            }
        }

        for (my $ix = 0; $ix <= $#{$meta->{_order}}; $ix++)
        {
            my $key = $meta->{_order}->[$ix];
            $self->DEBUG('meta %2d: %-15s %-10s = %s', $ix + 1,
                         $key, "($meta->{_types}->[$ix])", $meta->{$key});
        }

        return $meta;
    }

    sub _getLocation
    {
        my ($self, $offset) = @_;
        # {Location}
        # - int        structure size (bytes)
        # - coordinate longitude
        # - coordinate latitude
        # - height     elevation
        # - timestamp  time
        # - [accuracy] accuracy (optional, depending on structure size)
        # - [pressure] pressure (optional, depending on structure size)

        my $location = { lat => undef, lon => undef, alt => undef, ts => undef, acc => undef, bar => undef };

        my $size = $self->_getval('int') // return undef;
        $location->{lon} = $self->_getval('coordinate');
        $location->{lat} = $self->_getval('coordinate');
        $location->{alt} = $self->_getval('height');
        $location->{ts}  = $self->_getval('timestamp');
        if ($size > 20)
        {
            $location->{acc} = $self->_getval('accuracy');
        }
        if ($size > 24)
        {
            $location->{bar} = $self->_getval('pressure');
        }

        foreach (qw(lat lon alt ts acc bar))
        {
            delete $location->{$_} unless (defined $location->{$_});
        }

        $self->DEBUG('location: llh = %12.8f %11.8f %8s, ts = %s, acc = %s, bar = %s',
                     $location->{lon}, $location->{lat}, defined $location->{alt} ? sprintf('%8.3f', $location->{alt}) : 'n/a',
                     $location->{ts}, $location->{acc} // 'n/a', $location->{bar} // 'n/a');

        return $location;
    }

    sub _getWaypoints
    {
        my ($self, $metadataVersion) = @_;
        # {Waypoints}
        # - int         number of waypoints
        # - {Waypoint}*
        my @waypoints = ();

        my $nWaypoints = $self->_getval('int') // return undef;
        $self->DEBUG('nWaypoints=%s', $nWaypoints);

        for (my $ix = 0; $ix < $nWaypoints; $ix++)
        {
            # meta data
            my $meta = $self->_getMetadata($metadataVersion);

            # location
            my $location = $self->_getLocation();

            if (!$meta || !$location)
            {
                return undef;
            }

            push(@waypoints, { meta => $meta, location => $location });
        }

        return \@waypoints;
    }

    sub _getLocations
    {
        my ($self) = @_;
        # {Locations}
        # - int         number of locations
        # - {Location}*
        my @locations = ();

        my $nLocations = $self->_getval('int') // return undef;
        $self->DEBUG('nLocations=%s', $nLocations);

        for (my $ix = 0; $ix < $nLocations; $ix++)
        {
            # location
            my $location = $self->_getLocation();

            if (!$location)
            {
                return undef;
            }

            push(@locations, $location);
        }

        return \@locations;
    }

    sub _getSegments
    {
        my ($self, $segmentVersion) = @_;
        # {Segments}
        # - int         number of segments
        # - {Segment}*

        my @segments = ();

        my $nSegments = $self->_getval('int') // return undef;
        $self->DEBUG('nSegments=%s', $nSegments);

        for (my $ix = 0; $ix < $nSegments; $ix++)
        {
            # segment
            my $segment = $self->_getSegment($segmentVersion);

            if (!$segment)
            {
                return undef;
            }

            push(@segments, $segment);
        }

        return \@segments;
    }

    sub _getSegment
    {
        my ($self, $segmentVersion) = @_;
        # {Segment} version 1
        # - int         unknown (not documented in spec), always 0x00000000 (0) it seems
        # - int         number of locations
        # - {Location}*
        # {Segment} version 2
        # - int         unknown (not documented in spec), always 0x00000000 (0) it seems
        # - int         unknown (not documented in spec), always 0xffffffff (-1) it seems
        # - int         number of locations
        # - {Location}*

        my @locations = ();

        my $unknown1 = $self->_getval('int');
        my $unknown2 = $self->_getval('int') if ($segmentVersion >= 2);
        my $nLocations = $self->_getval('int') // return undef;
        $self->DEBUG('unknown1=%s unknown2=%s nLocations=%s segmentVersion=%s',
                     $unknown1, $unknown2, $nLocations, $segmentVersion);

        for (my $ix = 0; $ix < $nLocations; $ix++)
        {
            # location
            my $location = $self->_getLocation();

            if (!$location)
            {
                return undef;
            }

            push(@locations, $location);
        }

        return \@locations;
    }

};

####################################################################################################
# application

package App
{
    use base 'Base';

    use JSON::PP;
    use Geo::Gpx;
    use XML::LibXML;
    use List::Util qw();
    use MIME::Base64 qw();
    use Clone qw();
    #use DateTime;

    sub new
    {
        my $class = shift;
        my $argv = shift;
        my $self = $class->SUPER::new(@_);

        $self->{files} = [];
        $self->{dojson} = 0;
        $self->{dogpx} = 0;
        $self->{dobin} = 0;
        $self->{domerge} = 0;
        $self->{overwrite} = 0;
        $self->{outbase} = '';

        while (my $arg = shift(@{$argv}))
        {
            if    ($arg eq '-v') { $self->{verbosity}++; }
            elsif ($arg eq '-q') { $self->{verbosity}--; }
            elsif ($arg eq '-j') { $self->{dojson}++; }
            elsif ($arg eq '-g') { $self->{dogpx}++; }
            elsif ($arg eq '-b') { $self->{dobin}++; }
            elsif ($arg eq '-m') { $self->{domerge}++; }
            elsif ($arg eq '-f') { $self->{overwrite} = 1; }
            elsif ($arg eq '-o') { $self->{outbase} = shift(@{$argv}); }
            elsif (-f $arg)      { push(@{$self->{files}}, $arg); }
            elsif ($arg eq '-h')
            {
                $self->{files} = [];
                print(STDERR $_) for (<main::DATA>);
                return $self;
            }
            else
            {
                $self->ERROR("Illegal argument '%s'!", $arg);
                return undef;
            }
        }
        $self->TRACE('files=%s', $self->{files});

        if ($#{$self->{files}} < 0)
        {
            return undef;
        }

        return $self;
    }

    sub run
    {
        my $self = shift;
        $self->TRACE('run()');

        my $errors = 0;
        my @allDatas = ();
        foreach my $file (@{$self->{files}})
        {
            $self->PRINT("Loading: %s", $file);
            my $apq = ApqFile->new(path => $file, verbosity => $self->{verbosity});
            if (!$apq)
            {
                $errors++;
                continue;
            }

            my @datas = ();

            # in case of a LDK file we want to process the contents individually
            if ($apq->type() eq 'ldk')
            {
                my $data = $apq->data();
                push(@datas, $data);

                if ($self->{dobin})
                {
                    my $binBase = $data->{path};
                    $binBase =~ s{\.ldk$}{}i;
                    if (!$self->_writeBin($self->{outbase} || $binBase, $data))
                    {
                        $errors++;
                    }
                }

                if ($self->{dojson} || $self->{dogpx})
                {
                    my @ldkDatas = $self->_loadNodes($data->{root}, $data->{path});
                    return undef unless ($#ldkDatas > -1);
                    push(@datas, @ldkDatas);
                }
            }
            else
            {
                push(@datas, $apq->data());
            }

            # merge?
            if ($self->{domerge})
            {
                push(@allDatas, @datas);
            }
            # generate individual output
            else
            {
                if (!$self->_procDatas(@datas))
                {
                    $errors++;
                }
            }
        }

        if ($self->{domerge})
        {
            my $data = $self->_combineDatas(@allDatas);
            if (!$self->_procDatas($data))
            {
                $errors++;
            }
        }

        return $errors ? 0 : 1;
    }

    sub _procDatas
    {
        my ($self, @datas) = @_;
        my $errors = 0;
        foreach my $data (@datas)
        {
            my $base = $data->{path};
            $base =~ s{\.[^.]+$}{};
            if ($self->{outbase})
            {
                if (index($base, '/') > -1)
                {
                    $base =~ s{^.*/}{$self->{outbase}};
                }
                else
                {
                    $base =~ s{^}{$self->{outbase}};
                }
            }
            if ($self->{dojson})
            {
                if (!$self->_writeJson($self->{outbase} eq '-' ? '-' : "$base.json", $data))
                {
                    $errors++;
                }
            }
            if ($self->{dogpx} && ($data->{type} ne 'ldk'))
            {
                if (!$self->_writeGpx($self->{outbase} eq '-' ? '-' : "$base.gpx", $data))
                {
                    $errors++;
                }
            }
        }
        return $errors ? 0 : 1;
    }

    sub _writeJson
    {
        my ($self, $file, $data) = @_;
        if (-f $file && !$self->{overwrite})
        {
            $self->WARNING("File already exists: %s", $file);
            return 0;
        }
        $self->PRINT('Writing: %s', $file);
        my $json = JSON::PP->new()->utf8()->pretty($self->{dojson} > 1 ? 1 : 0)->canonical(1)->encode($data);
        return $self->_writeFile($file, $json);
    }

    sub _writeGpx
    {
        my ($self, $file, $data) = @_;
        if (-f $file && !$self->{overwrite})
        {
            $self->WARNING("File already exists: %s", $file);
            return 0;
        }

        $self->PRINT('Writing: %s', $file);

        my $gpx = Geo::Gpx->new();
        $gpx->time( $self->_gpx_time($data->{ts}) );

        # global meta data
        my $globalMeta = $data->{meta} // {};

        # waypoint
        if ($data->{type} eq 'wpt')
        {
            #$self->_gpx_set_meta($gpx, $globalMeta);
            my $wpt = $self->_gpx_loc2wpt($data->{location}, $globalMeta);
            $gpx->waypoints([ $wpt ]);
            $gpx->time( $self->_gpx_time($data->{location}->{ts}) ) if ($data->{location}->{ts});
        }
        # set of waypoints
        elsif ($data->{type} eq 'set')
        {
            $self->_gpx_set_meta($gpx, $globalMeta);
            my @ts = ();
            my @wpts = ();
            foreach my $waypoint (@{$data->{waypoints}})
            {
                my $wpt = $self->_gpx_loc2wpt($waypoint->{location}, $waypoint->{meta});
                push(@wpts, $wpt);
                push(@ts, $waypoint->{location}->{ts}) if ($waypoint->{location}->{ts});
            }
            $gpx->waypoints(\@wpts);
            $gpx->time($self->_gpx_time(List::Util::min(@ts))) if ($#ts > -1);
        }
        # area
        elsif ($data->{type} eq 'are')
        {
            $self->_gpx_set_meta($gpx, $globalMeta);
            my @wpts = ();
            foreach my $location (@{$data->{locations}})
            {
                my $wpt = $self->_gpx_loc2wpt($location);
                push(@wpts, $self->_gpx_loc2wpt($location));
            }
            push(@wpts, $wpts[0]) if ($#wpts > 1);
            my $route = {};
            $route->{name} = $globalMeta->{name} || 'Area';
            $route->{points} = \@wpts;
            $gpx->routes([ $route ]);
        }
        # route
        elsif ($data->{type} eq 'rte')
        {
            $self->_gpx_set_meta($gpx, $globalMeta);
            my @ts = ();
            my @wpts = ();
            foreach my $waypoint (@{$data->{waypoints}})
            {
                my $wpt = $self->_gpx_loc2wpt($waypoint->{location}, $waypoint->{meta});
                push(@wpts, $wpt);
                push(@ts, $waypoint->{location}->{ts}) if ($waypoint->{location}->{ts});
            }
            $gpx->waypoints(\@wpts);
            $gpx->time($self->_gpx_time(List::Util::min(@ts))) if ($#ts > -1);
        }
        # track
        elsif ( ($data->{type} eq 'trk') || ($data->{type} eq 'all') )
        {
            $self->_gpx_set_meta($gpx, $globalMeta);
            my @ts = ();
            my @wpts = ();
            foreach my $waypoint (@{$data->{waypoints}})
            {
                my $wpt = $self->_gpx_loc2wpt($waypoint->{location}, $waypoint->{meta});
                push(@wpts, $wpt);
                push(@ts, $waypoint->{location}->{ts}) if ($waypoint->{location}->{ts});
            }
            $gpx->waypoints(\@wpts);
            my @segments = ();
            foreach my $segment (@{$data->{segments}})
            {
                my @points = ();
                foreach my $location (@{$segment})
                {
                    my $wpt = $self->_gpx_loc2wpt($location);
                    push(@points, $wpt);
                    push(@ts, $location->{ts}) if ($location->{ts});
                }
                push(@segments, { points => \@points });
            }
            my $track = {};
            $track->{name} = $globalMeta->{name} || 'Track';
            $track->{segments} = \@segments;
            $gpx->tracks([ $track ]);
            $gpx->time($self->_gpx_time(List::Util::min(@ts))) if ($#ts > -1);
        }
        # pointless..
        elsif ($data->{type} eq 'ldk')
        {
            return 1;
        }
        # unhandled
        else
        {
            $self->ERROR('WTF?! type=%s', $data->{type});
            return 0;
        }

        # render XML
        my $xml = $gpx->xml('1.1');
        if ($self->{dogpx} > 1)
        {
            my $doc = XML::LibXML->load_xml(string => $xml, { no_blanks => 1 });
            $xml = $doc->toString(1);
        }

        # AlpineQuest doesn't like the 'yyyy-mm-ddThh:mm:ss+00:00' timezone specifier, it wants 'Z' instead of '+00:00'
        #$xml =~ s{\+00:00<}{Z<}gms;
        # bug filed: https://www.alpinequest.net/forum/viewtopic.php?f=4&t=3326

        return $self->_writeFile($file, $xml);
    }

    sub _gpx_set_meta
    {
        my ($self, $gpx, $meta) = @_;
        if ($meta->{comment})
        {
            $gpx->desc($meta->{comment});
        }
        if ($meta->{name})
        {
            $gpx->name($meta->{name});
        }
        if ($meta->{keywords})
        {
            $gpx->keywords([ split(/\s+/, $meta->{keywords}) ]);
        }
        return 1;
    }

    sub _gpx_loc2wpt
    {
        my ($self, $location, $meta) = @_;
        #$self->TRACE('loc2wpt: %s %s', $location, $meta);
        my $wpt = {};
        $wpt->{lon}  = $location->{lon};
        $wpt->{lat}  = $location->{lat};
        $wpt->{ele}  = $location->{alt} if (defined $location->{alt});
        $wpt->{time} = $self->_gpx_time($location->{ts})  if (defined $location->{ts});
        $wpt->{sym}  = $meta->{sym}     if ($meta && $meta->{icon});   # better use "type" field?
        $wpt->{name} = $meta->{name}    if ($meta && $meta->{name});
        $wpt->{desc} = $meta->{comment} if ($meta && $meta->{comment});
        # FIXME: isn't there a <cmt/> field in GPX?
        # acc?, bar?
        return $wpt;
    }

    sub _gpx_time
    {
        my ($self, $ts) = @_;
        #return DateTime->from_epoch(epoch => $ts, time_zone => 'UTC');
        return $ts;
    }

    sub _writeBin
    {
        my ($self, $base, $data) = @_;

        if ($base eq '-')
        {
            $self->WARNING('Cannot write %s type contents to standard output.', uc($data->{type}));
            return 0;
        }

        if ($data->{type} eq 'ldk')
        {
            return $self->_writeNodeFiles($data->{root}, $base);
        }
        else
        {
            $self->WARNING('Cannot write %s type files.', uc($data->{type}));
            return 0;
        }

    }

    sub _writeNodeFiles
    {
        my ($self, $node, $base) = @_;

        foreach my $file (sort { $a->{order} <=> $b->{order} } @{$node->{files}})
        {
            my $outFile = $node->{path} . $file->{name};
            $outFile =~ s{/+}{_}g;
            $outFile = $base . $outFile;

            if (-f $outFile && !$self->{overwrite})
            {
                $self->WARNING("File already exists: %s", $outFile);
            }
            else
            {
                $self->PRINT('Writing: %s', $outFile);
                my $data = MIME::Base64::decode_base64($file->{data});
                if (!$self->_writeFile($outFile, $data))
                {
                    return 0;
                }
            }
        }
        foreach (sort { $a->{order} <=> $b->{order} } @{$node->{nodes}})
        {
            if (!$self->_writeNodeFiles($_, $base))
            {
                return 0;
            }
        }
        return 1;
    }

    sub _writeFile
    {
        my ($self, $file, $data) = @_;
        if ($file eq '-')
        {
            print($data);
            return 1;
        }
        else
        {
            my $fh;
            if (open($fh, '>', $file))
            {
                print($fh $data);
                close($fh);
                return 1;
            }
            else
            {
                $self->WARNING("Failed writing: %s", $!);
                return 0;
            }
        }
    }

    sub _loadNodes
    {
        my ($self, $node, $ldkFile) = @_;
        my @datas = ();
        foreach my $file (sort { $a->{order} <=> $b->{order} } @{$node->{files}})
        {
            $self->PRINT('Loading: %s:%s%s', $ldkFile, $node->{path}, $file->{name});
            my $data = MIME::Base64::decode_base64($file->{data});
            my $apq = ApqFile->new(rawdata => $data, rawname => $file->{name}, type => $file->{type}, rawts => time(), verbosity => $self->{verbosity});
            return undef unless ($apq);
            push(@datas, $apq->data());
        }
        foreach (sort { $a->{order} <=> $b->{order} } @{$node->{nodes}})
        {
            my @moreDatas = $self->_loadNodes($_, $ldkFile);
            return undef unless ($#moreDatas > -1);
            push(@datas, @moreDatas);
        }
        return @datas;
    }

    sub _combineDatas
    {
        my ($self, @datas) = @_;
        my $all = { waypoints => [], segments => [], meta => { _order => [], _types => [] } };
        my @metaComments = ();
        foreach my $data (@datas)
        {
            $self->DEBUG('combine %s: %s', $data->{path}, $data);
            if ($data->{type} eq 'wpt')
            {
                push(@{$all->{waypoints}}, { location => $data->{location}, meta => $data->{meta} });
                push(@metaComments, $data->{file} . ($data->{meta}->{name} ? " ($data->{meta}->{name})" : ''));
            }
            elsif ($data->{type} eq 'set')
            {
                foreach my $wpt (@{$data->{waypoints}})
                {
                    $wpt->{meta} = $self->_mergeMeta($data->{meta}, $wpt->{meta});
                    push(@{$all->{waypoints}}, $wpt);
                }
                push(@metaComments, $data->{file} . ($data->{meta}->{name} ? " ($data->{meta}->{name})" : ''));
            }
            elsif ($data->{type} eq 'are')
            {
                my $nLocations = $#{$data->{locations}} + 1;
                for (my $ix = 0; $ix < $nLocations; $ix++)
                {
                    my $wpt = $data->{locations}->[$ix];
                    my $meta = { _order => [ 'name' ], _types => [ 'string' ],
                                 name => sprintf('location %d/%d', $ix + 1, $nLocations) };
                    $wpt->{meta} = $self->_mergeMeta($data->{meta}, $meta);
                    push(@{$all->{waypoints}}, $wpt);
                }
                push(@metaComments, $data->{file} . ($data->{meta}->{name} ? " ($data->{meta}->{name})" : ''));
            }
            elsif ($data->{type} eq 'rte')
            {
                my $nWaypoints = $#{$data->{waypoints}} + 1;
                for (my $ix = 0; $ix < $nWaypoints; $ix++)
                {
                    my $wpt = $data->{locations}->[$ix];
                    if (!$wpt->{meta}->{name})
                    {
                        $wpt->{meta}->{name} = sprintf('waypoint %d/%d', $ix + 1, $nWaypoints);
                        push(@{$wpt->{meta}->{_order}}, 'name');
                        push(@{$wpt->{meta}->{_types}}, 'string');
                    }
                    $wpt->{meta} = $self->_mergeMeta($data->{meta}, $wpt->{meta});
                    push(@{$all->{waypoints}}, $wpt);
                }
                push(@metaComments, $data->{file} . ($data->{meta}->{name} ? " ($data->{meta}->{name})" : ''));
            }
            elsif ($data->{type} eq 'trk')
            {
                push(@{$all->{segments}}, @{$data->{segments}});
                push(@metaComments, $data->{file} . ($data->{meta}->{name} ? " ($data->{meta}->{name})" : ''));
            }
            elsif ($data->{type} eq 'ldk')
            {
                # ignore
            }
        }

        push(@{$all->{meta}->{_order}}, 'comment');
        push(@{$all->{meta}->{_types}}, 'string');
        $all->{meta}->{comment} = join("\n", "Combination of:", @metaComments);
        $all->{type} = 'all';
        $all->{file} = 'merged.all';
        $all->{path} = $all->{file};
        return $all;
    }

    sub _mergeMeta
    {
        my ($self, $meta1, $meta2) = @_;
        my $meta = Clone::clone($meta1);
        for (my $ix = 0; $ix <= $#{$meta2->{_order}}; $ix++)
        {
            my $key = $meta2->{_order}->[$ix];
            if ($meta2->{$key})
            {
                if (!$meta->{$key})
                {
                    push(@{$meta->{_order}}, $key);
                    push(@{$meta->{_types}}, $meta2->{_types}->[$ix]);
                }
                if ($meta->{$key} ne $meta2->{$key})
                {
                    $meta->{$key} .= ', ' . $meta2->{$key};
                }
            }
        }
        return $meta;
    }
};

####################################################################################################
# instantiate application and run it

package main;

use strict;
use warnings;

my $app = App->new([ @ARGV ]);

if ($app && $app->run())
{
    exit(0);
}
else
{
    print(STDERR "Try '$0 -h'.\n");
    exit(1);
}

__DATA__
flipflip's AlpineQuest (https://www.alpinequest.net/) Landmark Files to GPX Converter

This tool can read the following AlpineQuest for Android version 2.0.6 file formats and convert them
to GPX and JSON files:

 - WPT: waypoint file (.wpt files)
 - SET: set (of waypoints) file (.set files)
 - RTE: route file (.rte files)
 - ARE: area file (.are files)
 - TRK: track (a.k.a. path) file (.trk files)
 - LDK: landmark (container) file (.ldk files)

Usage:

   apq2gpx.pl [-v] [-q] [-j] [-g] [-b] [-f] <file> ...

Where:

   -v / -q  increases / decrease verbosity
   -j       generate JSON output (add second -j for pretty-printing the JSON data)
   -g       generate GPX output (add second -g for pretty-printing the JSON data)
   -b       write LDK contents to individual files (only for .ldk input files)
   -m       merge all input files into a single output file instead of individual files
   -f       overwrite already existing (.json, .gpx) files
   -o ...   output base name (default input file path and base name) or '-' for standard output
   <file>   one or more landmark files (see above)

Examples:

   Convert the track in some/dir/track.trk to a JSON version of it in some/dir/track.json:

       apq2gpx.pl -j -g some/dir/track.trk

   Convert the track in some/dir/track.trk to a pretty-printed GPX version of it in ./track.gpx:

       apq2gpx.pl -g -g -o ./ ./some/dir/track.trk

   Pretty-print the JSON representation of the waypoint in waypoint.wpt to the screen:

       apq2gpx -j -j -o - waypoint.wpt

   Extract all files in the landmark container file foo.ldk and store as individual .wpt etc. files:

       apq2gpx -b foo.ldk

   Convert all files in the landmark container file foo.ldk and store as individual .gpx. files:

       apq2gpx -g foo.ldk

   Merge data from several files into foobar_merged.json and foobar_merged.gpx files:

       apq2gpx -g -g -j -j - foobar_ -m waypoints.set route1.rte track1.trk track2.trk

Notes:

- Binary data (in JSON) output is base64 encoded.
- Data from earlier or later versions of AlpineQuest may or may not work. YMMV.


