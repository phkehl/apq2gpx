# flipflip's AlpineQuest Landmark Files to GPX Converter (apq2gpx)

## Introduction

This tools reads AlpineQuest for Android (https://www.alpinequest.net/) landmark
files and converts them to JSON or GPX format. Landmark files are waypoints
("WPT"), sets of waypoints ("SET"), routes ("RTE"), areas ("ARE"), tracks or
paths ("TRK") and landmark file containers ("LDK").

This works with files generated by AlpineQuest version 2.0.6. Note that this may
or may not work with files from older or newer versions of the app. YMMV.

## Installation

The tool and its documentation is contained in one single file:
`apq2gpx.pl`. This is all you need.

It is a Perl (https://www.perl.org/) script. It uses the following non-core
modules: `Geo::Gpx`, `XML::LibXML`, `MIME::Base64`.

To install these on Debian or Ubuntu Linux systems use:

```
sudo apt install libgeo-gpx-perl libxml-libxml-perl libmime-base64-perl
```

On Windoze with Strawberry Perl (http://strawberryperl.com/) install using:

```
cpanm Geo::Gpx XML::LibXML MIME::Base64
```

See https://www.perl.org/get.html on how to install Perl and consult
http://www.cpan.org/modules/INSTALL.html for more information on installing
additional packages to Perl.

## Usage

Say:

```
./apq2gpx.pl -h
```

or if that doesn't work:

```
perl apq2gpx.pl -h
```

Happy hacking!

## See also

- https://github.com/jachetto/alp2gpx

