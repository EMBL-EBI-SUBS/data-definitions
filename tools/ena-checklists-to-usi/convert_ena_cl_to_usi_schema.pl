#! /usr/bin/env perl
use strict;
use warnings;

use Data::Dumper;
use IPC::Open2;

use REST::Client;
use JSON::MaybeXS;
use XML::Fast;

use open qw(:std :utf8);

my $true  = JSON()->true;
my $false = JSON()->false;

my ($accession) = @ARGV;

my $ena_checklist = load_checklist($accession);
my $schema        = checkist_2_schema($ena_checklist);

print(JSON->new->pretty->encode($schema));

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

        my $required_attributes = [];

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

        push @{$schema->{properties}{attributes}{required}}, flat($required_attributes);
    }

    return $schema;
}

sub convert_field {
    my ($field) = @_;

    my $multiplicity = $field->{MULTIPLICITY};    #single, multiple;
    my $label        = $field->{LABEL};
    my $description  = defined $field->{DESCRIPTION} ? $field->{DESCRIPTION} : "";
    my $mandatory  = $field->{MANDATORY};    #mandatory, recommended or optional
    my $name       = $field->{NAME};
    my $field_type = $field->{FIELD_TYPE};
    my $units      = $field->{UNITS};

    my $required =
              ( $field->{MANDATORY} eq 'mandatory' ) ? $true : $false;

    my $field_schema = { description => $description, };

    if ( $multiplicity eq 'single' ) {
        $field_schema->{maxItems} = 1;
    }

    my $properties = $field_schema->{items}{properties};
    $properties->{value} = {};
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
        build_taxon_requirement($value);
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

    if (defined $value && keys %$value) {
        $field_schema->{items}{properties}{value} = $value;
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

sub build_taxon_requirement {
    my ( $value ) = @_;

    $value->{isValidTaxonomy} = 'true';
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
        '$id'             => "$accession",
        '$schema' => "http://json-schema.org/draft-07/schema#",
        '$async'  => $true,
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
                        "terms" => { '$ref' => "#/definitions/terms" }
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
                        '^.*$' => { '$ref' => "#/definitions/attribute" }
                    }
                }
            }
        }
    };

    return $schema;
}

sub flat {  # no prototype for this one to avoid warnings
    return map { ref eq 'ARRAY' ? flat(@$_) : $_ } @_;
}
