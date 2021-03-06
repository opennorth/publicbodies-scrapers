require 'bundler/setup'

require 'csv'
require 'tempfile'

require 'copy_paste_pdf'
require 'govkit-ca'
require 'pupa'
require 'vcard'

module OrganizationHelper
  POSTAL_CODE_RE = /\b[A-Z]\d[A-Z]\s*\d[A-Z]\d\b/

  # @see http://www.bt-tb.tpsgc-pwgsc.gc.ca/btb.php?lang=eng&cont=044
  def tel(string)
    string.to_s.gsub(/\D/, '').sub(/\A(\d{3})(\d{3})(\d{4})\z/, '\1-\2-\3')
  end

  # @see http://www.canadapost.ca/tools/pg/manual/PGaddress-e.asp#1417000
  def adr(string)
    string.to_s.strip.sub(/[\s,]+(AB|BC|MB|ON|NB|NL|NS|NT|NU|PE|QC|SK|YT)[\s,]+(#{POSTAL_CODE_RE})\z/, ' \1  \2')
  end

  def valid_postal_code?(string)
    postal_code = string.to_s[POSTAL_CODE_RE]
    if postal_code
      GovKit::CA::PostalCode.valid?(GovKit::CA::PostalCode.format_postal_code(postal_code))
    else
      warn("Missing or invalid postal code in #{string}")
    end
  end
end

class OrganizationProcessor < Pupa::Processor
  class_attribute :jurisdiction_code

  include OrganizationHelper

  def tempfile
    Tempfile.open('pupa') do |f|
      f.binmode
      f.write yield
      f
    end
  end

  def documents
    Pupa.session['organizations'].find('extras.jurisdiction_code' => self.class.jurisdiction_code)
  end

  # @see https://github.com/okfn/publicbodies/blob/master/datapackage.json
  def public_bodies
    puts CSV.generate_line %w(
      id
      name
      abbreviation
      other_names
      description
      classification
      parent_id
      founding_date
      dissolution_date
      image
      url
      jurisdiction_code
      email
      address
      contact
      tags
      source_url
    )

    documents.each do |document|
      organization = Pupa::Organization.new(document)

      email = organization.contact_details.email
      if email.nil? && organization.extras[:contact_point]
        email = organization.extras[:contact_point].find{|person|
          person[:email]
        }.try{|person|
          person[:email]
        }
      end

      address = organization.contact_details.address
      if address.nil? && organization.extras[:contact_point]
        address = organization.extras[:contact_point].find{|person|
          person[:address]
        }.try{|person|
          person[:address]
        }
      end

      puts CSV.generate_line [
        organization._id,
        organization.name,
        nil,
        nil,
        nil,
        organization.classification,
        organization.parent_id,
        nil,
        nil,
        nil,
        nil,
        self.class.jurisdiction_code,
        email,
        address,
        nil,
        nil,
        organization.sources[0].try{|source| source[:url]},
      ]
    end
  end

  def nomenklatura
    documents.each do |document|
      organization = Pupa::Organization.new(document)

      puts CSV.generate_line [
        organization.name,
      ]
    end
  end

  # @see https://github.com/mysociety/alaveteli/blob/905655c7a37b6159b1468ef455ae2a179b6f9069/app/models/public_body.rb#L422
  def alaveteli
    puts CSV.generate_line [
      '#id',
      'name',
      'request_email',
    ]

    documents.each do |document|
      organization = Pupa::Organization.new(document)

      puts CSV.generate_line [
        organization._id,
        organization.name,
        organization.contact_details.email,
      ]
    end
  end
end

def run(processor)
  runner = Pupa::Runner.new(processor, database: 'publicbodies', expires_in: 604800) # 1 week
  runner.add_action(name: 'alaveteli', description: "Output CSV in Alaveteli format")
  runner.add_action(name: 'nomenklatura', description: "Output CSV in Nomenklatura format")
  runner.add_action(name: 'public_bodies', description: "Output CSV in publicbodies.org format")
  runner.run(ARGV)
end

OrganizationProcessor.add_scraping_task(:organizations)
