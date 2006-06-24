package SIL::Shoe::Backend::openoffice;
use OpenOffice::OODoc;

use encoding "utf8", STDERR => "utf8";

sub new
{
    # perhaps need to open an output file here?
    # also may need configuration for css
    my ($class, $outfile, $css, $props) = @_;
    my ($self) = {};
    my ($doc,$varstyle,$filename,$suffix);


    $self->{'props'} = $props;

	print STDERR "\nnew" if ($self->{'props'}{'debug'});
	print STDERR "\n   class: $class" if ($self->{'props'}{'debug'});
	print STDERR "\n   outfile: $outfile" if ($self->{'props'}{'debug'});
	print STDERR "\n   css: $css" if ($self->{'props'}{'debug'});

	if ( $self->{'props'}{'debug'} ) {
		print STDERR "\n   props: ";
		for $k (keys %{$props}) {
			print STDERR "\n        $k:  $props->{$k}";
		}
	}

	if ($props->{'variable_styles'}) {
		foreach $varstyle ( split(',',$props->{'variable_styles'}) ) {
			$self->{'variable_styles'}{$varstyle} = 1;
		}
	}


	# split up the input filename:
	if ($outfile) {
		if ($outfile =~ /^(.*)\.([^.]{0,4})$/ ) { 
			$filename = $1;
			$suffix = $2;
		} else {
			$filename = $outfile;
		}
		$suffix = "odt" if (not $suffix) ;
		$self->{'filename'} = $filename;
		$self->{'suffix'} = $suffix;
	} else {
    	die "Openoffice file name is required.\n"; 
	}

	if (not $self->{'props'}{'split_files'}) {
		$self->{'doc'} = open_document($outfile.".".$suffix);
	}

	if ($css) {
		$self->{'css'} = open_document($css);

	}

	print STDERR "\n/new" if ($self->{'props'}{'debug'});
    return bless $self, $class;
}

sub open_document
{
	my ($outfile) = @_;
	my ($doc);

    if ($outfile) {
    	if (-f $outfile) {
    		$doc = ooDocument( file => $outfile, local_encoding => '' )
			|| die "Can't open $outfile";
		} else {
    		$doc = ooDocument( file => $outfile, create => 'text' ,local_encoding => '' )
			|| die "Can't open $outfile";
		}
	}

	if (not $doc) {
		die "Could not open File $outfile\n";
	}

	return $doc;

}



sub start_section
{
    my ($self, $type, $name) = @_;
	my ($doc, $first, $last, $node, $nextnode, $sec_name);


	print STDERR "\nstart_section type: $type name: $name" if ($self->{'props'}{'debug'});

	$bookmark=$type . "_" . $name;
	print STDERR "\n  Bookmark name is : $bookmark" if ($self->{'props'}{'debug'});

	if ($self->{'props'}{'split_files'}) {
		$self->{'doc'} = open_document($self->{'filename'} . "-" . $bookmark . "." . $self->{'suffix'});
	}

	$doc = $self->{'doc'};

	# this is a really messy way of finding the highest level section or paragraph bounding the bookmarked area.
	# and ancestor:: selects ALL the ancestors, not just the highest one.  I don't know enough about xpath
	# to figure out exactly what to do here.  It seems sometimes we have text:p/text:section/text:p/text:bookmark
	# so I may not be getting the top one, which is the one I want.

	$first = $doc->getElement("//text:bookmark-start[\@text:name=\"$bookmark\"]/ancestor::text:section",0);
	if (not $first) {$first = $doc->getElement("//text:bookmark-start[\@text:name=\"$bookmark\"]/ancestor::text:p",0);}
	if (not $first) {$first = $doc->getElement("//text:bookmark[\@text:name=\"$bookmark\"]/ancestor::text:p",0);}
	if (not $first) {$first = $doc->getElement("//text:bookmark[\@text:name=\"$bookmark\"]/ancestor::text:section",0);}

	$last = $doc->getElement("//text:bookmark-end[\@text:name=\"$bookmark\"]/ancestor::text:section",0);
	if (not $last) {$last = $doc->getElement("//text:bookmark-end[\@text:name=\"$bookmark\"]/ancestor::text:p",0);}
	# if there is not last, treat it as if they are the same.  This will keep them from deleting.
	if (not $last) {$last = $first};

	if ($first) {
		#if last == first then keep it for now.
		if ($last ne $first) {
			for ($node=$first->{'next_sibling'}; $node ne $last; ) {
				$nextnode = $node->{'next_sibling'};
				print STDERR "\n  deleting node " . $node if ($self->{'props'}{'debug'} > 1);
				$doc->removeElement($node);
				$node = $nextnode;
			}
			$doc-> removeElement($last);
		}
	} else {
		# if the bookmark does not exist, append to the end of the document;
		print STDERR "\nappending paragraph" if ($self->{'props'}{'debug'});
		$first = $doc->appendParagraph(text => "APPENDED PARAGRAPH");
	}
	
	$sec_name = "section_".$bookmark;
	$self->{'styles'}->{$sec_name} = 'section';
	$self->{'sec_name'} = $sec_name;

	# keep first around as a starting point to insert the XML
	$self->{'first'} = $first;
	$self->{'cur'} = $first;
	$self->{'xml'} = '';
	$self->{'curr_bookmark'} = $bookmark;
	$self->{'secnum'} = 0;
	# setting the first node for bookmarking
	$self->{'first_node'} = 1;

	print STDERR "\n/start_section" if ($self->{'props'}{'debug'});

}

sub end_section
{
    my ($self, $type, $name) = @_;
	
	print STDERR "\nend_section type: $type name: $name" if ($self->{'props'}{'debug'});

	if ($self->{'curr_para'})
	{
		$self->{'xml'} .= "<text:bookmark-end text:name='" . $self->{'curr_bookmark'} . "' />";
	}

	$self->outputXML('close_section');

	$self->{'cur'} = '';

	$self->{'doc'}->removeElement($self->{'first'});

	if ($self->{'props'}{'split_files'}) {
		$self->close_document();
	}
	
	print STDERR "\n/end_section" if ($self->{'props'}{'debug'});
}

sub start_letter
{
    my ($self) = @_;

	print STDERR "\nstart_letter" if ($self->{'props'}{'debug'} > 1);

	$self->outputXML('close_section');

	print STDERR "\n/start_letter" if ($self->{'props'}{'debug'} > 1);

}

sub end_letter
{

	my ($self) = @_;
	my ($secnum);

	print STDERR "\nend_letter" if ($self->{'props'}{'debug'} > 1);

	$self->outputXML();

	$secnum = $self->{'secnum'}++;
	$self->{'xml'} .= "<text:section text:name='". $self->{'sec_name'} ."_" . $secnum . "' text:style-name='" . $self->{'sec_name'} . "' >";

	$self->{'curr_sect'} = 1;

	print STDERR "\n/end_letter" if ($self->{'props'}{'debug'} > 1);
}


sub new_para
{
    my ($self, $type) = @_;
	print STDERR "\new_para" if ($self->{'props'}{'debug'} > 1);
    
	$self->{'styles'}->{$type} = 'paragraph';

	$self->outputXML();

	$self->{'xml'} .= "<text:p text:style-name='$type' >";

	if ($self->{'first_node'}) {
		$self->{'xml'} .= "<text:bookmark-start text:name='" . $self->{'curr_bookmark'} . "' />";
		$self->{'first_node'} = 0;
	}

	$self->{'curr_para'} = 1;
	$self->{'start_para'} = 1;

	print STDERR "\n/new_para" if ($self->{'props'}{'debug'} > 1);
}

sub output_tab
{
    my ($self) = @_;
	$self->{'xml'} .= "<text:tab />" unless ($self->{'start_para'});
	print STDERR "\noutput_tab" if ($self->{'props'}{'debug'} > 1);
}

sub output_space
{    
    my ($self) = @_;
    
	$self->{'xml'} .= '<text:s text:c="1"/>' unless ($self->{'start_para'});
	print STDERR "\noutput_space" if ($self->{'props'}{'debug'} > 1);
}

sub output
{
    my ($self, $text) = @_;
    
	$self->{'xml'} .= xmlescape($text);
    $self->{'start_para'} = 0;

	print STDERR "\noutput" if ($self->{'props'}{'debug'} > 1);

}

sub char_style
{
    my ($self, $style, $text) = @_;
    
	$self->{'styles'}->{$style} = 'text';

	$self->{'xml'} .= "<text:span text:style-name='$style'>";

	if ($self->{'variable_styles'}{$style}) {
		$self->{'xml'} .= "<text:variable-set text:name='$style' office:value-type='string'>";
	}

	$self ->{'xml'} .= xmlescape($text);

	if ($self->{'variable_styles'}{$style}) {
		$self->{'xml'} .= "</text:variable-set>";
	}
	
	
	$self ->{'xml'} .= "</text:span>";

    $self->{'start_para'} = 0;

	print STDERR "\nchar_style" if ($self->{'props'}{'debug'} > 1);
}

sub finish
{
    my ($self) = @_;

	print STDERR "\nfinish" if ($self->{'props'}{'debug'});

	if (not $self->{'props'}{'split_files'}) {
		$self->close_document();
	}

	print STDERR "\n/finish\n" if ($self->{'props'}{'debug'});
}

sub get_csssection_style
{
	my ($self,$style) = @_;
	my ($css,$sec,$sse);
	#find a section with the right name
	#find that section's style
	#pull that sections's style
	#change its name

	$css = $self->{'css'};
	return "" if not ($css);

	$ss = $css->sectionStyle($style);
	return "" if not ($ss);

	$sse = $css->getStyleElement($ss);

	$css->styleName($sse,$style);
	return $css->exportXMLElement($sse);
}

sub close_document
{
    my ($self) = @_;
	my ($doc,$styles,$docstyle,$element,$stylexml);
	print STDERR "\nclose_document" if ($self->{'props'}{'debug'});

	$doc = $self->{'doc'};
	$styles = $self->{'styles'};
	$docstyle = ooStyles( file => $doc );

	foreach $style (keys %$styles) {
		print STDERR "\n  looking at style ". $style . " type " . $styles->{$style}  if ($self->{'props'}{'debug'});
		if ($styles->{$style} eq "section") {
			#automatic style in content.xml, so use $doc and not $docstyle.

			# FIRST if $css is used, look in that file for a section by the style name.
			# If not, add a default one.  Otherwise take one from the $css document.
			$stylexml = $self->get_csssection_style($style);

				# if stylxml then remove all existing styles. then use it
				# if not, then if existing style, use it
				# if not that, then create default style

			if ($stylexml ne "" ) {
				@conflictstyles = $doc->selectStyleElementsByName($style, family => 'section');
				for $s (@conflictstyles) {
					$doc->removeElement($s);
				}
				$element = $doc->createStyle($style, family => 'section');
				print STDERR "\n    using external style: $style" if ($self->{'props'}{'debug'});
				$doc->replaceElement($element,$doc->createElement($stylexml));
			}  else {

				$element = $doc->getStyleElement($style, family => 'section');
			
				if (not $element) {
					$element = $doc->createStyle($style, family => 'section');
					$stylexml = '<style:style style:name="'. $style .'" style:family="section">'.
						 '<style:section-properties text:dont-balance-text-columns="false" style:editable="false">'.
						  '<style:columns fo:column-count="2" fo:column-gap="0in">'.
						   '<style:column style:rel-width="4818*" fo:start-indent="0in" fo:end-indent="0in" /> '.
						   '<style:column style:rel-width="4819*" fo:start-indent="0in" fo:end-indent="0in" /> '.
						  '</style:columns>'.
						 '</style:section-properties>'.
						'</style:style>';
					$doc->replaceElement($element,$doc->createElement($stylexml));
				}
			}
		} else {
			if (not $docstyle->getStyleElement($style)) {
				print STDERR "\n    adding style $style" if ($self->{'props'}{'debug'});
				$docstyle->createStyle($style, family => $styles->{$style});
			}
		}
	}

	$doc->save();
	print "\nSaved file: " . $doc->{file};

	# clean up all the variables, styles, etc.
	$self->{'doc'} = "";
	$self->{'styles'} = {};
	$self->{'xml'} = "";
	$self->{'curr_para'} = 0;
	$self->{'curr_sect'} = 0;

	print STDERR "\n/close_document\n" if ($self->{'props'}{'debug'});
}

sub outputXML
{
    my ($self,$close_sect) = @_;

	print STDERR "\noutputXML: $close_sect" if ($self->{'props'}{'debug'} > 1);

	if ($self->{'curr_para'}) {
		$self->{'xml'} .= "</text:p>";
		$self->{'curr_para'} = 0;
	}

	if ($close_sect && $self->{'curr_sect'}) {
		$self->{'xml'} .= "</text:section>";
		$self->{'curr_sect'} = 0;
	}


	if (!$self->{'curr_sect'} && $self->{'xml'}) {
		print STDERR "\n  XML: " . $self->{'xml'} if ($self->{'props'}{'debug'} > 1);
		$self->{'cur'} = $self->{'doc'}->insertElement($self->{'cur'}, $self->{'xml'}, position => 'after');
		$self->{'xml'} = '';
	}

}

%esc = (
    '&' => '&amp;',
    '>' => '&gt;',
    '<' => '&lt;',
    "'" => '&apos;',
    '"' => '&quot;'
    );
$esc = join("", keys %esc);

sub xmlescape
{
    my ($str) = @_;
    $str =~ s/([$esc])/$esc{$1}/oge;
    $str;
}


1;
