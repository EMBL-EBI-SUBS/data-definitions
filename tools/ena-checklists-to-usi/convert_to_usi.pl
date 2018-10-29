#! /usr/bin/env perl
use strict;
use warnings;

use Data::Dumper;
use IPC::Open2;

use REST::Client;
use JSON::MaybeXS;
use XML::Fast;

my $true  = JSON()->true;
my $false = JSON()->false;

my ($accession) = @ARGV;

my $ena_checklist = load_checklist($accession);
my $schema        = checkist_2_schema($ena_checklist);
my $template      = checklist_2_template($ena_checklist);

my $usi_checklist = {
    _id         => $ena_checklist->{IDENTIFIERS}{PRIMARY_ID},
    dataTypeId  => 'samples',
    displayName => $ena_checklist->{DESCRIPTOR}{LABEL},
    description => $ena_checklist->{DESCRIPTOR}{DESCRIPTION},

    validationSchema    => $schema,
    spreadsheetTemplate => $template
};

print_as_json($usi_checklist);

sub load_checklist {
    my ($accession) = @_;

    my $client = REST::Client->new();
    $client->GET("https://www.ebi.ac.uk/ena/data/view/$accession&display=xml");
    my $xml = xml2hash $client->responseContent();

    my $checklist = $xml->{ROOT}{CHECKLIST};
    die "no checklist" unless $checklist;

    return $checklist;
}

sub checkist_2_schema {
    my ($checklist) = @_;

    my $schema = initial_schema($checklist);

    my $field_groups = $checklist->{DESCRIPTOR}{FIELD_GROUP};

    for my $field_group (@$field_groups) {
        my $restriction_type = $field_group->{"-restrictionType"};

        # "Any number or none of the fields"
        # "One of the fields"
        # "At least one of the fields"
        # "One or none of the fields"
        die "restriction type '$restriction_type' is not supported yet"
          unless ( $restriction_type eq 'Any number or none of the fields' );

        my $field_group_name = $field_group->{NAME};

        my $fields = $field_group->{FIELD};

        my $required_attributes = $schema->{properties}{attributes}{required};

        if ( ref $fields eq 'HASH' ) {
            $fields = [$fields];
        }

        for my $field (@$fields) {
            my ( $field_name, $field_schema, $required ) =
              convert_field($field);
            $schema->{properties}{attributes}{properties}{$field_name} =
              $field_schema;

            push @$required_attributes, $field_name if ($required);
        }

    }

    return $schema;
}

sub field_capture {
    my ( $fieldName, $required, $fieldType ) = @_;
    my %capture_def = (
        "_class"    => "uk.ac.ebi.subs.repository.model.templates.FieldCapture",
        "fieldName" => undef,
        "fieldType" => "String",
        "required"  => $false
    );
    $capture_def{fieldName} = $fieldName;
    $capture_def{required}  = $required if defined $required;
    $capture_def{fieldType} = $fieldType if defined $fieldType;
    return \%capture_def;
}

sub date_field_capture {
    my ( $fieldName, $required) = @_;
    my %capture_def = (
        "_class"    => "uk.ac.ebi.subs.repository.model.templates.DateFieldCapture",
        "fieldName" => undef,
        "required"  => $false
    );
    $capture_def{fieldName} = $fieldName;
    $capture_def{required}  = $required if defined $required;
    return \%capture_def;
}

sub attribute_capture {
    my ( $required, $allow_units, $allow_terms ) = @_;
    my %attr_capture = (
        "_class" =>
          "uk.ac.ebi.subs.repository.model.templates.AttributeCapture",
        "required"   => $false,
        "allowUnits" => $false,
        "allowTerms" => $false
    );

    $attr_capture{required}   = $required    if defined $required;
    $attr_capture{allowUnits} = $allow_units if defined $allow_units;
    $attr_capture{allowTerms} = $allow_terms if defined $allow_terms;

    return \%attr_capture;

}

sub checklist_2_template {
    my ($checklist) = @_;

    my @columnCaptures = (
        { key => "alias", value => field_capture( 'alias', $true ) },
        { key => "title", value => field_capture( 'title', $true ) },
        {
            key   => "description",
            value => field_capture( 'description', $false )
        },
        {
            key   => "release date",
            value => date_field_capture( 'releaseDate', $true )
        },
        { key => "taxon", value => field_capture( 'taxon', $true ) },
        {
            key   => "taxon id",
            value => field_capture( 'taxonId', $true, 'IntegerNumber' )
        }
    );

    my $template = {
        "columnCaptures" => \@columnCaptures,
        "defaultCapture" => attribute_capture()
    };

    my $field_groups = $checklist->{DESCRIPTOR}{FIELD_GROUP};

    for my $field_group (@$field_groups) {

        my $field_group_name = $field_group->{NAME};

        my $fields = $field_group->{FIELD};

        if ( ref $fields eq 'HASH' ) {
            $fields = [$fields];
        }

        for my $field (@$fields) {
            my $name = $field->{NAME};
            my $required =
              ( $field->{MANDATORY} eq 'mandatory' ) ? $true : $false;

            my $capture = attribute_capture($required);

            $capture->{description} = $field->{DESCRIPTION}
              if defined $field->{DESCRIPTION};


        # we represent column captures as an array of objects,
        # but we will reshape it to an object in the print method,
        # because the order matters and perl cannot preserve key order
              
            push @columnCaptures, { key => $name, value => $capture };
        }

    }

    return $template;
}

sub convert_field {
    my ($field) = @_;

    my $multiplicity = $field->{MULTIPLICITY};    #single, multiple;
    my $label        = $field->{LABEL};
    my $description  = $field->{DESCRIPTION};
    my $mandatory  = $field->{MANDATORY};    #mandatory, recommended or optional
    my $name       = $field->{NAME};
    my $field_type = $field->{FIELD_TYPE};
    my $units      = $field->{UNITS};

    my $required = ( $mandatory eq 'mandatory' );

    my $field_schema = { description => $description, };

    if ( $multiplicity eq 'single' ) {
        $field_schema->{maxItems} = 1;
    }

    my $properties = $field_schema->{items}{properties};
    my $value      = $properties->{value};

    if ( exists $field_type->{TEXT_FIELD} ) {
        build_text_requirement( $field_type->{TEXT_FIELD}, $value );
    }
    elsif ( exists $field_type->{TEXT_AREA_FIELD} ) {
        build_text_requirement( $field_type->{TEXT_AREA_FIELD}, $value );
    }
    elsif ( exists $field_type->{TEXT_CHOICE_FIELD} ) {
        build_enum_requirement( $field_type->{TEXT_CHOICE_FIELD}, $value );
    }
    elsif ( exists $field_type->{DATE_FIELD} ) {
        build_date_requirement( $field_type->{DATE_FIELD}, $value );
    }
    elsif ( exists $field_type->{TAXON_FIELD} ) {

        # TAXON_FIELD
        #   TAXON
        #
        die "we don't support TAXON_FIELD yet";
    }
    elsif ( exists $field_type->{ONTOLOGY_FIELD} ) {
        build_ontology_requirement( $field_type->{ONTOLOGY_FIELD}, $value );
    }

    if ($units) {
        if ( ref $units eq 'HASH' ) {
            $units = [$units];
        }

        my @valid_units = map { $_->{UNIT} } @$units;

        $properties->{units}{enum} = \@valid_units;

        push @{ $field_schema->{items}{required} }, 'units';
    }

    return ( $name, $field_schema, $required );
}

sub build_text_requirement {
    my ( $type_def, $value ) = @_;

    if ( ref $type_def eq 'HASH' ) {

        if ( defined $type_def->{MIN_LENGTH} ) {
            $value->{minLength} = $type_def->{MIN_LENGTH};
        }

        if ( defined $type_def->{MAX_LENGTH} ) {
            $value->{maxLength} = $type_def->{MAX_LENGTH};
        }

        if ( defined $type_def->{REGEX_VALUE} ) {
            $value->{pattern} = $type_def->{REGEX_VALUE};
        }
    }
}

sub build_ontology_requirement {
    my ( $type_def, $value ) = @_;

    $value->{type}        = 'string';
    $value->{format}      = 'uri';
    $value->{isValidTerm} = 'true';
}

sub build_enum_requirement {
    my ( $type_def, $value ) = @_;
    my $text_values = $type_def->{TEXT_VALUE};

    if ( ref $text_values eq 'ARRAY' ) {
        my @valid_values = map { $_->{VALUE} } @$text_values;
        $value->{enum} = \@valid_values;
    }
    elsif ( ref $text_values eq 'HASH' ) {
        $value->{enum} = [ $text_values->{VALUE} ];
    }
    else {
        die "unexpected ref type in enum type def: " . Dumper($type_def);
    }

    # TEXT_CHOICE_FIELD
    #   TEXT_VALUE
    #    VALUE
}

sub build_date_requirement {
    my ( $type_def, $value ) = @_;
    $value->{format} = 'date-time';
}

sub initial_schema {
    my ($checklist) = @_;

    my $accession   = $checklist->{IDENTIFIERS}{PRIMARY_ID};
    my $descriptor  = $checklist->{DESCRIPTOR};
    my $name        = $descriptor->{NAME};
    my $description = $descriptor->{DESCRIPTION};
    my $label       = $descriptor->{LABEL};
    my $authority   = $descriptor->{AUTHORITY};

    my $schema = {
        "id"             => "$accession",
        '#dollar#schema' => "http://json-schema.org/draft-07/schema#",
        '#dollar#async'  => $true,
        "description"    => $description,
        "version"        => "1.0.0",
        "author"         => $authority,
        "type"           => "object",
        "title"          => "$name",
        "required"       => ["attributes"],
        "definitions"    => {
            "terms" => {
                "type"  => "array",
                "items" => {
                    "type"       => "object",
                    "properties" => {
                        "url" => {
                            "type"   => "string",
                            "format" => "uri"
                        }
                    },
                    "required" => ["url"]
                }
            },
            "attribute" => {
                "type"     => "array",
                "minItems" => 1,
                "items"    => {
                    "properties" => {
                        "value" => { "type" => "string", "minLength" => 1 },
                        "units" => { "type" => "string", "minLength" => 1 },
                        "terms" => { '#dollar#ref' => "#/definitions/terms" }
                    },
                    "required" => ["value"]
                }
            },
            "properties" => {
                "attributes" => {
                    "description" => "Attributes for describing a sample.",
                    "type"        => "object",
                    "properties"  => {},
                    "required"    => [],
                    "patternProperties" => {
                        '^#dot#*$' => { '#dollar#ref' => "#/definitions/attribute" }
                    }
                }
            }
        }
    };

    return $schema;
}

sub print_as_json {
    my ($thing) = @_;
    my $json = encode_json($thing);


    # the ordering of column captures matters, but perl can't preserve it, so we use jq 
    # to restructure the document into it's final form
    # This method receives column captures as an array of objects, with the keys 'key' and value
    # jq remaps them to be one object, with the k/v pairs in the same order as the array
    

    my $pid = open2( \*CHILD_OUT, \*CHILD_IN,
'jq \'.spreadsheetTemplate.columnCaptures = reduce .spreadsheetTemplate.columnCaptures[] as $i ({}; .[$i.key] = $i.value)\''
    ) or die "open2() failed $!";

    print CHILD_IN $json;
    close CHILD_IN;

    while (<CHILD_OUT>) {
        print STDOUT $_ . $/;
    }
}

