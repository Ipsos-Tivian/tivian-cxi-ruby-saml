require "xml_security"
require "onelogin/ruby-saml/attributes"

require "time"
require "nokogiri"

# Only supports SAML 2.0
module OneLogin
  module RubySaml

    # SAML2 Authentication Response. SAML Response
    #
    class Response < SamlMessage
      ASSERTION = "urn:oasis:names:tc:SAML:2.0:assertion"
      PROTOCOL  = "urn:oasis:names:tc:SAML:2.0:protocol"
      DSIG      = "http://www.w3.org/2000/09/xmldsig#"

      # TODO: Settings should probably be initialized too... WDYT?

      # OneLogin::RubySaml::Settings Toolkit settings
      attr_accessor :settings

      # Array with the causes [Array of strings]
      attr_accessor :errors

      attr_reader :document
      attr_reader :response
      attr_reader :options

      attr_accessor :soft

      # Constructs the SAML Response. A Response Object that is an extension of the SamlMessage class.
      # @param response [String] A UUEncoded SAML response from the IdP.
      # @param options  [Hash]   :settings to provide the OneLogin::RubySaml::Settings object 
      #                          Or some options for the response validation process like skip the conditions validation
      #                          with the :skip_conditions, or allow a clock_drift when checking dates with :allowed_clock_drift
      #                          or :matches_request_id that will validate that the response matches the ID of the request.
      def initialize(response, options = {})
        @errors = []

        raise ArgumentError.new("Response cannot be nil") if response.nil?
        @options  = options

        @soft = true
        if !options.empty? && !options[:settings].nil?
          @settings = options[:settings]
          if !options[:settings].soft.nil? 
            @soft = options[:settings].soft
          end
        end

        @response = decode_raw_saml(response)
        @document = XMLSecurity::SignedDocument.new(@response, @errors)
      end

      # Append the cause to the errors array, and based on the value of soft, return false or raise
      # an exception
      def append_error(error_msg)
        @errors << error_msg
        return soft ? false : validation_error(error_msg)
      end

      # Reset the errors array
      def reset_errors!
        @errors = []
      end

      # Validates the SAML Response with the default values (soft = true)
      # @return [Boolean] TRUE if the SAML Response is valid
      #
      def is_valid?
        validate
      end

      # @return [String] the NameID provided by the SAML response from the IdP.
      #
      def name_id
        @name_id ||= begin
          node = xpath_first_from_signed_assertion('/a:Subject/a:NameID')
          node.nil? ? nil : node.text
        end
      end

      # Gets the SessionIndex from the AuthnStatement.
      # Could be used to be stored in the local session in order
      # to be used in a future Logout Request that the SP could
      # send to the IdP, to set what specific session must be deleted
      # @return [String] SessionIndex Value
      #
      def sessionindex
        @sessionindex ||= begin
          node = xpath_first_from_signed_assertion('/a:AuthnStatement')
          node.nil? ? nil : node.attributes['SessionIndex']
        end
      end

      # Gets the Attributes from the AttributeStatement element.
      #
      # All attributes can be iterated over +attributes.each+ or returned as array by +attributes.all+
      # For backwards compatibility ruby-saml returns by default only the first value for a given attribute with
      #    attributes['name']
      # To get all of the attributes, use:
      #    attributes.multi('name')
      # Or turn off the compatibility:
      #    OneLogin::RubySaml::Attributes.single_value_compatibility = false
      # Now this will return an array:
      #    attributes['name']
      #
      # @return [Attributes] OneLogin::RubySaml::Attributes enumerable collection.
      #      
      def attributes
        @attr_statements ||= begin
          attributes = Attributes.new

          stmt_element = xpath_first_from_signed_assertion('/a:AttributeStatement')
          return attributes if stmt_element.nil?

          stmt_element.elements.each do |attr_element|
            name  = attr_element.attributes["Name"]
            values = attr_element.elements.collect{|e|
              # SAMLCore requires that nil AttributeValues MUST contain xsi:nil XML attribute set to "true" or "1"
              # otherwise the value is to be regarded as empty.
              ["true", "1"].include?(e.attributes['xsi:nil']) ? nil : e.text.to_s
            }

            attributes.add(name, values)
          end

          attributes
        end
      end

      # Gets the SessionNotOnOrAfter from the AuthnStatement.
      # Could be used to set the local session expiration (expire at latest)
      # @return [String] The SessionNotOnOrAfter value
      #
      def session_expires_at
        @expires_at ||= begin
          node = xpath_first_from_signed_assertion('/a:AuthnStatement')
          node.nil? ? nil : parse_time(node, "SessionNotOnOrAfter")
        end
      end

      # Checks if the Status has the "Success" code
      # @return [Boolean] True if the StatusCode is Sucess
      # 
      def success?
        status_code == "urn:oasis:names:tc:SAML:2.0:status:Success"
      end

      # @return [String] StatusCode value from a SAML Response.
      #
      def status_code
        @status_code ||= begin
          node = REXML::XPath.first(
            document,
            "/p:Response/p:Status/p:StatusCode",
            { "p" => PROTOCOL, "a" => ASSERTION }
          )
          node.attributes["Value"] if node && node.attributes
        end
      end

      # @return [String] the StatusMessage value from a SAML Response.
      #
      def status_message
        @status_message ||= begin
          node = REXML::XPath.first(
            document,
            "/p:Response/p:Status/p:StatusMessage",
            { "p" => PROTOCOL, "a" => ASSERTION }
          )
          node.text if node
        end
      end

      # Gets the Condition Element of the SAML Response if exists.
      # (returns the first node that matches the supplied xpath)
      # @return [REXML::Element] Conditions Element if exists
      #
      def conditions
        @conditions ||= xpath_first_from_signed_assertion('/a:Conditions')
      end

      # Gets the NotBefore Condition Element value.
      # @return [Time] The NotBefore value in Time format
      #
      def not_before
        @not_before ||= parse_time(conditions, "NotBefore")
      end

      # Gets the NotOnOrAfter Condition Element value.
      # @return [Time] The NotOnOrAfter value in Time format
      #
      def not_on_or_after
        @not_on_or_after ||= parse_time(conditions, "NotOnOrAfter")
      end

      # Gets the Issuers (from Response and Assertion).
      # (returns the first node that matches the supplied xpath from the Response and from the Assertion)
      # @return [Array] Array with the Issuers (REXML::Element)
      #
      def issuers
        @issuers ||= begin
          issuers = []
          nodes = REXML::XPath.match(
            document,
            "/p:Response/a:Issuer | /p:Response/a:Assertion/a:Issuer",
            { "p" => PROTOCOL, "a" => ASSERTION }
          )
          nodes.each do |node|
            issuers << node.text if node.text
          end
          issuers.uniq
        end
      end

      # @return [String|nil] The InResponseTo attribute from the SAML Response.
      #
      def in_response_to
        @in_response_to ||= begin
          node = REXML::XPath.first(
            document,
            "/p:Response",
            { "p" => PROTOCOL }
          )
          node.nil? ? nil : node.attributes['InResponseTo']
        end
      end

      # @return [Array] The Audience elements from the Contitions of the SAML Response.
      #
      def audiences
        @audiences ||= begin
          audiences = []
          nodes = xpath_from_signed_assertion('/a:Conditions/a:AudienceRestriction/a:Audience')
          nodes.each do |node|
            if node && node.text
              audiences << node.text
            end
          end
          audiences
        end
      end

      # returns the allowed clock drift on timing validation
      # @return [Integer]
      def allowed_clock_drift
        return options[:allowed_clock_drift] || 0
      end

      private

      # Validates the SAML Response (calls several validation methods)
      # @return [Boolean] True if the SAML Response is valid, otherwise False if soft=True
      # @raise [ValidationError] if soft == false and validation fails
      #
      def validate
        reset_errors!

        validate_response_state &&
        validate_id &&
        validate_version &&
        validate_success_status &&
        validate_num_assertion &&
        validate_no_encrypted_attributes &&
        validate_signed_elements &&
        validate_structure &&
        validate_in_response_to &&
        validate_conditions &&
        validate_audience &&
        validate_issuer &&
        validate_session_expiration &&
        validate_subject_confirmation &&
        validate_signature
      end


      # Validates the Status of the SAML Response
      # @return [Boolean] True if the SAML Response contains a Success code, otherwise False if soft == false
      # @raise [ValidationError] if soft == false and validation fails
      #
      def validate_success_status
        return true if success?
          
        error_msg = 'The status code of the Response was not Success'
        status_error_msg = OneLogin::RubySaml::Utils.status_error_msg(error_msg, status_code, status_message)
        append_error(status_error_msg)
      end

      # Validates the SAML Response against the specified schema.
      # @return [Boolean] True if the XML is valid, otherwise False if soft=True
      # @raise [ValidationError] if soft == false and validation fails 
      #
      def validate_structure
        unless valid_saml?(document, soft)
          return append_error("Invalid SAML Response. Not match the saml-schema-protocol-2.0.xsd")
        end

        true
      end

      # Validates that the SAML Response provided in the initialization is not empty,
      # also check that the setting and the IdP cert were also provided
      # @param soft [Boolean] soft Enable or Disable the soft mode (In order to raise exceptions when the response is invalid or not)
      # @return [Boolean] True if the required info is found, otherwise False if soft=True
      # @raise [ValidationError] if soft == false and validation fails
      #
      def validate_response_state(soft = true)
        return append_error("Blank response") if response.nil? || response.empty?

        return append_error("No settings on response") if settings.nil?

        if settings.idp_cert_fingerprint.nil? && settings.idp_cert.nil?
          return append_error("No fingerprint or certificate on settings")
        end

        true
      end

      # Validates that the SAML Response contains an ID 
      # If fails, the error is added to the errors array.
      # @return [Boolean] True if the SAML Response contains an ID, otherwise returns False
      #
      def validate_id
        unless id(document)
          return append_error("Missing ID attribute on SAML Response")
        end

        true
      end

      # Validates the SAML version (2.0)
      # If fails, the error is added to the errors array.
      # @return [Boolean] True if the SAML Response is 2.0, otherwise returns False
      #
      def validate_version
        unless version(document) == "2.0"
          return append_error("Unsupported SAML version")
        end

        true
      end

      # Validates that the SAML Response only contains a single Assertion (encrypted or not).
      # If fails, the error is added to the errors array.
      # @return [Boolean] True if the SAML Response contains one unique Assertion, otherwise False
      #
      def validate_num_assertion
        assertions = REXML::XPath.match(
          document,
          "//a:Assertion",
          { "a" => ASSERTION }
        )
        encrypted_assertions = REXML::XPath.match(
          document,
          "//a:EncryptedAssertion",
          { "a" => ASSERTION }
        )

        unless assertions.size + encrypted_assertions.size == 1
          return append_error("SAML Response must contain 1 assertion")
        end

        true
      end

      # Validates that there are not EncryptedAttribute (not supported)
      # If fails, the error is added to the errors array
      # @return [Boolean] True if there are no EncryptedAttribute elements, otherwise False if soft=True
      # @raise [ValidationError] if soft == false and validation fails
      #
      def validate_no_encrypted_attributes
        nodes = REXML::XPath.match(
          document,
          "/p:Response/a:Assertion/a:AttributeStatement/a:EncryptedAttribute",
          { "p" => PROTOCOL, "a" => ASSERTION }
        )
        if nodes && nodes.length > 0
          return append_error("There is an EncryptedAttribute in the Response and this SP not support them")
        end

        true
      end


      # Validates the Signed elements
      # If fails, the error is added to the errors array
      # @return [Boolean] True if there is 1 or 2 Elements signed in the SAML Response
      #                                   an are a Response or an Assertion Element, otherwise False if soft=True
      #
      def validate_signed_elements
        signature_nodes = REXML::XPath.match(
          document,
          "//ds:Signature",
          {"ds"=>DSIG}
        )
        signed_elements = []
        signature_nodes.each do |signature_node|
          signed_element = signature_node.parent.name
          if signed_element != 'Response' && signed_element != 'Assertion'
            return append_error("Found an unexpected Signature Element. SAML Response rejected")
          end
          signed_elements << signed_element
        end

        unless signature_nodes.length < 3 && !signed_elements.empty?
          return append_error("Found an unexpected number of Signature Element. SAML Response rejected")
        end

        true
      end

      # Validates if the provided request_id match the inResponseTo value.
      # If fails, the error is added to the errors array
      # @return [Boolean] True if there is no request_id or it match, otherwise False if soft=True
      # @raise [ValidationError] if soft == false and validation fails
      #
      def validate_in_response_to
        return true unless options.has_key? :matches_request_id
        return true if options[:matches_request_id].nil? || options[:matches_request_id].empty?
        return true unless options[:matches_request_id] != in_response_to

        error_msg = "The InResponseTo of the Response: #{in_response_to}, does not match the ID of the AuthNRequest sent by the SP: #{options[:matches_request_id]}"
        append_error(error_msg)
      end

      # Validates the Audience, (If the Audience match the Service Provider EntityID)
      # If fails, the error is added to the errors array
      # @return [Boolean] True if there is an Audience Element that match the Service Provider EntityID, otherwise False if soft=True
      # @raise [ValidationError] if soft == false and validation fails
      #
      def validate_audience
        return true if audiences.empty? || settings.issuer.nil? || settings.issuer.empty?

        unless audiences.include? settings.issuer
          error_msg = "#{settings.issuer} is not a valid audience for this Response"
          return append_error(error_msg)
        end

        true
      end

      # Validates the Conditions. (If the response was initialized with the :skip_conditions option, this validation is skipped,
      # If the response was initialized with the :allowed_clock_drift option, the timing validations are relaxed by the allowed_clock_drift value)
      # @return [Boolean] True if satisfies the conditions, otherwise False if soft=True
      # @raise [ValidationError] if soft == false and validation fails
      #
      def validate_conditions
        return true if conditions.nil?
        return true if options[:skip_conditions]

        now = Time.now.utc

        if not_before && (now + (options[:allowed_clock_drift] || 0)) < not_before
          error_msg = "Current time is earlier than NotBefore condition #{(now + (options[:allowed_clock_drift] || 0))} < #{not_before})"
          return append_error(error_msg)
        end

        if not_on_or_after && now >= not_on_or_after
          error_msg = "Current time is on or after NotOnOrAfter condition (#{now} >= #{not_on_or_after})"
          return append_error(error_msg)
        end

        true
      end

      # Validates the Issuer (Of the SAML Response and the SAML Assertion)
      # @param soft [Boolean] soft Enable or Disable the soft mode (In order to raise exceptions when the response is invalid or not)
      # @return [Boolean] True if the Issuer matchs the IdP entityId, otherwise False if soft=True
      # @raise [ValidationError] if soft == false and validation fails
      #
      def validate_issuer
        return true if settings.idp_entity_id.nil?

        issuers.each do |issuer|
          unless URI.parse(issuer) == URI.parse(settings.idp_entity_id)
            error_msg = "Doesn't match the issuer, expected: <#{settings.idp_entity_id}>, but was: <#{issuer}>"
            return append_error(error_msg)
          end
        end

        true
      end

      # Validates that the Session haven't expired (If the response was initialized with the :allowed_clock_drift option,
      # this time validation is relaxed by the allowed_clock_drift value)
      # If fails, the error is added to the errors array
      # @param soft [Boolean] soft Enable or Disable the soft mode (In order to raise exceptions when the response is invalid or not)
      # @return [Boolean] True if the SessionNotOnOrAfter of the AttributeStatement is valid, otherwise (when expired) False if soft=True
      # @raise [ValidationError] if soft == false and validation fails
      #
      def validate_session_expiration(soft = true)
        return true if session_expires_at.nil?

        now = Time.now.utc
        unless session_expires_at > (now + allowed_clock_drift)
          error_msg = "The attributes have expired, based on the SessionNotOnOrAfter of the AttributeStatement of this Response"
          return append_error(error_msg)
        end

        true
      end

      # Validates if exists valid SubjectConfirmation (If the response was initialized with the :allowed_clock_drift option,
      # timimg validation are relaxed by the allowed_clock_drift value)
      # If fails, the error is added to the errors array
      # @return [Boolean] True if exists a valid SubjectConfirmation, otherwise False if soft=True
      # @raise [ValidationError] if soft == false and validation fails
      #
      def validate_subject_confirmation
        valid_subject_confirmation = false

        subject_confirmation_nodes = xpath_from_signed_assertion('/a:Subject/a:SubjectConfirmation')
        
        now = Time.now.utc
        subject_confirmation_nodes.each do |subject_confirmation|
          if subject_confirmation.attributes.include? "Method" and subject_confirmation.attributes['Method'] != 'urn:oasis:names:tc:SAML:2.0:cm:bearer'
            next
          end

          confirmation_data_node = REXML::XPath.first(
            subject_confirmation,
            'a:SubjectConfirmationData',
            { "a" => ASSERTION }
          )

          next unless confirmation_data_node

          attrs = confirmation_data_node.attributes
          next if (attrs.include? "InResponseTo" and attrs['InResponseTo'] != in_response_to) ||
                  (attrs.include? "NotOnOrAfter" and (parse_time(confirmation_data_node, "NotOnOrAfter") + allowed_clock_drift) <= now) ||
                  (attrs.include? "NotBefore" and parse_time(confirmation_data_node, "NotBefore") > (now + allowed_clock_drift))
          
          valid_subject_confirmation = true
          break
        end

        if !valid_subject_confirmation
          error_msg = "A valid SubjectConfirmation was not found on this Response"
          return append_error(error_msg)
        end

        true
      end

      # Validates the Signature
      # @return [Boolean] True if not contains a Signature or if the Signature is valid, otherwise False if soft=True
      # @raise [ValidationError] if soft == false and validation fails
      #
      def validate_signature
        unless document.validate_document(settings.get_fingerprint, soft, :fingerprint_alg => settings.idp_cert_fingerprint_algorithm)
          error_msg = "Invalid Signature on SAML Response"
          return append_error(error_msg)
        end

        true
      end

      # Extracts the first appearance that matchs the subelt (pattern)
      # Search on any Assertion that is signed, or has a Response parent signed
      # @param subelt [String] The XPath pattern
      # @return [REXML::Element | nil] If any matches, return the Element
      #
      def xpath_first_from_signed_assertion(subelt=nil)
        node = REXML::XPath.first(
            document,
            "/p:Response/a:Assertion[@ID=$id]#{subelt}",
            { "p" => PROTOCOL, "a" => ASSERTION },
            { 'id' => document.signed_element_id }
        )
        node ||= REXML::XPath.first(
            document,
            "/p:Response[@ID=$id]/a:Assertion#{subelt}",
            { "p" => PROTOCOL, "a" => ASSERTION },
            { 'id' => document.signed_element_id }
        )
        node
      end

      # Extracts all the appearances that matchs the subelt (pattern)
      # Search on any Assertion that is signed, or has a Response parent signed
      # @param subelt [String] The XPath pattern
      # @return [Array of REXML::Element] Return all matches
      #
      def xpath_from_signed_assertion(subelt=nil)
        node = REXML::XPath.match(
            document,
            "/p:Response/a:Assertion[@ID=$id]#{subelt}",
            { "p" => PROTOCOL, "a" => ASSERTION },
            { 'id' => document.signed_element_id }
        )
        node.concat( REXML::XPath.match(
            document,
            "/p:Response[@ID=$id]/a:Assertion#{subelt}",
            { "p" => PROTOCOL, "a" => ASSERTION },
            { 'id' => document.signed_element_id }
        ))
      end

      # Parse the attribute of a given node in Time format
      # @param node [REXML:Element] The node
      # @param attribute [String] The attribute name
      # @return [Time|nil] The parsed value
      #
      def parse_time(node, attribute)
        if node && node.attributes[attribute]
          Time.parse(node.attributes[attribute])
        end
      end
    end
  end
end
