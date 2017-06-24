package ExSite::Time;

#-----------------------------------------------------------------------
#
#   Copyright 2001-2014 Exware Solutions, Inc.  http://www.exware.com
#
#   This file is part of ExSite WebWare (ExSite, for short).
#
#   ExSite is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.
#
#   ExSite is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with ExSite; if not, write to the Free Software
#   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
#   Users requiring warranty coverage and/or support may arrange alternate
#   commercial licensing for ExSite, by contacting Exware Solutions 
#   via the website noted above.
#
#----------------------------------------------------------------------------

=pod

=head1 ExSite::Time 

Utilities for handling dates and times in various formats.

We support the following time formats

    sql_date            yyyy-mm-dd
    sql_datetime        yyyy-mm-dd hh:mm:ss
    iso_date            yyyy-mm-dd
    iso_extended        yyyy-mm-ddThh:mm:ss
    iso_basic           yyyymmddThhmmss
    time                hh:mm AM/PM
    time24              hh:mm (24-hour clock)
    hms                 hh:mm:ss (24-hour clock)
    sql_timestamp       yyyy-mm-dd hh:mm:ss
    unix_timestamp      nnnnnnnnnnn
    date                mmm dd, yyyy
    date_long           Month dd, yyyy
    datetime            wday Mon dd hh:mm yyyy
    datetime_long       Weekday Month dd hh:mm yyyy
    datetime2           hh:mm AM/PM, Month dd, yyyy
    arpa                wday, dd Mon yy hh:mm:ss ZONE
    cookie              Wdy, dd-mmm-yyyy hh:mm:ss GMT
    full                Weekday, Month dd, yyyy at hh:mm AM/PM
    dd-mmm-yy           dd-Mon-yy
    weekday             wday
    weekday_long        Weekday
    year-month          yyyy-mm
    year                yyyy
    month               Mon
    month_long          Month
    raw                 [y,m,d,h,m,s]
    raw_year		yyyy
    raw_month		mm
    raw_day		dd
    raw_hour		hh
    raw_minute		mm
    raw_second		ss
    raw_weekday         nn
    ago                 N UNITS ago

You can also output custom formats using %X format codes such as:
    %YY                 last 2 digits of year
    %YYYY               year
    %M                  numeric month (with no leading zero)
    %MM                 numeric month (with leading zero)
    %MMM                short month name
    %MMMM               long month name
    %D                  numeric day (with no leading zero)
    %DD                 numeric day (with leading zero)
    %H                  hour (24-hour clock, no leading zero)
    %HH                 hour (24-hour clock, with leading zero)
    %h                  hour (12-hour clock, no leading zero)
    %hh                 hour (12-hour clock, with leading zero)
    %m                  minute (no leading zero)
    %mm                 minute (with leading zero)
    %s                  second (no leading zero)
    %ss                 second (with leading zero)
    %WWW                short weekday
    %WWWW               long weekday
    %A                  am/pm
    %ZZZ                time zone (3-letter code, if possible)
    %Z                  time zone (1-letter code)
    %z                  time zone (numeric code)

For example, the format "%m minutes past %h, on %WWWW, %MMMM %D" would
give results like "16 minutes past 8, on Monday, March 7".
Custom formats are not supported for inputting times.

Note that AM/PM indicators are formatted according to C<$config{form}{am}>
and C<$config{form}{pm}>.

Internally, we convert all dates/times to a 6-element time array: y,
m, d, h, m, s.  A 7th element (weekday) may be added in some cases.
The time array is initialized to the current datetime, so if you only
set a partial datetime (eg. only the time), the remaining values are
unchanged, and the full array still represents a complete datetime.

=head2 Usage

Make a time object (initialized to current time):

    my $t = new ExSite::Time;

Make a time object (initialized to some other time/format):

    my $t = new ExSite::Time("2001-12-25 09:00:00","sql_datetime");

Set the time to the current time:

    $t->set;

Set the time to some time/format:

    $t->set('Feb 1, 1968','date');
    $t->set('6:30 pm','time');
    $t->set('Fri Aug 26 12:14:43 2005','datetime');

=head3 Validation

Times can be correctly formatted, but still meaningless or even just
questionable.  For example:

    Feb 30, 2008       # obviously illegal day
    Feb 29, 2000       # not-so-obviously illegal day
    Feb 28, 1008       # strange, but legal, year (typo?)

Time validation can catch these and other cases.  
To validate the date/time value:

    my $error = $t->validate();

The return value, C<$error>, will be set to a message explaining the 
formatting problems, if there are any.  Otherwise, it returns C<undef>.
To validate, date values must fall in the following ranges:

    year    within 100 years of current date (configurable)
    month   1 - 12
    day     1 - number of days in month
    hour    0 - 23
    min     0 - 59
    sec     0 - 59

=head2 Displaying Times

Output the time in some format:

    print $t->write('date');
    print $t->write('unix_timestamp');
    print $t->write('weekday');

C<get_X()> return a formatted subvalue, where X is one of:

    YY                 last 2 digits of year
    YYYY               year
    M                  numeric month (with no leading zero)
    MM                 numeric month (with leading zero)
    MMM                short month name
    MMMM               long month name
    D                  numeric day (with no leading zero)
    DD                 numeric day (with leading zero)
    H                  hour (24-hour clock, no leading zero)
    HH                 hour (24-hour clock, with leading zero)
    h                  hour (12-hour clock, no leading zero)
    hh                 hour (12-hour clock, with leading zero)
    m                  minute (no leading zero)
    mm                 minute (with leading zero)
    s                  second (no leading zero)
    ss                 second (with leading zero)
    WWW                short weekday
    WWWW               long weekday
    A                  am/pm
    ZZZ                time zone (3-character code)
    Z                  time zone (1-character code)
    z                  time zone (numeric code)

=head2 Adjusting Times

To adjust the time by some amount:

    $t->add(30,'days');
    $t->add(-3,'months');

NB: some time units are not precisely defined, so we must approximate.
What we do is define 1 month as 1/12 of a year, and 1 year as 365
days.  These may not give expected results.  For example, adding 1
month will not leave you at the same time of day, nor on the same day
of the following month. (To understand why this is correct, consider
what the date should be if we start from Jan 31, and add 1 month.)

If you want to keep the same time of day or same day of month, insofar
as is possible, use the following call:

    $t->add_approximate(1,"month");

This may adjust times forward or backward to try to keep you at the
expected time of day, or month of year. For instance if you use this
method to add 1 month to Jan 31, you will end up at Feb 28, not March
2.

=head3 Timezones

All times are assumed to be the timezone that the server is configured in, 
unless otherwise declared in the time value. If your time value does not include 
a timezone, and you want to declare one that is not the server timezone, use:

    $t->set_timezone();         # declare native timezone of server
    $t->set_timezone("-0800");  # declare a specific offset from UTC
    $t->set_timezone("H");      # declare a specific 1-letter timezone code
    $t->set_timezone("EST");    # declare a 3-letter timezone code

Note that 3-letter timezone codes are non-standard and unspecific; only a few
North American timezones are recognized, as per RFC 822.

Then you can adjust the timezone (which changes the time and possibly date), 
as follows:

    $t->adjust_timezone("+0100");  # change to a specific offset from UTC
    $t->adjust_timezone("A");      # change to a specific 1-letter timezone code
    $t->adjust_timezone("PST");    # change to a 3-letter timezone code

To change to the "local" time of the website owner, which may be
different from the server timezone, use:

    $t->adjust_localtime();

Note that the server timezone is part of the system configuration by default, eg.:

    timezone.server = -0800

However, this must be manually changed if you want it to be aware of daylight time.
If you want the server to automatically adjust for daylight time, then use:

    timezone.auto = 1

which will autoconfigure the server timezone. If the website owner is
located in a different timezone, you should specify the home timezone 
as an offset to the server timezone (not UTC!), eg.

    timezone.home = +0200  # office is 2 hours ahead of the server timezone

This is so that the home time also adjusts automatically for daylight
time when the server time does so.

=head2 Comparing Times

Compare another time to the currently-set time
(returns 1 if the compared time is in the future, -1 if it is in 
the past, and 0 if it is the same as the current time):

    $t->compare('2005-08-26 09:15:00','sql_timestamp');

If directly comparing two instances of this class, the format string
is not needed:

    $t->compare($t2);

To compare to now, you can also use:

    $t->in_future();
    $t->in_past();

To test if the time falls between two other times, use

    $t->in_date_range( $start_time, $end_time, $format );

Compare two Time instances using operator overloading:

    $t <=> $t2
    $t > $t2
    # etc...

Note that the <=> operator and all other comparison operators only compare
the date portion of an object.  To compare the entire date and time, use
the subtraction operator, eg:

    sort { $a - $b }   # time-sensitive sort
    sort { $a <=> $b } # time-insensitive sort

Convenience call to compare two times in same format:

    $t->compare2('Aug 26, 2005','Aug 28, 2005','datetime');

=head2 Calendars

To get the calendar structure for the month, use

    $t->get_month_calendar();

This returns a 2-D array, C<$month[week][day]>, in which there will be
4 or 5 week rows, and 7 days in each row, corresponding to Sunday .. Saturday --
in other words, a calendar grid for that month. The values in each cell are the
dates (day only) for that cell, with blank cells at the beginning and end for 
padding.

=head2 Internationalization

Month and weekday names are passed through the C<%msg> tool to allow for
translation in multilingual environments.  However, time formats do not 
automatically change based on language preference. To get time format
localization, set the config setting

    report.date.localize = 1

Then the format strings themselves will be run through translation so
that time formats can be altered depending on language.


=cut

# TODO: cannot scan values that are concatenated, like 20110129

use strict;
use ExSite::Config;
use ExSite::Misc;
use ExSite::Base;
use POSIX qw(strftime);
use vars qw(@ISA);
@ISA = qw(ExSite::Base);

# IFP - allow direct comparisons of Time objects
use overload '<=>' => 'compare',
    '>'   => 'gt',
    '<'   => 'lt',
    '=='  => 'eq',
    '>='  => 'ge',
    '<='  => 'le',
    '-'   => 'subtract',
    'bool' => sub { my $this = shift; return defined $this->{time} };

use vars qw(@month_short @month @dayinmonth @weekday_short @weekday 
	    %seconds_in %format);

@month_short = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
@month = qw(January February March April May June July August September October November December);
@dayinmonth = qw(31 28 31 30 31 30 31 31 30 31 30 31);
@weekday_short = qw(Sun Mon Tue Wed Thu Fri Sat);
@weekday = qw(Sunday Monday Tuesday Wednesday Thursday Friday Saturday);
%seconds_in = (
	       year=>(365*24*60*60), 
	       month=>int(30.4375*24*60*60), 
	       week=>(7*24*60*60),
	       day=>(24*60*60), 
	       hour=>(60*60), 
	       minute=>60, 
	       second=>1
	       ); 

%format = (
	   sql_date => "%YYYY-%MM-%DD",
	   sql_datetime => "%YYYY-%MM-%DD %HH:%mm:%ss",
	   iso_date => "%YYYY-%MM-%DD",
	   iso_extended => "%YYYY-%MM-%DDT%HH:%mm:%ss",
	   iso_basic => "%YYYY%MM%DDT%HH%mm%ss",
	   time => "%h:%mm %A",
	   time24 => "%HH:%mm",
	   hms => "%HH:%mm:%ss",
	   date => "%MMM %D, %YYYY",
	   date_long => "%MMMM %D, %YYYY",
	   datetime => "%WWW %MMM %D %H:%mm %YYYY",
	   datetime_long => "%WWWW %MMMM %D %H:%mm %YYYY",
	   full => "%WWWW, %MMMM %D, %YYYY at %h:%mm %A",
	   datetime2 => "%h:%mm %A, %MMMM %D, %YYYY",
	   arpa => "%WWW, %DD %MMM %YYYY %HH:%mm:%ss %ZZZ",
	   cookie => "%WWW, %DD-%MMM-%YYYY %HH:%mm:%ss GMT",
	   'dd-mmm-yy' => "%D-%MMM-%YY",
	   weekday => "%WWW",
	   weekday_long => "%WWWW",
	   year => "%YYYY",
	   month => "%MMM",
	   'year-month' => "%YYYY-%MM",
	   month_long => "%MMMM",
	   month_digit => "%M",
           html_ymd => "<span class='Time'><span class='TimeYear'>%YYYY</span><span class='TimeMonth'>%MMM</span><span class='TimeDay'>%D</span></span>",
	   );

my %timezone = (
    A => "-0100",
    B => "-0200",
    C => "-0300",
    D => "-0400",
    E => "-0500",
    F => "-0600",
    G => "-0700",
    H => "-0800",
    I => "-0900",
    K => "-1000",
    L => "-1100",
    M => "-1200",
    N => "+0100",
    O => "+0200",
    P => "+0300",
    Q => "+0400",
    R => "+0500",
    S => "+0600",
    T => "+0700",
    U => "+0800",
    V => "+0900",
    W => "+1000",
    X => "+1100",
    Y => "+1200",
    Z => "+0000",
    );
my %timezone_alt = (
    UT => "Z",
    GMT => "Z", 
    UTC => "Z",
    AST => "D",
    ADT => "C",
    EST => "E",
    EDT => "D",
    CST => "F",
    CDT => "E",
    MST => "G",
    MDT => "F",
    PST => "H",
    PDT => "G",
    );

# new : create a Time object

sub new {
    my($this, $time, $format) = @_;

    # objectify object
    my $obj = {};
    my $class = ref($this) || $this;
    bless $obj, $class;

    # setup Base class features
    $obj->initialize_object;

    # load time
    $obj->set($time,$format);

    return $obj;
}

# test for unset dates/times

sub defined {
    my $this = shift;
    return $this->defined_date();
    # deprecated:
    foreach my $t (@{$this->{time}}) { return 1 if $t; }
    return 0;
}

sub defined_date {
    my $this = shift;
    foreach (0..2) {
	return 1 if $this->{time}[$_];
    }
    return 0;
}

sub defined_time {
    my $this = shift;
    foreach (3..5) {
	return 1 if $this->{time}[$_];
    }
    return 0;
}

# set : set the current time, using a formatted time string and a format

sub set {
    my ($this,$value,$format) = @_;
    # eval the call to time() in case of a badly formatted value
    my $t = eval { $this->time($value,$format); };
    if ($@) {
	$this->error("ExSite::Time: bad time value ($format): $value [$@]");
	return $this->{time} = undef;
    }
    $this->{time} = $t;
    $this->{weekday} = $this->weekday();
    if (ref $this->{tmp_tz}) {
	$this->{tz} = $this->{tmp_tz};
	$this->{zone} = $this->{tz}[0];
    }
    return $this->{time};
}

sub weekday {
    my ($this,$t) = @_;
    my $weekday;
    $t or $t = $this->{time};
    if ($this->now()->[0] - $t->[0] < 50) {
	# timelocal weekday support is dodgy outside the current century
	use Time::Local;
	if ($t->[1] > 0 && $t->[1] <= 12 && $t->[2] >= 1 && $t->[2] <= 31) {
	    my $t = eval "timelocal($t->[5],$t->[4],$t->[3],$t->[2],$t->[1]-1,$t->[0]-1900);";
	    if (! $@) {
		(undef,undef,undef,undef,undef,undef,$weekday,undef,undef) =
		    localtime($t);
	    }
	}
    }
    return $weekday;
}

# time : convert a formatted time string to a time array

sub time {
    my ($this,$value,$format) = @_;

    # initialize time to current time
    my $t = $this->now;
    my @time = @$t;

    # replace time fields with passed values
    if ($value) {
	my @newtime;
	if (exists $format{$format} || $format =~ /%/) {
	    # the time has a fixed format
	    @newtime = $this->scan($value,$format);
	}
	elsif ($format =~ /^sql_timestamp$/) {
	    # mysql timestamp format depends on version
	    if ($config{timestamp_format} eq "num") {
		@newtime = $this->scan($value,"%YYYY%MM%DD%HH%mm%ss");
	    }
	    else {
		@newtime = $this->scan($value,"%YYYY-%MM-%DD %HH:%mm:%ss");
	    }
	}
	elsif ($format =~ /^unix_timestamp$/) {
	    # unix timestamp is just seconds since the epoch
	    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
		localtime($value);
	    @newtime = ($year+1900,$mon+1,$mday,$hour,$min,$sec);
	    $this->{tmp_weekday} = $wday;
	}
	elsif ($format =~ /^ago$/) {
	    # ago times are relative to now
	    my $t = time;
	    $value =~ /^(\d+) (\w+?)s? ago$/i;
	    my $nunit = $1;
	    my $unit = $2;
	    my $diff = $nunit * $seconds_in{$unit};
	    $t -= $diff;
	    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
		localtime($t);
	    @newtime = ($year+1900,$mon+1,$mday,$hour,$min,$sec);
	    $this->{tmp_weekday} = $wday;
	}
	elsif ($format =~ /^raw/) {
	    $_ = $format;
	    if (/year$/) {
		$newtime[0] = $value;
	    }
	    elsif (/month$/) {
		$newtime[1] = $value;
	    }
	    elsif (/day$/) {
		$newtime[2] = $value;
	    }
	    elsif (/hour$/) {
		$newtime[3] = $value;
	    }
	    elsif (/minute$/) {
		$newtime[4] = $value;
	    }
	    elsif (/second$/) {
		$newtime[5] = $value;
	    }
	    elsif (ref $value eq "ARRAY") {
		@newtime = @$value;
	    }
	}
	elsif ( ref($value) eq ( ref($this) || $this ) ) {
	    # IFP - $value can also be a Time object, in which case a format
	    # string is not necessary.
	    @newtime = @{ $value->{time} };
	}
	# replace time values with values extracted from the time string
	my $i = 0;
	foreach my $t (@newtime) { 
	    if (defined $t) { $time[$i] = $t; }
	    $i++;
	}
    }
    $this->{weekday} = $this->{tmp_weekday};
    # Convert time values to ints, so they don't look like octal strings if
    # they have a leading zero.
    foreach my $t (@time) { $t += 0; }
    # untaint time values
    foreach my $t (@time) { 
	$t =~ /^(\d*)$/;
	$t = $1; 
    }
    return \@time;
}

# scan : parse a time format string containing %X placeholder codes

sub scan {
    my ($this,$value,$format) = @_;
    my $fmt = $format =~ /%/ ? $format : $format{$format};
    my %value;
    my @time;

    # convert the value and format to character arrays

    my @v = split //, $value;
    my @f = split //, $fmt;

    # scan the format string

    while (my $fchar = shift @f) {
	if ($fchar eq "%") {
	    # we have a format code - determine what it is
	    my @fcode;
	    push @fcode, shift @f;
	    # keep adding to the format code while the character is the same
	    while ($f[0] eq $fcode[0]) { 
		push @fcode, shift @f;
	    }
	    # done - join the format chars back into a string
	    my $fcode = join "", @fcode;
	    # extract the next continuous substring off the value
	    my $remainder = join "", @v;
	    $remainder =~ /^(\w+)/;
	    # associated the format code with the substring
	    $value{$fcode} = $1;
	    # remove the substring from the value
	    for (1 .. length $value{$fcode}) { shift @v; }
	}
	else {
	    # non-significant character - ignore
	    shift @v;
	}
    }

    # now we have a hash of format codes => substrings
    # build a time array from the available values

    # year
    if (exists $value{YYYY}) { 
	$time[0] = $value{YYYY}; 
    }
    elsif (exists $value{YY}) { 
	my $y = $value{YY};
	$time[0] = $y > 50 ? $y + 1900 : $y + 2000;
    }
    # month
    if (exists $value{MMMM}) {
	$time[1] = $this->which($value{MMMM},@month);
    }
    elsif (exists $value{MMM}) {
	$time[1] = $this->which($value{MMM},@month_short);
    }
    elsif (exists $value{MM}) {
	$time[1] = $value{MM};
    }
    elsif (exists $value{M}) {
	$time[1] = $value{M};
    }
    # day
    if (exists $value{DD}) {
	$time[2] = $value{DD};
    }
    elsif (exists $value{D}) {
	$time[2] = $value{D};
    }
    # hour
    if (exists $value{HH}) {
	$time[3] = $value{HH};
    }
    elsif (exists $value{H}) {
	$time[3] = $value{H};
    }
    elsif (exists $value{hh} || exists $value{h}) {
	my $h = $value{hh} || $value{h};
	if ($h == 12) { $h = 0; }
	if ($value{A} =~ /p/i) { $h += 12; }  # pm
	$time[3] = $h;
    }
    # minutes
    if (exists $value{mm}) {
	$time[4] = $value{mm};
    }
    elsif (exists $value{m}) {
	$time[4] = $value{m};
    }
    # seconds
    if (exists $value{ss}) {
	$time[5] = $value{ss};
    }
    elsif (exists $value{s}) {
	$time[5] = $value{s};
    }
    # weekday
    if (exists $value{WWWW}) {
	$this->{tmp_weekday} = $this->which($value{WWWW},@weekday);
    }
    elsif (exists $value{WWW}) {
	$this->{tmp_weekday} = $this->which($value{WWW},@weekday_short);
    }
    # timezone
    if (exists $value{Z} || exists $value{ZZZ} || exists $value{z}) {
	$this->{tmp_tz} = [];
	if (exists $value{z}) {
	    $this->{tmp_tz}[0] = $value{z};
	    my %tzr = reverse %timezone;
	    $this->{tmp_tz}[1] = $tzr{$value{z}};
	}
	if (exists $value{Z}) {
	    $this->{tmp_tz}[1] = $value{Z};
	}
	if (exists $value{ZZZ}) {
	    $this->{tmp_tz}[2] = $value{ZZZ};
	}
    }
    return wantarray ? @time : \@time;
}

sub write {
    my $this = shift;
    $_ = shift;     # format
    return undef if (! $this->defined);
    #return "invalid date" if ($this->validate);
    if (exists $format{$_}) {
	return $config{report}{date}{localize} ?
	    $this->write_format($msg{$format{$_}}) : # allows for format localization
	    $this->write_format($format{$_}); 
    }
    elsif (/^sql_timestamp$/) {
	if ($config{timestamp_format} eq "num") {
	    return $this->write_format("%YYYY%MM%DD%HH%mm%ss");
	}
	else {
	    return $this->write_format("%YYYY-%MM-%DD %HH:%mm:%ss");
	}
    }
    elsif (/^unix_timestamp$/) { 
	use Time::Local;
	my @t = @{$this->{time}};
	if ($t[1] >= 1 && $t[1] <= 12 && $t[2] >= 1 && $t[2] <= 31) {
	    if ($this->now()->[0] - $t[0] < 50) {
		return eval { timelocal($this->{time}[5],$this->{time}[4],$this->{time}[3],$this->{time}[2],$this->{time}[1]-1,$this->{time}[0]-1900); }
	    }
	    else {
		# YMMV - timelocal not well defined for dates outside the epoch
		return eval { timelocal($this->{time}[5],$this->{time}[4],$this->{time}[3],$this->{time}[2],$this->{time}[1]-1,$this->{time}[0]); }
	    }
	}
	else {
	    $this->error("bad time value: $@");
	    return -1;
	}
    }
    elsif (/^ago$/) {
	my $now = time;
	my $then = $this->write("unix_timestamp");
	my $diff = $now - $then;
	foreach my $unit (qw(year month week day hour minute second)) {
	    if (abs($diff) > $seconds_in{$unit}) {
		my $nunit = int($diff / $seconds_in{$unit});
		my $u = $nunit == 1 ? $unit : $unit."s";
		return &substitute($msg{"[[n]] $u ago"},{n=>$nunit});
	    }
	}
	return &substitute($msg{"[[n]] seconds ago"},{n=>0});
    }
    elsif (/^raw/) {
	if (/_year$/) {
	    return $this->{time}[0];
	}
	elsif (/_month$/) {
	    return $this->{time}[1];
	}
	elsif (/_day$/) {
	    return $this->{time}[2];
	}
	elsif (/_hour$/) {
	    return $this->{time}[3];
	}
	elsif (/_minute$/) {
	    return $this->{time}[4];
	}
	elsif (/_second$/) {
	    return $this->{time}[5];
	}
	elsif (/_weekday$/) {
	    return $this->{weekday};
	}
	# add wkday, timezone to return array
	return [ @{$this->{time}}, $this->{weekday}, $this->{zone} ];
    }
    elsif (/\%/) {
    	return $this->write_format($_);
    }
    $this->error("Unknown time format: $_");
}

sub write_format {
    my $this = shift;
    my $date = shift; # custom format string
    $date =~ s/\%YYYY/$this->get_YYYY/eg;
    $date =~ s/\%YY/$this->get_YY/eg;
    $date =~ s/\%MMMM/$this->get_MMMM/eg;
    $date =~ s/\%MMM/$this->get_MMM/eg;
    $date =~ s/\%MM/$this->get_MM/eg;
    $date =~ s/\%M/$this->get_M/eg;
    $date =~ s/\%DD/$this->get_DD/eg;
    $date =~ s/\%D/$this->get_D/eg;
    $date =~ s/\%HH/$this->get_HH/eg;
    $date =~ s/\%H/$this->get_H/eg;
    $date =~ s/\%hh/$this->get_hh/eg;
    $date =~ s/\%h/$this->get_h/eg;
    $date =~ s/\%mm/$this->get_mm/eg;
    $date =~ s/\%m/$this->get_m/eg;
    $date =~ s/\%ss/$this->get_ss/eg;
    $date =~ s/\%s/$this->get_s/eg; 
    $date =~ s/\%WWWW/$this->get_WWWW/eg;
    $date =~ s/\%WWW/$this->get_WWW/eg;
    $date =~ s/\%A/$this->get_A/eg;
    $date =~ s/\%ZZZ/$this->get_ZZZ/eg;
    $date =~ s/\%Z/$this->get_Z/eg;
    $date =~ s/\%z/$this->get_z/eg;
    return $date;
}

# validate : see if the object represents a legal date/time

sub validate {
    my ($this,@date) = @_;
    my @err;
    if (ref $this->{time} ne "ARRAY") {
	push @err, $msg{"date is not defined"};
	return @err;
    }
    scalar @date or @date = @{$this->{time}};
    my $y = shift @date;
    my $m = shift @date;
    my $d = shift @date;
    my $now = $this->now();
    if ($y < 1) {
	push @err, $msg{"invalid year"};
    }
    if (abs($y - $now->[0]) > $config{form}{validate_year_range}) {
	# year must be within 100 years of today
	push @err, $msg{"year is out of range"};
    }
    if ($m < 1 || $m > 12) {
	push @err, $msg{"invalid month"};
    }
    if ($d < 1 || $d > 31) {
	push @err, $msg{"invalid day"};
    }
    else {
	# right number of days in month?
	my $dinm = $m > 0 ? $dayinmonth[$m-1] : 0;
	if ($m == 2 &&        # Feb
	    $this->is_leap_year($y)) {
	    # add a day to February for leap years
	    $dinm++;
	}
	if ($m > 0 && $d > $dinm) {
	    push @err, &substitute($msg{"too many days for [[month]]"},{month=>$month[$m-1]});
	}
    }

    my $h = shift @date;
    my $m = shift @date;
    my $s = shift @date;
    if ($h < 0 || $h > 23) {
	push @err, $msg{"invalid hour"};
    }
    if ($m < 0 || $m > 59) {
	push @err, $msg{"invalid minute"};
    }
    if ($s < 0 || $s > 59) {
	push @err, $msg{"invalid seconds"};
    }

    ### validate weekday ??

    return @err == 0 ? undef : join "; ",@err;
}

# now : convert the current time to a time array

sub now {
    my $this = shift;
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = 
	localtime(time);
    $this->{tmp_weekday} = $wday;
    return [$year+1900,$mon+1,$mday,$hour,$min,$sec];
}

# add: add a number of time units (years, months, days, hours, minutes, 
# seconds) to the current time.

sub add {
    my $this = shift;
    my $add_method = $this->{add_method} || $config{time_add_method};
    return $add_method =~ /approx/ ?
	$this->add_approximate(@_) :
	$this->add_exact(@_);
}

# add_exact : adds an absolute amount of time, which is the number of
#             seconds in a time unit, times the number of time units

sub add_exact {
    my ($this,$number,$what) = @_;
    my $t = $this->write("unix_timestamp");
    $what =~ s/s$//i;
    $t += $number * $seconds_in{lc $what};
    return $this->set($t,"unix_timestamp");
}

# add_approximate : add_exact can sometimes leave you at a
# different hour of the day, or a different day of the month than you
# started with, because the following time units are not fixed length:
#   days : can be more or less than 24 hours on daylight savings changes
#   weeks : can be more or less than 192 hours on daylight savings changes
#   months : have variable number of days
#   years : have variable number of days

sub add_approximate {
    my ($this,$number,$what) = @_;
    if ($what =~ /hour|minute|second/) {
	# these time units are fixed
	return $this->add_exact($number,$what);
    }
    elsif ($what =~ /year/) {
	# simply increment the year
	$this->{time}[0] += $number;
	if ($this->{time}[1] == 2 && $this->{time}[2] == 29) {
	    # it's Feb 29; change to Feb 28
	    $this->{time}[3] == 28;
	}
    }
    elsif ($what =~ /month/) {
	# must fix rollovers, rollunders, and invalid day-in-month values
	my $m = $this->{time}[1] + $number;
	if ($m > 12) {
	    # year rollover
	    $this->{time}[0] += int(($m-1) / 12);
	    $this->{time}[1] = ($m % 12) || 12;
	}
	elsif ($m < 1) {
	    # year rollunder
	    while ($m < 1) {
		$this->{time}[0]--;
		$m += 12;
	    }
	    $this->{time}[1] = $m;
	}
	else {
	    $this->{time}[1] = $m;
	}
	if ($this->{time}[2] > $this->days_in_month()) {
	    # invalid day of month; back up to last day of month
	    $this->{time}[2] = $this->days_in_month();
	}
    }
    elsif ($what =~ /week/) {
	# use day logic
	return $this->add_approximate($number*7,"days");
    }
    elsif ($what =~ /day/) {
	# must fix rollovers, rollunders
	$this->{time}[2] += $number;
	if ($number > 0) {
	    # fix month rollover
	    while ($this->{time}[2] > $this->days_in_month()) {
		$this->{time}[2] -= $this->days_in_month();
		$this->{time}[1]++;
		if ($this->{time}[1] > 12) {
		    $this->{time}[0]++;
		    $this->{time}[1] = 1;
		}
	    }
	}
	else {
	    # fix month rollunder
	    while ($this->{time}[2] < 1) {
		my $prev_month = $this->{time}[1]-1;
		if ($prev_month == 0) { $prev_month = 12; }
		$this->{time}[2] += $this->days_in_month($prev_month,$this->{time}[0]);
		$this->{time}[1]--;
		if ($this->{time}[1] < 1) {
		    $this->{time}[0]--;
		    $this->{time}[1] = 12;
		}
	    }
	}
    }
    elsif ($what =~ /week/) {
	return $this->add_approximate($number*7,"days");
    }
    # reset weekday
    $this->{weekday} = $this->weekday();
    return $this->{time};
}

# timezone management

sub timezone {
    my ($this,$zone) = @_;
    $zone or $zone = $config{timezone}{server}; # default to server timezone
    my $tz;
    my @tz; # ( numeric, single-letter, 3-letter )
    # convert timezone to format +/-NNNN
    if ($zone =~ /^[\-\+]\d\d:\d\d$/) {
	$zone =~ s/://;
	@tz = ($zone);
    }
    elsif ($zone !~ /^[\-\+]\d+$/) {
	$zone = uc $zone;
	if ($zone !~ /^[A-Z]$/) {
	    unshift @tz, $zone;
	    $zone = $timezone_alt{$zone};
	}
	unshift @tz, $zone;
	unshift @tz, $timezone{$zone};
    }
    else {
	@tz = ($zone);
    }
    return wantarray ? @tz : $tz[0];
}

sub set_timezone {
    my ($this,$zone) = @_;
    my @tz = $this->timezone($zone);
    $this->{tz} = \@tz;
    $this->{zone} = $tz[0];
}

sub adjust_timezone {
    my ($this,$zone) = @_;
    $zone or $zone = $config{timezone}{server};
    if ($zone && $this->{zone}) {
	# convert to UTC
	my ($sgn,$h,$m) = ($this->{zone} =~ /^([\-\+])(\d\d)(\d\d)$/);
	my $min = $h * 60 + $m;
	if ($sgn eq "+") { $min = -$min; } # go in reverse direction to get to UTC
	$this->add($min,"minutes");

	# set new timezone
	$this->set_timezone($zone);

	# convert to new TZ
	($sgn,$h,$m) = ($this->{zone} =~ /^([\-\+])(\d\d)(\d\d)$/);
	$min = $h * 60 + $m;
	if ($sgn eq "-") { $min = -$min; }
	$this->add($min,"minutes");
    }
}

sub adjust_localtime {
    my $this = shift;
    return if (! $config{timezone}{home}); # nothing to adjust to
    if (! $this->{zone}) {
	$this->set_timezone();
    }
    elsif ($this->{zone} ne $this->timezone($config{timezone}{server})) {
	# adjust back to server time
	$this->adjust_timezone($config{timezone}{server});
    }
    # get current offset from UTC
    my ($sgn1,$h1,$m1) = ($this->{zone} =~ /^([\-\+])(\d\d)(\d\d)$/);
    my $min1 = $h1 * 60 + $m1;
    if ($sgn1 eq "-") { $min1 = -$min1; }
    
    # convert to new TZ
    my ($sgn,$h,$m) = ($config{timezone}{home} =~ /^([\-\+])(\d\d)(\d\d)$/);
    my $min = $h * 60 + $m;
    if ($sgn eq "-") { $min = -$min; }
    $this->add($min,"minutes");

    # calculate effective local TZ
    my $min2 = $min + $min1;
    my $h2 = int($min2 / 60);
    my $sgn2;
    if ($h2 < 0) {
	$sgn2 = '-';
	$h2 = -$h2;
    }
    else {
	$sgn2 = '+';
    }
    my $m2 = $sgn2 eq "-" ? $min2 + $h2 * 60 : $min2 - $h2 * 60;
    $this->{zone} = $sgn2 . sprintf('%02d',$h2) . sprintf('%02d',$m2);
}

# show_date_range : display two dates representing a range 
# as a single string (one format only, due to number of possible 
# variations). 
#
# The $contiguous flag should be true if the event
# spans ALL times between the beginning and the end; false if the
# event has multiple discrete periods between the beginning and the
# end. This may affect how times are displayed. For example:
# an event that runs 10pm - 2am starting on Mar 1 will display like:
# 10:00 PM March 1 - 2:00 AM March 2, 2012 (contiguous time)
# whereas an event that runs 8-9 pm, on both Mar 1 & 2 will display like:
# March 1-2, 2012 (discontiguous time)

sub show_date_range {
    my ($this,$enddate,$format,$contiguous) = @_;
    my $start = $this;
    defined $contiguous or $contiguous = 1; # assume contiguous
    my $end = ((ref $enddate) =~ /ExSite::Time/) ? 
	$enddate : 
	new ExSite::Time($enddate,$format); # defaults to now
    my $diff = $this->diff($end);
    if ($diff < 0) {
	# end before start !? reverse
	$start = $end;
	$end = $this;
    }
    elsif ($diff < 60) {
	# same (to the nearest minute), no range to report
	return $this->has_time ? 
	    $this->write("%h:%mm %A %MMMM %D, %YYYY") : 
	    $this->write("date_long");
    }

    if ($start->write("sql_date") ne $end->write("sql_date")) {
	# different days
	my $sty = $start->get_YYYY;
	my $endy = $end->get_YYYY;
	if ($start->has_time || $end->has_time) {
	    # time is significant
	    if ($contiguous) {
		# single time period, show complete dates with times
		my $endstr = $end->write("%h:%mm %A %MMM %D, %YYYY");
		my $startstr = ($sty == $endy) ?
		    $start->write("%h:%mm %A %MMM %D") : # don't show same yr twice
		    $start->write("%h:%mm %A %MMM %D, %YYYY");
		return "$startstr - $endstr";
	    }
	    else {
		# multiple time periods, only show dates
		my $endstr = $end->write("%MMM %D, %YYYY");
		my $startstr = ($sty == $endy) ?
		    $start->write("%MMM %D") : # don't show same yr twice
		    $start->write("%MMM %D, %YYYY");
		return "$startstr - $endstr";
	    }
	}
	elsif ($sty != $endy || $start->get_M != $end->get_M) {
	    # different months
 	    return ($sty == $endy) ?
		$start->write("%MMMM %D") . " - " . $end->write("date_long") :
		$start->write("date_long") . " - " . $end->write("date_long");
 	}
 	elsif ($start->get_D != $end->get_D) {
	    # different days in same month
 	    return $start->write("month_long") . " " . 
		$start->write("raw_day") . " - " . 
		$end->write("raw_day") . ", " . 
		$start->write("year");
 	}
    }
    else {
	# same day 
        my $out = $start->write("date_long") . ", ";
	my $a1 = $start->get_A;
	my $a2 = $end->get_A;
	if ($start->get_A eq $end->get_A) {
	    $out .= $start->write("%h:%mm") . " - " . $end->write("%h:%mm") . " $a1";
	}
	else {
	    $out .= $start->write("time") . " - " . $end->write("time");
	}
	return $out;
    }
}

# compare : return -1, 0, +1 if passed date is past, present, or future 
# with respect to the current date

sub compare {
    my ($this, $date, $fmt) = @_;
    my $now = $date ? $this->time($date,$fmt) : $this->now;
    my $then = $this->{time};
   
    return 1 if ($now->[0] > $then->[0]);
    return -1 if ($now->[0] < $then->[0]);
	       
    return 1 if ($now->[1] > $then->[1]);
    return -1 if ($now->[1] < $then->[1]);
	       
    return 1 if ($now->[2] > $then->[2]);
    return -1 if ($now->[2] < $then->[2]);

    return 0;
}

sub compare2 {
    my ($this, $date1, $date2, $fmt) = @_;
    $this->set($date2,$fmt);
    return $this->compare($date1,$fmt);
}

# in_date_range: compare with 2 dates; returns true if our date/time
# falls between the two.

sub in_date_range {
    my ($this, $date1, $date2, $fmt) = @_;
    return 
	$this->compare($date1,$fmt) <= 0 &&
	$this->compare($date2,$fmt) >= 0;
}

sub in_future {
    my $this = shift;
    my $now = new ExSite::Time();
    return $this->compare($now) < 0;
}

sub in_past {
    my $this = shift;
    my $now = new ExSite::Time();
    return $this->compare($now) > 0;
}

# IFP
# Wrapper methods around compare() for various types of comparisons. 
# These also implement the overloaded comparison operators, in which case:
#	a) both parameters must be instances of this class; and 
#	b) the $fmt parameter is undef.
#
# Note that the order of operands in compare() and diff() are the reverse
# of what you'd expect when using operators, so the comparisons in these
# methods are the reverse of what you'd expect, and the subtract()
# function is necessary to flip the operands around.
sub gt {
	my ($this, $that, $fmt) = @_;
	return ( $this->compare($that, $fmt) < 0 );
}
sub lt {
	my ($this, $that, $fmt) = @_;
	return ( $this->compare($that, $fmt) > 0 );
}
sub eq {
	my ($this, $that, $fmt) = @_;
	return ( $this->compare($that, $fmt) == 0 );
}
sub ge {
	my ($this, $that, $fmt) = @_;
	return ( $this->compare($that, $fmt) <= 0 );
}
sub le {
	my ($this, $that, $fmt) = @_;
	return ( $this->compare($that, $fmt) >= 0 );
}
sub subtract {
	my ($this, $that, $fmt) = @_;
	# Make sure that $that is a Time object.
	$that = new ExSite::Time($that, $fmt);  
	return $that->diff($this);
}

# diff: return the difference between the passed date and the internal date
# +ve differences indicate the passed date is in the future; -ve indicates
# the passed date is in the past.  The difference returned is in seconds.

sub diff {
    my ($this, $date, $fmt) = @_;
    my $s1 = $this->write("unix_timestamp");
    my $time = ((ref $date) =~ /ExSite::Time/) ? 
	$date : 
	new ExSite::Time($date,$fmt);
    if ($time->defined) {
	my $s2 = $time->write("unix_timestamp");
	return $s2 - $s1;
    }
    return undef;
}

# diffdays: like diff, but in days. Accounts for daylight savings
# switches which can result in 23- and 25-hour days in some cases.

sub diffdays {
    my ($this, $date, $fmt) = @_;
    my $s1 = $this->write("unix_timestamp");
    my $time = ((ref $date) =~ /ExSite::Time/) ? 
	$date : 
	new ExSite::Time($date,$fmt);
    if ($time->defined) {
	my $s2 = $time->write("unix_timestamp");
	my $diff = $s2 - $s1;
	my $diffdays = $diff / 86400;
	my $idiffdays = int($diffdays);
	my $residual = $diffdays - $idiffdays;
	if ($residual > 0.95) { $idiffdays++; }
	elsif ($residual < -0.95) { $idiffdays--; }
	return $idiffdays;
    }
    return undef;
}

# which : finds a named time value (eg. month, weekday) in an array
# and returns the array location plus 1.

sub which {
    my ($this,$val,@list) = @_;
    my $i = 0;
    foreach my $item (@list) {
	$i++;
	return $i if ($val =~ /^$item$/i);
    }
    return 0;
}

# get_X : return formatted sub-values
#
# X is one of:
#
#    YY                 last 2 digits of year
#    YYYY               year
#    M                  numeric month (with no leading zero)
#    MM                 numeric month (with leading zero)
#    MMM                short month name
#    MMMM               long month name
#    D                  numeric day (with no leading zero)
#    DD                 numeric day (with leading zero)
#    H                  hour (24-hour clock, no leading zero)
#    HH                 hour (24-hour clock, with leading zero)
#    h                  hour (12-hour clock, no leading zero)
#    hh                 hour (12-hour clock, with leading zero)
#    m                  minute (no leading zero)
#    mm                 minute (with leading zero)
#    s                  second (no leading zero)
#    ss                 second (with leading zero)
#    WWW                short weekday
#    WWWW               long weekday
#    A                  am/pm
#    ZZZ                time zone (3-character code preferred)
#    Z                  time zone (1-character code preferred)
#    z                  time zone numeric code

sub get_YY {
    my $this = shift;
    return $this->{time}[0] % 100;
}
sub get_YYYY {
    my $this = shift;
    return $this->{time}[0];
}
sub get_M {
    my $this = shift;
    return $this->{time}[1];
}
sub get_MM {
    my $this = shift;
    return sprintf "%02d",$this->{time}[1];
}
sub get_MMM {
    my $this = shift;
    return $msg{$month_short[$this->{time}[1] - 1]};
}
sub get_MMMM {
    my $this = shift;
    return $msg{$month[$this->{time}[1] - 1]};
}
sub get_D {
    my $this = shift;
    return $this->{time}[2];
}
sub get_DD {
    my $this = shift;
    return sprintf "%02d",$this->{time}[2];
}
sub get_H {
    my $this = shift;
    return $this->{time}[3];
}
sub get_HH {
    my $this = shift;
    return sprintf "%02d",$this->{time}[3];
}
sub get_h {
    my $this = shift;
    my $h = $this->{time}[3] % 12;
    return $h == 0 ? 12 : $h;
}
sub get_hh {
    my $this = shift;
    return sprintf "%02d", $this->{time}[3] % 12 + 1;
}
sub get_m {
    my $this = shift;
    return $this->{time}[4];
}
sub get_mm {
    my $this = shift;
    return sprintf "%02d", $this->{time}[4];
}
sub get_s {
    my $this = shift;
    return $this->{time}[5];
}
sub get_ss {
    my $this = shift;
    return sprintf "%02d", $this->{time}[5];
}
sub get_WWW {
    my $this = shift;
    return $msg{$weekday_short[$this->{weekday}]};
}
sub get_WWWW {
    my $this = shift;
    return $msg{$weekday[$this->{weekday}]};
}
sub get_A {
    my $this = shift;
    return $this->{time}[3] < 12 ? $config{form}{am} : $config{form}{pm};
}
sub get_ZZZ {
    my $this = shift;
    $this->set_timezone() if (! $this->{zone});
    return $this->{tz}[2] || $this->{tz}[1] || $this->{tz}[0];
}
sub get_Z {
    my $this = shift;
    $this->set_timezone() if (! $this->{zone});
    return $this->{tz}[1] || $this->{tz}[0];
}
sub get_z {
    my $this = shift;
    $this->set_timezone() if (! $this->{zone});
    return $this->{zone};
}

# some tests to see how complete this time value is

sub has_date {
    my $this = shift;
    return $this->{time}[0] && $this->{time}[1] && $this->{time}[2];
}

# has time returns true if the time has been set to anything 
# other than 00:00:00

sub has_time {
    my $this = shift;
    return $this->{time}[3] || $this->{time}[4] || $this->{time}[5];
}

sub has_weekday {
    my $this = shift;
    return $this->{weekday};
}

sub has_timezone {
    my $this = shift;
    return $this->{zone};
}

sub is_leap_year {
    my ($this,$y) = @_;
    $y or $y = $this->{time}[0];
    return ($y % 4 == 0 &&                      # years divisible by 4 
	    ($y % 100 != 0 || $y % 400 == 0));  # century exceptions
}

sub days_in_month {
    my ($this,$m,$y) = @_;
    $m or $m = $this->{time}[1];
    $y or $y = $this->{time}[0];
    return ($m == 2 && $this->is_leap_year($y)) ?
	    $dayinmonth[$m-1] + 1 : 
	    $dayinmonth[$m-1];
}

# get_month_calendar: returns a 2-D array, representing the month/week grid, eg.
# 
#           1  2  3  4  
#  5  6  7  8  9 10 11  
# 12 13 14 15 16 17 18  
# 19 20 21 22 23 24 25  
# 26 27 28 29 30 31     

sub get_month_calendar {
    my $this = shift;
    my @week;
    my $days = [];

    my $year = $this->{time}[0];
    my $month = $this->{time}[1];
    my $first_wday;
    if ($this->{time}[2] == 1) {
	$first_wday = $this->{weekday};
    }
    else {
	my $first = new ExSite::Time([$year,$month,1],"raw");
	$first_wday = $first->{weekday};
    }
    if ($first_wday < 0) { $first_wday += 7; }
    my $weekday = 0;
    my $dayinmonth = $this->days_in_month();

    # pad first week with empty days
    foreach (0 .. $first_wday-1) {
	push @$days, undef;
	$weekday++;
    }

    # fill up calendar matrix with actual days
    foreach my $d (1 .. $dayinmonth) {
	if ($weekday == 7) {
	    push @week,$days;
	    $days = [];
	    $weekday = 0;
	}
	push @$days, $d;
	$weekday++;
    }

    # pad last week of month with empty days
    if ($weekday != 7) { 
	foreach my $d ($weekday+1 .. 7) { 
	    push @$days, undef;
	}
    }
    push @week, $days;

    return wantarray ? @week : \@week;
}

1;
