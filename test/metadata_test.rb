require File.expand_path(File.join(File.dirname(__FILE__), "test_helper"))

class MetadataTest < Test::Unit::TestCase

  def setup
    @settings = OneLogin::RubySaml::Settings.new
    @settings.issuer = "https://example.com"
    @settings.name_identifier_format = "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress"
    @settings.assertion_consumer_service_url = "https://foo.example/saml/consume"
  end

  should "generate Service Provider Metadata with X509Certificate" do
    @settings.sign_request = true
    @settings.certificate = ruby_saml_cert

    xml_text = OneLogin::RubySaml::Metadata.new.generate(@settings)

    # assert xml_text can be parsed into an xml doc
    xml_doc = REXML::Document.new(xml_text)

    spsso_descriptor = REXML::XPath.first(xml_doc, "//md:SPSSODescriptor")
    assert_equal "true", spsso_descriptor.attribute("AuthnRequestsSigned").value

    cert_node = REXML::XPath.first(xml_doc, "//md:KeyDescriptor/ds:KeyInfo/ds:X509Data/ds:X509Certificate", {
      "md" => "urn:oasis:names:tc:SAML:2.0:metadata",
      "ds" => "http://www.w3.org/2000/09/xmldsig#"
    })
    cert_text = cert_node.text
    cert = OpenSSL::X509::Certificate.new(Base64.decode64(cert_text))
    assert_equal ruby_saml_cert.to_der, cert.to_der
  end

  should "should generate Service Provider Metadata" do
    settings = OneLogin::RubySaml::Settings.new
    settings.issuer = "https://example.com"
    settings.name_identifier_format = "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress"
    settings.assertion_consumer_service_url = "https://foo.example/saml/consume"

    xml_text = OneLogin::RubySaml::Metadata.new.generate(settings)

    # assert correct xml declaration
    start = "<?xml version='1.0' encoding='UTF-8'?>\n<md:EntityDescriptor"
    assert xml_text[0..start.length-1] == start

    # assert xml_text can be parsed into an xml doc
    xml_doc = REXML::Document.new(xml_text)

    assert_equal "https://example.com", REXML::XPath.first(xml_doc, "//md:EntityDescriptor").attribute("entityID").value

    spsso_descriptor = REXML::XPath.first(xml_doc, "//md:SPSSODescriptor")
    assert_equal "urn:oasis:names:tc:SAML:2.0:protocol", spsso_descriptor.attribute("protocolSupportEnumeration").value
    assert_equal "false", spsso_descriptor.attribute("AuthnRequestsSigned").value
    assert_equal "false", spsso_descriptor.attribute("WantAssertionsSigned").value

    assert_equal "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress", REXML::XPath.first(xml_doc, "//md:NameIDFormat").text.strip

    acs = REXML::XPath.first(xml_doc, "//md:AssertionConsumerService")
    assert_equal "urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST", acs.attribute("Binding").value
    assert_equal "https://foo.example/saml/consume", acs.attribute("Location").value
  end
end
