#---------------------------------------------------------
# $Id$

=head1 NAME

Bio::Matrix::PSM::IO - PSM parser

=head1 SYNOPSIS

  use Bio::Matrix::PSM::IO;

  my $psmIO= new Bio::Matrix::PSM::IO(-file=>$file, -format=>'transfac');

  my $release=$psmIO->release; #Using Bio::Matrix::PSM::PsmHeader methods

  my $release=$psmIO->release;

  while (my $psm=$psmIO->next_psm) {
   my %psm_header=$psm->header;
   my $ic=$psm_header{IC};
   my $sites=$psm_header{sites};
   my $width=$psm_header{width};
   my $score=$psm_header{e_val};
   my $IUPAC=$psm->IUPAC;
  }

  my $instances=$psm->instances;
  foreach my $instance (@{$instances}) {
    my $id=$instance->primary_id;
  }


=head1 DESCRIPTION

This module allows you to read DNA position scoring matrices and/or
their respective sequence matches from a file.

There are two header methods, one belonging to
Bio::Matrix::PSM::IO::driver and the other to
Bio::Matrix::PSM::Psm. They provide general information about the file
(driver) and for the current PSM result (Psm) respectively. Psm header
method always returns the same thing, but some values in the hash
might be empty, depending on the file you are parsing. You will get
undef in this case (no exceptions are thrown).

Please note that the file header data (commenatries, version, input
data, configuration, etc.)  might be obtained through
Bio::Matrix::PSM::PsmHeader methods. Some methods are driver specific
(meme, transfac, etc.): meme: weight mast: seq, instances

If called when you parse a different file type you will get undef. For
example:

my $psmIO= new Bio::Matrix::PSM::IO(file=>$file, format=>'transfac');
my %seq=$psmIO->seq;

will return an empty hash. To see all methods and how to use them go
to Bio::Matrix::PSM::PsmHeaderI.

See also Bio::Matrix::PSM::PsmI for details on using and manipulating
the parsed data.

=head1 FEEDBACK

=head2 Mailing Lists

User feedback is an integral part of the evolution of this
and other Bioperl modules. Send your comments and suggestions preferably
 to one of the Bioperl mailing lists.
Your participation is much appreciated.

  bioperl-l@bioperl.org                 - General discussion
  http://bio.perl.org/MailList.html             - About the mailing lists

=head2 Reporting Bugs

Report bugs to the Bioperl bug tracking system to help us keep track
 the bugs and their resolution.
 Bug reports can be submitted via email or the web:

  bioperl-bugs@bio.perl.org
  http://bugzilla.bioperl.org/

=head1 AUTHOR - Stefan Kirov

Email skirov@utk.edu

=head1 APPENDIX

=head1 See also
Bio::Matrix::PSM::PsmI, Bio::Matrix::PSM::PsmHeaderI
=cut


# Let the code begin...
package Bio::Matrix::PSM::IO;
use Bio::Root::Root;
use Bio::Root::IO;
use vars qw(@ISA);
use strict;

@ISA=qw( Bio::Root::IO);

@Bio::Matrix::PSM::IO::PSMFORMATS=qw(meme transfac mast);

=head2 new

 Title   : new
 Usage   : my $psmIO =  new Bio::Matrix::PSM::IO(-format=>'meme', 
						 -file=>$file);
 Function: Associates a file with the appropriate parser
 Throws  : Throws if the file passed is in HTML format or 
           if some criteria for the file
           format are not met. See L<Bio::Matrix::PSM::IO::meme> and 
           L<Bio::Matrix::PSM::IO::transfac> for more details.
 Example :
 Returns : psm object, associated with a file with matrix file
 Args    : hash

=cut

sub new {
    my($caller,@args) = @_;
    my $class = ref($caller) || $caller;
    my $self;
    # or do we want to call SUPER on an object if $caller is an
    # object?
    if( $class =~ /Bio::Matrix::PSM::IO(\S+)/ ) {
	$self = $class->SUPER::new(@args);
	$self->_initialize(@args);
	return $self;
    } else {
	my %param = @args;
	@param{ map { lc $_ } keys %param } = values %param; # lowercase keys
	my $format = $param{'-format'} ||
	    $class->_guess_format( $param{'-file'} || $ARGV[0] ) ||
	    'scoring';
	$self->throw("$format format unrecognized or an argument error occured\n.") if (!grep(/$format/,@Bio::Matrix::PSM::IO::PSMFORMATS));
	$format = "\L$format"; # normalize capitalization to lower case

	# normalize capitalization
	return undef unless( $class->_load_format_module($format) );
	return "Bio::Matrix::PSM::IO::$format"->new(@args);
    }
}

=head2 fh

 Title   : fh
 Usage   : $obj->fh
 Function: Get a filehandle type access to the matrix parser
 Example : $fh = $obj->fh;      # make a tied filehandle
           $matrix = <$fh>;     # read a matrix object
 Returns : filehandle tied to Bio::Matrix::PSM::IO class
 Args    : none

=cut

sub fh {
    my $self = shift;
    my $class = ref($self) || $self;
    my $s = Symbol::gensym;
    tie $$s,$class,$self;
    return $s;
}


=head2 _load_format_module

 Title   : _load_format_module
 Usage   : *INTERNAL Matrix::PSM::IO stuff*
 Function: Loads up (like use) a module at run time on demand

=cut

sub _load_format_module {
  my ($self,$format) = @_;
  my $module = "Bio::Matrix::PSM::IO::" . $format;
  my $ok;

  eval {
      $ok = $self->_load_module($module);
  };
  if ( $@ ) {
    print STDERR <<END;
$self: $format cannot be found
Exception $@
For more information about the Matrix::PSM::IO system please see the
Matrix::PSM::IO docs.  This includes ways of checking for formats at
compile time, not run time
END
  ;
  }
  return $ok;
}


=head2 _guess_format

 Title   : _guess_format
 Usage   : $obj->_guess_format($filename)
 Returns : guessed format of filename (lower case)
 Args    : filename

=cut

sub _guess_format {
    my $class = shift;
    return unless $_ = shift;
    return 'meme'   if /.meme$|meme.html$/i;
    return 'transfac'   if /\.dat$/i;
    return 'mast'   if /^mast\.|\.mast.html$|.mast$/i;
}

=head2 next_psm

 Title   : next_psm
 Usage   : my $psm=$psmIO->next_psm();
 Function: Reads the next PSM from the input file, associated with this object
 Throws  : Throws if there ara format violations in the input file (checking is not
            very strict with all drivers).
 Example :
 Returns : Bio::Matrix::PSM::Psm object
 Args    : none

=cut

sub next_psm {
    my $self = shift;
    $self->throw_not_implemented();
}

=head2 _parseMatrix

 Title   : _parseMatrix
 Usage   :
 Function: Parses the next site matrix information in the meme file
 Throws  :
 Example :  Internal stuff
 Returns :  hash as for constructing a SiteMatrix object (see SiteMatrixI)
 Args    :  string

=cut

sub _parseMatrix {
    my $self = shift;
    $self->throw_not_implemented();
}

=head2 _parseInstance

 Title   : _parseInstance
 Usage   :
 Function: Parses the next sites instances from the meme file
 Throws  :
 Example : Internal stuff
 Returns : Bio::Matrix::PSM::SiteMatrix object
 Args    : array references

=cut

sub _parseInstance {
    my $self = shift;
    $self->throw_not_implemented();
}

=head2 _parse_coordinates

 Title   : _parse_coordinates
 Usage   :
 Function:
 Throws  :
 Example : Internal stuff
 Returns :
 Args    :

=cut

sub _parse_coordinates {
    my $self = shift;
    $self->throw_not_implemented();
}

=head2 header

 Title   : header
 Usage   :  my %header=$psmIO->header;
 Function:  Returns the header for the PSM file, format specific
 Throws  :
 Example :
 Returns :  Hash or a single string with driver specific information
 Args    :  none

=cut

sub header {
    my $self = shift;
    $self->throw_not_implemented();
}

=head2 _make_matrix

 Title   : _make_matrix
 Usage   :
 Function: makes a matrix from 4 array references (A C G T)
 Throws  :
 Example :
 Returns : SiteMatrix object
 Args    : array of references(A C G T)

=cut

sub _make_matrix {
    my $self = shift;
    $self->throw_not_implemented();
}


sub DESTROY {
    my $self = shift;
    $self->close();
}

1;

